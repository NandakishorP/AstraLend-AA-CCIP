// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Script, console} from "forge-std/Script.sol";
import {BurnMintERC677Helper, BurnMintERC677} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {StableCoin} from "../src/tokens/StableCoin.sol";
import {LpToken} from "../src/tokens/LpTokenContract.sol";
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
import {StateAggregator} from "../src/StateMirror/StateAggregator.sol";
import {MockCCIPRouter} from "../test/mocks/MockCCIPRouter.sol";

contract DeployChainBScript is Script {
    // Must match DeployChainA — the Registry routing lookups and the relayer
    // both key off these values.
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

        // Real chain ids, not loop indices — see the matching comment in
        // DeployChainA. These populate s_AllowedChains, which gates every
        // deposit and borrow.
        uint64[] memory chainId = new uint64[](2);
        chainId[0] = uint64(ETH_CHAIN_ID);
        chainId[1] = uint64(ARB_CHAIN_ID);

        LendingPoolContract lendingPoolContract = new LendingPoolContract();
        ProxyAdmin proxyAdmin = new ProxyAdmin(vm.addr(deployerKey));

        // Deployed before its collaborators and initialised at the end — see the
        // matching comment in DeployChainA for why they must hold the proxy
        // address rather than the implementation's.
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(lendingPoolContract),
            address(proxyAdmin),
            ""
        );
        address poolAddress = address(proxy);

        Vault vault = new Vault(poolAddress, address(stableCoin));

        StateAggregator stateAggregator = new StateAggregator();

        // No CCIP router exists on a local node; the mock plays the source side
        // and the off-chain relayer plays the DON. See test/mocks/MockCCIPRouter.
        MockCCIPRouter router = new MockCCIPRouter();
        CrossChainMessageSender crossChainMessageSender = new CrossChainMessageSender(
                address(lpToken), // link — unused, native-token fees only
                address(router)
            );

        CCIPReceiver ccipReceiver = new CCIPReceiver(
            poolAddress,
            address(registry),
            // `ccipRequestHandler` — hub-side only; the satellite never
            // originates the request/response handshake.
            address(lpToken),
            // `stateAggregator` — this is where inbound messages write the
            // mirrored state. Passing anything else (it was the LP token) makes
            // every delivery revert inside the receiver.
            address(stateAggregator)
        );

        CrossChainMessageReceiver crossChainMessageReceiver = new CrossChainMessageReceiver(
                address(router),
                address(ccipReceiver)
            );
        LoanController loanController = new LoanController(
            address(stateAggregator),
            address(stateAggregator),
            poolAddress,
            address(registry),
            address(vault)
        );

        CollateralController collateralController = new CollateralController(
            address(registry),
            address(vault),
            address(stateAggregator),
            poolAddress,
            address(stateAggregator)
        );
        LiquidityController liquidityController = new LiquidityController(
            address(registry),
            poolAddress,
            address(vault),
            address(stateAggregator),
            address(stateAggregator),
            address(lpToken)
        );

        // ── State aggregator permissions ──────────────────────────────────────
        // Inbound CCIP messages are written by CCIPReceiver; the pool and all
        // three controllers read the mirror. Granting only some of these is the
        // classic cause of a StateAggregator__InvalidSender at message-delivery
        // time, long after the deposit that triggered it looked successful.
        stateAggregator.setAuthorizedUpdators(address(ccipReceiver), true);
        stateAggregator.setAuthorizedReadors(poolAddress, true);
        stateAggregator.setAuthorizedReadors(address(loanController), true);
        stateAggregator.setAuthorizedReadors(
            address(collateralController),
            true
        );
        stateAggregator.setAuthorizedReadors(
            address(liquidityController),
            true
        );
        LendingPoolContract pool = LendingPoolContract(payable(poolAddress));

        pool.initialize(
            tokenAddresses,
            priceFeedAddresses,
            chainId,
            address(stableCoin),
            address(lpToken),
            // `link_` — no LINK token on the local/test network, so the LP token
            // stands in as a placeholder. Native-token CCIP fees are used instead.
            address(lpToken),
            // `gsm` — the satellite chain has no GlobalStateManager; it is only
            // read behind a `block.chainid == ethChainId` guard, so it stays unset.
            address(0),
            address(registry),
            address(vault),
            address(crossChainMessageSender),
            address(ccipReceiver),
            address(lpToken), // ccipRequestHandlerAddress
            address(stateAggregator),
            address(crossChainMessageReceiver),
            address(liquidityController),
            address(collateralController),
            address(loanController)
        );

        // ── Post-deploy wiring ────────────────────────────────────────────────
        // Mirrors DeployChainA, minus the GSM (which only exists on the hub).

        address[] memory controllers = new address[](3);
        controllers[0] = address(liquidityController);
        controllers[1] = address(collateralController);
        controllers[2] = address(loanController);

        vault.setAuthorizedContracts(controllers, true);
        for (uint256 i = 0; i < controllers.length; i++) {
            crossChainMessageSender.setAllowedCallers(controllers[i], true);
        }
        crossChainMessageSender.setAllowedCallers(poolAddress, true);
        crossChainMessageSender.setAllowedCallers(address(ccipReceiver), true);

        interestRateModel.setLendingPoolContractAndGSM(
            poolAddress,
            address(stateAggregator)
        );

        // Seed the satellite vault so loans can be drawn here too, and give the
        // deployer a balance, while the deployer still owns the stablecoin.
        stableCoin.mint(address(vault), 1_000_000e6);
        stableCoin.mint(vm.addr(deployerKey), 100_000e6);

        // Set while the deployer still owns them; ownership moves to the pool next.
        liquidityController.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        collateralController.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        loanController.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        ccipReceiver.setChainIds(ETH_CHAIN_ID);
        stateAggregator.setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);
        LendingPoolContract(payable(poolAddress)).setChainIds(ETH_CHAIN_ID, ARB_CHAIN_ID);

        lpToken.transferOwnership(address(liquidityController));
        interestRateModel.transferOwnership(poolAddress);
        stableCoin.transferOwnership(poolAddress);
        crossChainMessageSender.transferOwnership(poolAddress);
        crossChainMessageReceiver.transferOwnership(poolAddress);
        ccipReceiver.transferOwnership(poolAddress);
        liquidityController.transferOwnership(poolAddress);
        collateralController.transferOwnership(poolAddress);
        loanController.transferOwnership(poolAddress);

        // ── Registry routing ──────────────────────────────────────────────────
        registry.setAddress(
            ARB_CHAIN_ID,
            "crossChainMessageSenderAddress",
            address(crossChainMessageSender)
        );
        registry.setDestinationChainSelector(ETH_CHAIN_ID, ETH_CHAIN_SELECTOR);
        registry.setDestinationChainSelector(ARB_CHAIN_ID, ARB_CHAIN_SELECTOR);
        registry.setCrossChainRegistryAddress(
            ARB_CHAIN_SELECTOR,
            "crossChainMessageReceiverAddress",
            address(crossChainMessageReceiver)
        );

        (bool funded, ) = payable(address(crossChainMessageSender)).call{
            value: 1 ether
        }("");
        require(funded, "failed to fund cross-chain sender");

        vm.stopBroadcast();

        // Parsed by tooling/deploy-local.mjs — keep the "KEY=0x..." shape.
        console.log("DEPLOY lendingPool=%s", poolAddress);
        console.log("DEPLOY vault=%s", address(vault));
        console.log("DEPLOY stableCoin=%s", address(stableCoin));
        console.log("DEPLOY lpToken=%s", address(lpToken));
        console.log("DEPLOY stateAggregator=%s", address(stateAggregator));
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
