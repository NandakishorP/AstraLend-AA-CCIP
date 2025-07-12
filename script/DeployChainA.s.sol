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

contract DeployChainAScript is Script {
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

        GlobalStateManager GSM = new GlobalStateManager(
            address(registry),
            address(interestRateModel)
        );

        // link token address is given as zero because in the contract we are using the native tokens and its in avil chain right now
        // the router address is given as zero as well because right now we don't have the router address in the local testing enviornment but for the
        // unit testing its configured in the testing space itself
        LendingPoolContract lendingPoolContract = new LendingPoolContract();
        ProxyAdmin proxyAdmin = new ProxyAdmin(vm.addr(deployerKey));

        bytes memory data = abi.encodeWithSignature(
            "initialize(address[],address[],uint64[],address,address,address,address,address,address)",
            tokenAddresses,
            priceFeedAddresses,
            chainId,
            address(stableCoin),
            address(lpToken),
            address(lpToken),
            address(lpToken),
            address(GSM),
            address(registry)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(lendingPoolContract),
            address(proxyAdmin),
            data
        );

        interestRateModel.setLendingPoolContractAndGSM(
            address(proxy),
            address(GSM)
        );
        interestRateModel.transferOwnership(address(proxy));
        stableCoin.transferOwnership(address(proxy));
        lpToken.transferOwnership(address(proxy));

        vm.stopBroadcast();
        return (lendingPoolContract, stableCoin, helperConfig, lpToken);
    }
}
