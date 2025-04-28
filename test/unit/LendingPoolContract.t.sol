// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployLendingPoolContract} from "../../script/DeployLendingPoolContract.s.sol";
import {LendingPoolContract} from "../../src/LendingPoolContract.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {LpToken} from "../../src/LpTokenContract.sol";

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
    address user1 = makeAddr("user1");
    address lpTokenAddress;
    uint256 public deployer;

    //events

    event DepositWithdrawn(
        address indexed user,
        address indexed tokenAddress,
        uint256 amount
    );

    event CollateralWithdrawed(
        address indexed user,
        address indexed token,
        uint256 amount
    );

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
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(user1, STARTING_USER_BALANCE);
    }

    function testIsConstructorParameterLengthTheSame() public {
        console.log("test started");
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeedAddress);
        priceFeedAddresses.push(btcUsdPriceFeedAddress);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__TokenAddressAndPriceFeedAddressMismatch(uint256,uint256)",
                tokenAddresses.length,
                priceFeedAddresses.length
            )
        );
        new LendingPoolContract(
            tokenAddresses,
            priceFeedAddresses,
            address(stableCoin),
            address(lpToken)
        );
    }

    // testing of the deposit function
    function testDepositLiquidityExpectingRevertBecauseTheAmountPassedIsZero()
        public
    {
        vm.startPrank(user);
        console.log(address(user));
        vm.expectRevert(
            LendingPoolContract
                .LendingPoolContract__AmountShouldBeGreaterThanZero
                .selector
        );
        lendingPoolContract.depositLiquidity(weth, 0);
        vm.stopPrank();
    }

    //here the lptoken address has been used instead of any generic address ,
    // and its done for convienence....Hehe I'm lazy
    function testDepositLiquidityIsTokeAllowedToDeposit() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__TokenIsNotAllowedToDeposit(address)",
                lpTokenAddress
            )
        );
        lendingPoolContract.depositLiquidity(lpTokenAddress, 2 ether);

        vm.stopPrank();
    }

    //unit testing for the deposit function
    // testing the function for the first user
    function testDepositLiquidityUnitTest() public {
        uint256 initalLiquidity = lendingPoolContract.getTotalLiquidityPerToken(
            weth
        );
        uint256 initalUserBalance = ERC20Mock(weth).balanceOf(user);
        uint256 initalLpTokenBalance = lpToken.balanceOf(user);
        vm.startPrank(user);
        ERC20Mock(weth).approve(
            address(lendingPoolContract),
            DEPOSITING_AMOUNT
        );
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.stopPrank();
        uint256 finalLiquidity = lendingPoolContract.getTotalLiquidityPerToken(
            weth
        );
        uint256 finalUserBalance = ERC20Mock(weth).balanceOf(user);
        uint256 finalLpTokenBalance = lpToken.balanceOf(user);
        assertEq(finalLiquidity - initalLiquidity, DEPOSITING_AMOUNT);
        assertEq(initalUserBalance - finalUserBalance, DEPOSITING_AMOUNT);
        assertEq(finalLpTokenBalance - initalLpTokenBalance, DEPOSITING_AMOUNT);
    }

    //testing the depositLiquidity function when there are multple users, the main aim
    // of this testing is to make sure that the lptokens are minted properly

    function testDepositLiquidityWhenThereAreMultipleUsers() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(
            address(lendingPoolContract),
            DEPOSITING_AMOUNT
        );
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.stopPrank();
        vm.startPrank(user1);
        uint256 initalLpTokenAmount = lpToken.balanceOf(user1);
        uint256 initalTotalSupplyOfLpTokens = lpToken.totalSupply();
        uint256 initalTotalLiquidity = lendingPoolContract
            .getTotalLiquidityPerToken(weth);
        ERC20Mock(weth).approve(
            address(lendingPoolContract),
            DEPOSITING_AMOUNT
        );
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.stopPrank();
        uint256 amountOfLpTokensToMint = (DEPOSITING_AMOUNT *
            initalTotalSupplyOfLpTokens) / initalTotalLiquidity;
        uint256 finalLpTokenBalance = lpToken.balanceOf(user1);
        assertEq(
            finalLpTokenBalance - initalLpTokenAmount,
            amountOfLpTokensToMint
        );
    }

    //TESTING THE WITHDRAW FUNCTION
    function testWithdrawDepositFunctionRevertBecauseAmountPassedIsZero()
        public
    {
        vm.startPrank(user);
        vm.expectRevert(
            LendingPoolContract
                .LendingPoolContract__AmountShouldBeGreaterThanZero
                .selector
        );
        lendingPoolContract.withdrawDeposit(weth, 0);
        vm.stopPrank();
    }

    function testWithdrawLiquidityIsTokeAllowedToDeposit() public {
        uint256 amount = 2 ether;
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__TokenIsNotAllowedToDeposit(address)",
                lpTokenAddress
            )
        );
        lendingPoolContract.withdrawDeposit(lpTokenAddress, amount);
    }

    function testWithDrawLiquidityUnitTest() public {
        vm.startPrank(user);

        ERC20Mock(weth).approve(
            address(lendingPoolContract),
            DEPOSITING_AMOUNT
        );
        uint256 initalUserBalance = ERC20Mock(weth).balanceOf(user);
        uint256 initalTotalLiquidity = lendingPoolContract
            .getTotalLiquidityPerToken(weth);

        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.expectEmit(true, true, false, true);
        emit DepositWithdrawn(user, weth, DEPOSITING_AMOUNT);
        lendingPoolContract.withdrawDeposit(weth, DEPOSITING_AMOUNT);

        vm.stopPrank();
        uint256 finalUserBalance = ERC20Mock(weth).balanceOf(user);
        uint256 finalTotalLiquidity = lendingPoolContract
            .getTotalLiquidityPerToken(weth);
        assertEq(initalUserBalance, finalUserBalance);
        assertEq(initalTotalLiquidity, finalTotalLiquidity);
    }

    function testWithDrawDepositRevertIfAmountGreaterThanBalance() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(
            address(lendingPoolContract),
            DEPOSITING_AMOUNT
        );
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__InsufficentBalance(uint256,uint256)",
                DEPOSITING_AMOUNT * 2,
                DEPOSITING_AMOUNT
            )
        );
        lendingPoolContract.withdrawDeposit(weth, DEPOSITING_AMOUNT * 2);
    }

    // TESTING THE DEPOSIT COLLATERAL FUNCTION

    function testDepositCollateralRevertBecauseTheTokenIsInvalid() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__TokenIsNotAllowedToDeposit(address)",
                address(lpToken)
            )
        );
        lendingPoolContract.depositCollateral(address(lpToken), 10);
        vm.stopPrank();
    }

    function testDepositCollateralRevertBecauseAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__AmountShouldBeGreaterThanZero()"
            )
        );
        lendingPoolContract.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositCollateralUnitTest() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(
            address(lendingPoolContract),
            DEPOSITING_AMOUNT
        );
        uint256 initalUserBalance = ERC20Mock(weth).balanceOf(user);
        uint256 initalDepositedCollateralByUser = lendingPoolContract
            .getCollateralDetailsOfUser(weth);
        uint256 initalTotalCollateralDeposited = lendingPoolContract
            .getCollateralPerToken(weth);
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);
        uint256 finalUserBalance = ERC20Mock(weth).balanceOf(user);
        uint256 finalDepositedCollateralByUser = lendingPoolContract
            .getCollateralDetailsOfUser(weth);
        uint256 finalTotalCollateralDeposited = lendingPoolContract
            .getCollateralPerToken(weth);
        assertEq(initalUserBalance - finalUserBalance, DEPOSITING_AMOUNT);
        assertEq(
            finalDepositedCollateralByUser - initalDepositedCollateralByUser,
            DEPOSITING_AMOUNT
        );
        assertEq(
            finalTotalCollateralDeposited - initalTotalCollateralDeposited,
            DEPOSITING_AMOUNT
        );
    }

    function testWithDrawCollateralRevertBecauseAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__AmountShouldBeGreaterThanZero()"
            )
        );
        lendingPoolContract.withdrawCollateral(weth, 0);
        vm.stopPrank();
    }

    function testWithdrawCollateralRevertBecauseTokenIsInvalid() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__TokenIsNotAllowedToDeposit(address)",
                address(lpToken)
            )
        );
        lendingPoolContract.withdrawCollateral(address(lpToken), 10);
        vm.stopPrank();
    }

    function testWithdrawCollateralRevertBecauseNoCollateralDeposited() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__InvalidRequestAmount()"
            )
        );
        lendingPoolContract.withdrawCollateral(weth, 10);
        vm.stopPrank();
    }

    function testWithDrawCollateralUnitTest() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(
            address(lendingPoolContract),
            DEPOSITING_AMOUNT
        );
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);
        uint256 initalUserBalance = ERC20Mock(weth).balanceOf(user);
        uint256 initalDepositedCollateralByUser = lendingPoolContract
            .getCollateralDetailsOfUser(weth);
        uint256 initalTotalCollateralDeposited = lendingPoolContract
            .getCollateralPerToken(weth);
        lendingPoolContract.withdrawCollateral(weth, DEPOSITING_AMOUNT);
        uint256 finalUserBalance = ERC20Mock(weth).balanceOf(user);
        uint256 finalDepositedCollateralByUser = lendingPoolContract
            .getCollateralDetailsOfUser(weth);
        uint256 finalTotalCollateralDeposited = lendingPoolContract
            .getCollateralPerToken(weth);
        assertEq(initalUserBalance + DEPOSITING_AMOUNT, finalUserBalance);
        assertEq(
            initalDepositedCollateralByUser - DEPOSITING_AMOUNT,
            finalDepositedCollateralByUser
        );
        assertEq(
            initalTotalCollateralDeposited - DEPOSITING_AMOUNT,
            finalTotalCollateralDeposited
        );
    }

    // BORROWING LOAN TESTING

    function testBorrowLoanRevertBecauseAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__AmountShouldBeGreaterThanZero()"
            )
        );
        lendingPoolContract.borrowLoan(weth, 0);
        vm.stopPrank();
    }

    function testBorrowLoanRevertBecauseTokenIsInvalid() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__TokenIsNotAllowedToDeposit(address)",
                address(lpToken)
            )
        );
        lendingPoolContract.borrowLoan(address(lpToken), 10);
        vm.stopPrank();
    }

    function testBorrowLoanRevertBecauseNoCollateralDeposited() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__NotEnoughCollateral()"
            )
        );
        lendingPoolContract.borrowLoan(weth, 10);
        vm.stopPrank();
    }

    function testBorrowLoanUnitTest() public {
        vm.prank(address(lendingPoolContract));
        ERC20Mock(address(stableCoin)).mint(
            address(lendingPoolContract),
            10000 ether
        );
        console.log(
            ERC20Mock(address(stableCoin)).balanceOf(
                address(lendingPoolContract)
            )
        );

        console.log(address(stableCoin));

        vm.startPrank(user);
        ERC20Mock(weth).approve(
            address(lendingPoolContract),
            DEPOSITING_AMOUNT
        );
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);
        uint256 collateralAvailableForBorrowing = (DEPOSITING_AMOUNT * 75e16) /
            1e18;
        uint256 collateralAvailableForBorrowingInUsd = lendingPoolContract
            .getUsdValue(weth, collateralAvailableForBorrowing);
        uint256 initalUserBalance = ERC20Mock(address(stableCoin)).balanceOf(
            user
        );
        uint256 initalTotalBorrowedForToken = lendingPoolContract
            .getTotalBorroweedForAToken(weth);
        uint256 initalTotalBorrowedInUsdInTheContract = lendingPoolContract
            .totalBorrowed();
        lendingPoolContract.borrowLoan(
            weth,
            collateralAvailableForBorrowingInUsd
        );
        uint256 finalUserBalance = ERC20Mock(address(stableCoin)).balanceOf(
            user
        );
        uint256 finalTotalBorrowedForToken = lendingPoolContract
            .getTotalBorroweedForAToken(weth);
        uint256 finalTotalBorrowedInUsdInTheContract = lendingPoolContract
            .totalBorrowed();
        assertEq(
            finalUserBalance - initalUserBalance,
            collateralAvailableForBorrowingInUsd
        );
        assertEq(
            finalTotalBorrowedForToken - initalTotalBorrowedForToken,
            collateralAvailableForBorrowing
        );
        assertEq(
            finalTotalBorrowedInUsdInTheContract -
                initalTotalBorrowedInUsdInTheContract,
            collateralAvailableForBorrowingInUsd
        );
        vm.stopPrank();
    }
}
