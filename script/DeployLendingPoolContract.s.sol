// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {InterestRateModel} from "../src/InterestRate/InterestRateModel.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {LpToken} from "../src/tokens/LpTokenContract.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
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
        uint64[] memory arr = new uint64[](0);
        InterestRateModel interestRateModel = new InterestRateModel();
        StableCoin stableCoin = new StableCoin();
        LpToken lpToken = new LpToken();
        LendingPoolContract lendingPoolcontract = new LendingPoolContract();
        lendingPoolcontract.initialize(
            tokenAddresses,
            priceFeedAddresses,
            arr,
            address(stableCoin),
            address(lpToken),
            address(lpToken), // this is link address now replacing with lptoken for testing
            address(lpToken), // this is router and now replacing with lptoken for convinence and should be replaced with ccip router address
            address(0),
            address(0)
        );
        interestRateModel.setLendingPoolContractAndGSM(
            address(lendingPoolcontract),
            address(0)
        );
        interestRateModel.transferOwnership(address(lendingPoolcontract));
        stableCoin.transferOwnership(address(lendingPoolcontract));
        lpToken.transferOwnership(address(lendingPoolcontract));
        vm.stopBroadcast();
        return (lendingPoolcontract, stableCoin, helperConfig, lpToken);
    }
}
