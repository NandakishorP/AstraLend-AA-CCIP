// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Script, console} from "forge-std/Script.sol";
import {BurnMintERC677Helper, BurnMintERC677} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {StableCoin} from "../src/tokens/StableCoin.sol";
import {LpToken} from "../src/tokens/LpTokenContract.sol";
import {GlobalStateManager} from "../src/GSM/GlobalStateManager.sol";
import {Registry} from "../src/AdminRegistry/Registry.sol";
import {InterestRateModel} from "../../src/InterestRate/InterestRateModel.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Vault} from "../src/Vault.sol";
import {CrossChainMessageSender} from "../src/ccip/CrossChainMessageSender.sol";
import {CrossChainMessageReceiver} from "../src/ccip/CrossChainMessageReceiver.sol";
import {CCIPReceiver} from "../src/ccip/CCIPReceiver.sol";
import {CCIPRequestHandler} from "../src/ccip/CCIPRequestHandler.sol";
import {LiquidityController} from "../src/service/LiquidityController.sol";
import {CollateralController} from "../src/service/CollateralController.sol";
import {LoanController} from "../src/service/LoanController.sol";
import {MockCCIPRouter} from "../test/mocks/MockCCIPRouter.sol";

contract DeployChainAScript is Script {
    // CCIP chain selectors for the two networks this protocol spans. On a local
    // node no real router reads them, but the Registry routing lookups and the
    // relayer both key off these values, so they must match the real ones.
    // The hub runs on a dedicated id rather than Sepolia's 11155111. MetaMask
    // reserves that id for its own built-in Sepolia and will not let a custom
    // RPC own it, so gas estimation and balances resolve against the public
    // network instead of the local node. The contracts default to the real
    // testnet ids; `setChainIds` below points this deployment at the local ones.
    uint256 constant ETH_CHAIN_ID = 424242;
    uint256 constant ARB_CHAIN_ID = 421614;
    uint64 constant ETH_CHAIN_SELECTOR = 16015286601757825753;
    uint64 constant ARB_CHAIN_SELECTOR = 3478487238524512106;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    HelperConfig helperConfig;

    function run()
        public
        returns (LendingPoolContract, StableCoin, HelperConfig, LpToken)
    {
        helperConfig = new HelperConfig();
        (
            address wethPriceFeedAddress,
            address wbtcPriceFeedAddress,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];

        priceFeedAddresses = [wethPriceFeedAddress, wbtcPriceFeedAddress];

        vm.startBroadcast(deployerKey);
        InterestRateModel interestRateModel = new InterestRateModel();

        LpToken lpToken = new LpToken();
        StableCoin stableCoin = new StableCoin();
        Registry registry = new Registry();

        // `initialize` uses this list to populate s_AllowedChains, which the
        // `isChainAllowed` modifier gates deposits and borrows on. It must hold
        // real chain ids — filling it with loop indices whitelists chains 0 and
        // 1, and every user action reverts with InvalidChainId.
        uint64[] memory chainId = new uint64[](2);
        chainId[0] = uint64(ETH_CHAIN_ID);
        chainId[1] = uint64(ARB_CHAIN_ID);

        GlobalStateManager GSM = new GlobalStateManager(
            address(registry),
            address(interestRateModel)
        );

        LendingPoolContract lendingPoolContract = new LendingPoolContract();
        ProxyAdmin proxyAdmin = new ProxyAdmin(vm.addr(deployerKey));

        // The proxy is deployed *before* everything that talks to the pool, and
        // initialised at the end. Every peripheral contract takes the pool
        // address in its constructor with no setter, so handing them the
        // implementation would point them at storage that is never written —
        // `getUsdValue` reverts there, which breaks collateral pricing and so
        // breaks borrowing. Handing over the proxy is what makes those reads work.
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(lendingPoolContract),
            address(proxyAdmin),
            ""
        );
        address poolAddress = address(proxy);

        Vault vault = new Vault(poolAddress, address(stableCoin));

        // There is no CCIP router on a bare local node, so a mock stands in for
        // it: it charges a fee, assigns a message id and emits the event the
        // off-chain relayer watches. On a real network this is replaced with the
        // network's Router address and a LINK token address.
        MockCCIPRouter router = new MockCCIPRouter();
        CrossChainMessageSender crossChainMessageSender = new CrossChainMessageSender(
                address(lpToken), // link — unused, native-token fees only
                address(router)
            );
        CCIPRequestHandler ccipRequestHandler = new CCIPRequestHandler(
            poolAddress,
            address(registry),
            address(GSM),
            address(crossChainMessageSender)
        );
        CCIPReceiver ccipReceiver = new CCIPReceiver(
            poolAddress,
            address(registry),
            address(ccipRequestHandler),
            address(lpToken)
        );

        // The receiver only accepts calls from its router, so it must be given
        // the same mock the relayer delivers through.
        CrossChainMessageReceiver crossChainMessageReceiver = new CrossChainMessageReceiver(
                address(router),
                address(ccipReceiver)
            );
        LoanController loanController = new LoanController(
            address(GSM),
            address(GSM),
            poolAddress,
            address(registry),
            address(vault)
        );

        CollateralController collateralController = new CollateralController(
            address(registry),
            address(vault),
            address(GSM),
            poolAddress,
            address(GSM)
        );
        LiquidityController liquidityController = new LiquidityController(
            address(registry),
            poolAddress,
            address(vault),
            address(GSM),
            address(GSM),
            address(lpToken)
        );
        LendingPoolContract pool = LendingPoolContract(payable(poolAddress));

        // Initialise through the proxy now that every collaborator exists.
        pool.initialize(
            tokenAddresses,
            priceFeedAddresses,
            chainId,
            address(stableCoin),
            address(lpToken),
            // `link_` — no LINK token on the local/test network, so the LP token
            // stands in as a placeholder. Native-token CCIP fees are used instead.
            address(lpToken),
            address(GSM), // gsm
            address(registry),
            address(vault),
            address(crossChainMessageSender),
            address(ccipReceiver),
            address(ccipRequestHandler),
            // `stateAggregatorAddress` — the hub chain reads global state straight
            // from the GSM, so it doubles as the aggregator here.
            address(GSM),
            address(crossChainMessageReceiver),
            address(liquidityController),
            address(collateralController),
            address(loanController)
        );

        // ── Post-deploy wiring ────────────────────────────────────────────────
        // Every call below grants one component permission to talk to another.
        // Without it the contracts deploy fine but the first deposit reverts, so
        // this mirrors the authorisation block the integration tests set up —
        // pointed at the proxy, which is the address users actually call.

        address[] memory controllers = new address[](3);
        controllers[0] = address(liquidityController);
        controllers[1] = address(collateralController);
        controllers[2] = address(loanController);

        // Controllers move funds through the vault and send CCIP messages.
        vault.setAuthorizedContracts(controllers, true);
        for (uint256 i = 0; i < controllers.length; i++) {
            crossChainMessageSender.setAllowedCallers(controllers[i], true);
            GSM.setAllowedChains(controllers[i]);
        }

        // The pool and the CCIP request handler both write global state.
        GSM.setAllowedChains(address(proxy));
        GSM.setAllowedChains(address(ccipRequestHandler));

        // The liquidation keeper. `performUpkeep` is permissionless, but the
        // liquidation it triggers writes global state, so whoever runs the
        // keeper must be allow-listed. On a real deployment this is the
        // Chainlink Automation upkeep address; locally it is the deployer.
        GSM.setAllowedChains(vm.addr(deployerKey));
        GSM.setLendingPoolContractAddress(address(proxy));
        GSM.setCrosssChainMessageSenderAddress(address(crossChainMessageSender));

        interestRateModel.setLendingPoolContractAndGSM(
            address(proxy),
            address(GSM)
        );

        // Seed the vault with stablecoin so there is something to lend, and give
        // the deployer a balance for testing — both must happen while the
        // deployer still owns the stablecoin.
        stableCoin.mint(address(vault), 1_000_000e6);
        stableCoin.mint(vm.addr(deployerKey), 100_000e6);

        // Chain ids must be set while the deployer still owns these contracts —
        // the setters are onlyOwner and ownership moves to the pool below.
        GSM.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        liquidityController.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        collateralController.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        loanController.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        ccipReceiver.setChainIds(ETH_CHAIN_ID);
        ccipRequestHandler.setChainIds(ETH_CHAIN_ID);
        pool.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        // `initialize` only wires the GSM on the default hub id, and this
        // deployment runs on its own — so point the pool at it explicitly.
        pool.setGlobalStateManager(address(GSM));

        // ── Ownership handoff ─────────────────────────────────────────────────
        // The LP token is minted and burned by the liquidity controller; every
        // other component is driven by the pool.
        lpToken.transferOwnership(address(liquidityController));
        interestRateModel.transferOwnership(address(proxy));
        stableCoin.transferOwnership(address(proxy));
        crossChainMessageSender.transferOwnership(address(proxy));
        crossChainMessageReceiver.transferOwnership(address(proxy));
        ccipRequestHandler.transferOwnership(address(proxy));
        ccipReceiver.transferOwnership(address(proxy));
        liquidityController.transferOwnership(address(proxy));
        collateralController.transferOwnership(address(proxy));
        loanController.transferOwnership(address(proxy));

        // ── Registry + cross-chain callers ────────────────────────────────────
        pool.setGSMAddress(address(GSM));
        pool.setAllowedCallersFoCrossChainMessageSender(
            address(ccipRequestHandler),
            true
        );
        pool.setAllowedCallersFoCrossChainMessageSender(address(GSM), true);

        registry.setAddress(
            ETH_CHAIN_ID,
            "crossChainMessageSenderAddress",
            address(crossChainMessageSender)
        );
        registry.setAddress(
            ETH_CHAIN_ID,
            "ccipRequestHandlerAddress",
            address(ccipRequestHandler)
        );

        // Chain-id → CCIP selector, for both directions. The controllers look
        // these up on every cross-chain action; leaving them unset routes
        // messages to selector 0 and they are silently lost.
        registry.setDestinationChainSelector(ETH_CHAIN_ID, ETH_CHAIN_SELECTOR);
        registry.setDestinationChainSelector(ARB_CHAIN_ID, ARB_CHAIN_SELECTOR);

        // This chain's own receiver. The counterpart chain's receiver address is
        // not known until it has been deployed, so the two-node bring-up script
        // cross-registers them afterwards.
        registry.setCrossChainRegistryAddress(
            ETH_CHAIN_SELECTOR,
            "crossChainMessageReceiverAddress",
            address(crossChainMessageReceiver)
        );

        // The sender pays CCIP fees out of its own balance, so it needs a float
        // to cover the first messages before user-supplied fees accumulate.
        (bool funded, ) = payable(address(crossChainMessageSender)).call{
            value: 1 ether
        }("");
        require(funded, "failed to fund cross-chain sender");

        vm.stopBroadcast();

        // Parsed by tooling/deploy-local.mjs — keep the "KEY=0x..." shape.
        console.log("DEPLOY lendingPool=%s", address(proxy));
        console.log("DEPLOY vault=%s", address(vault));
        console.log("DEPLOY stableCoin=%s", address(stableCoin));
        console.log("DEPLOY lpToken=%s", address(lpToken));
        console.log("DEPLOY gsm=%s", address(GSM));
        console.log("DEPLOY registry=%s", address(registry));
        console.log("DEPLOY router=%s", address(router));
        console.log("DEPLOY messageSender=%s", address(crossChainMessageSender));
        console.log(
            "DEPLOY messageReceiver=%s",
            address(crossChainMessageReceiver)
        );
        console.log("DEPLOY weth=%s", tokenAddresses[0]);
        console.log("DEPLOY wbtc=%s", tokenAddresses[1]);
        return (lendingPoolContract, stableCoin, helperConfig, lpToken);
    }
}
