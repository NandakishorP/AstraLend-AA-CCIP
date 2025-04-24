// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {LpToken} from "../src/LpTokenContract.sol";
import {StableCoin} from "../src/StableCoin.sol";

contract DeployLendingPoolContract is Script {
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
        // this is to ensure that the trasnaction is comingg from the desired account only
        vm.startBroadcast(deployerKey);
        StableCoin stableCoin = new StableCoin();
        LpToken lpToken = new LpToken();
        LendingPoolContract lendingPoolcontract = new LendingPoolContract(
            tokenAddresses,
            priceFeedAddresses,
            address(stableCoin),
            address(lpToken)
        );
        stableCoin.transferOwnership(address(lendingPoolcontract));
        lpToken.transferOwnership(address(lendingPoolcontract));
        vm.stopBroadcast();
        return (lendingPoolcontract, stableCoin, helperConfig, lpToken);
    }
}
