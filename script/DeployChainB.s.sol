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

contract DeployChainBScript is Script {
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

        uint64[] memory chainId = new uint64[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            chainId[i] = uint64(i);
        }

        // link token address is given as zero because in the contract we are using the native tokens and its in avil chain right now
        // the router address is given as zero as well because right now we don't have the router address in the local testing enviornment but for the
        // unit testing its configured in the testing space itself
        LendingPoolContract lendingPoolContract = new LendingPoolContract();
        ProxyAdmin proxyAdmin = new ProxyAdmin(vm.addr(deployerKey));
        Vault vault = new Vault(
            address(lendingPoolContract),
            address(stableCoin)
        );

        StateAggregator stateAggregator = new StateAggregator();

        // we are supposed to pass the link token address and the router address but since this deployment is for testing and there is no real router or link address available its replaced with the lptoken address temperorarly
        CrossChainMessageSender crossChainMessageSender = new CrossChainMessageSender(
                address(lpToken),
                address(lpToken)
            );

        CCIPReceiver ccipReceiver = new CCIPReceiver(
            address(lendingPoolContract),
            address(registry),
            address(lpToken),
            address(lpToken)
        );

        stateAggregator.setAuthorizedUpdators(address(ccipReceiver), true);
        stateAggregator.setAuthorizedReadors(
            address(lendingPoolContract),
            true
        );

        CrossChainMessageReceiver crossChainMessageReceiver = new CrossChainMessageReceiver(
                address(lpToken),
                address(ccipReceiver)
            );
        LoanController loanController = new LoanController(
            address(stateAggregator),
            address(stateAggregator),
            address(lendingPoolContract),
            address(registry),
            address(vault)
        );

        CollateralController collateralController = new CollateralController(
            address(registry),
            address(vault),
            address(stateAggregator),
            address(lendingPoolContract),
            address(stateAggregator)
        );
        LiquidityController liquidityController = new LiquidityController(
            address(registry),
            address(lendingPoolContract),
            address(vault),
            address(stateAggregator),
            address(stateAggregator),
            address(lpToken)
        );
        bytes memory data = abi.encodeWithSelector(
            lendingPoolContract.initialize.selector,
            tokenAddresses,
            priceFeedAddresses,
            chainId,
            address(stableCoin),
            address(lpToken),
            address(lpToken), // rewardDistributor
            address(lpToken), // interestRateModel (check this!!)
            address(stateAggregator),
            address(registry),
            address(vault),
            address(crossChainMessageSender),
            address(ccipReceiver),
            address(lpToken),
            address(stateAggregator), // incentivesController?
            address(crossChainMessageReceiver),
            address(liquidityController),
            address(collateralController),
            address(loanController)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(lendingPoolContract),
            address(proxyAdmin),
            data
        );

        interestRateModel.transferOwnership(address(proxy));
        stableCoin.transferOwnership(address(proxy));
        lpToken.transferOwnership(address(proxy));

        vm.stopBroadcast();
        return (lendingPoolContract, stableCoin, helperConfig, lpToken);
    }
}
