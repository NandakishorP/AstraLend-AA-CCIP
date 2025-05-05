// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {InterestRateModel} from "../src/InterestRate/InterestRateModel.sol";
import {LpToken} from "../src/tokens/LpTokenContract.sol";
import {StableCoin} from "../src/tokens/StableCoin.sol";

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
        InterestRateModel interestRateModel = new InterestRateModel();
        StableCoin stableCoin = new StableCoin();
        LpToken lpToken = new LpToken();
        LendingPoolContract lendingPoolcontract = new LendingPoolContract(
            tokenAddresses,
            priceFeedAddresses,
            address(stableCoin),
            address(lpToken),
            address(interestRateModel)
        );
        interestRateModel.setLendingPoolContract(address(lendingPoolcontract));
        interestRateModel.transferOwnership(address(lendingPoolcontract));
        stableCoin.transferOwnership(address(lendingPoolcontract));
        lpToken.transferOwnership(address(lendingPoolcontract));
        vm.stopBroadcast();
        return (lendingPoolcontract, stableCoin, helperConfig, lpToken);
    }
}
