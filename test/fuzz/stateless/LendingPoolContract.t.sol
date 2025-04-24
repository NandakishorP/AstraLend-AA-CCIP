// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployLendingPoolContract} from "../../../script/DeployLendingPoolContract.s.sol";
import {LendingPoolContract} from "../../../src/LendingPoolContract.sol";
import {StableCoin} from "../../../src/StableCoin.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {LpToken} from "../../../src/LpTokenContract.sol";

contract LendingPoolContractTest is Test {
    LendingPoolContract public lendingPoolContract;
    StableCoin public stableCoin;
    HelperConfig public helperConfig;
    address weth;
    address wbtc;
    uint256 public constant STARTING_USER_BALANCE = 20 ether;
    uint256 public constant DEPOSITING_AMOUNT = 5 ether;
    LpToken lpToken;
    address ethUsdPriceFeedAddress;
    address btcUsdPriceFeedAddress;
    address[] tokenAddresses;
    address[] priceFeedAddresses;
    address user = makeAddr("user");
    address lpTokenAddress;
    uint256 public deployer;

    function setUp() public {
        DeployLendingPoolContract deployLendingPoolContract = new DeployLendingPoolContract();
        (
            lendingPoolContract,
            stableCoin,
            helperConfig,
            lpToken
        ) = deployLendingPoolContract.run();
        (
            ethUsdPriceFeedAddress,
            btcUsdPriceFeedAddress,
            wbtc,
            weth,
            deployer
        ) = helperConfig.activeNetworkConfig();
    }

    // stateless fuzzs testing for the depositt function
    // testing the function for the first user
    function testDepositLiquidityStatelessFuzzTest(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1e27);
        uint256 initalUserBalance = lendingPoolContract.getUserBalance(
            user,
            weth
        );
        uint256 initalLpTokenBalance = lpToken.balanceOf(user);
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, amount);
        ERC20Mock(weth).approve(address(lendingPoolContract), amount);
        lendingPoolContract.depositLiquidity(weth, amount);
        vm.stopPrank();
        uint256 finalLiquidityPerToken = lendingPoolContract
            .getTotalLiquidityPerToken(weth);

        uint256 finalLiquidity = lendingPoolContract.getTotalLiquidity();

        console.log("finalLiquidity", finalLiquidity);
        console.log("finalLiquidityPerToken", finalLiquidityPerToken);
        uint256 finalUserBalance = lendingPoolContract.getUserBalance(
            user,
            weth
        );
        uint256 finalLpTokenBalance = lpToken.balanceOf(user);
        assertEq(finalLiquidityPerToken, amount);
        assertEq(finalUserBalance - initalUserBalance, amount);
        assertEq(finalLpTokenBalance - initalLpTokenBalance, amount);
    }
}
