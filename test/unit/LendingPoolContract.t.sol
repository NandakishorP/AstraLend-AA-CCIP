// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployLendingPoolContract} from "../../script/DeployLendingPoolContract.s.sol";
import {LendingPoolContract} from "../../src/LendingPoolContract.sol";
import {StableCoin} from "../../src/tokens/StableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {LpToken} from "../../src/tokens/LpTokenContract.sol";
import {LendingPoolContractErrors} from "../../src/errors/Errors.sol";
import {IInterestRateModel} from "../../src/interfaces/IInterestRateModel.sol";

contract LendingPoolContractTest is Test {
    LendingPoolContract public lendingPoolContract;
    IInterestRateModel public interestRateModel;
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
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    address user5 = makeAddr("user5");
    address user6 = makeAddr("user6");
    address lpTokenAddress;
    uint256 public PRECISION = 1e18;
    uint256 public kink = 70e16;
    uint256 public maxInterestRate = 100e16;
    uint256 public baseInterestRate = 5e16;
    uint256 public deployer;
    address vault;

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
        interestRateModel = IInterestRateModel(
            lendingPoolContract.getInterestRateModelAddress()
        );
        vault = lendingPoolContract.getVaultAddress();
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(user1, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(user2, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(user3, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(user4, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(user5, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(user6, STARTING_USER_BALANCE);
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
            address(lpToken),
            address(weth)
        );
    }

    // testing of the deposit function
    function testDepositLiquidityExpectingRevertBecauseTheAmountPassedIsZero()
        public
    {
        vm.startPrank(user);
        console.log(address(user));
        vm.expectRevert(
            LendingPoolContractErrors
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
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
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
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.stopPrank();
        vm.startPrank(user1);
        uint256 initalLpTokenAmount = lpToken.balanceOf(user1);
        uint256 initalTotalSupplyOfLpTokens = lpToken.totalSupply();
        uint256 initalTotalLiquidity = lendingPoolContract
            .getTotalLiquidityPerToken(weth);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
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
            LendingPoolContractErrors
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

        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
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
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
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
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
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
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
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
        ERC20Mock(address(stableCoin)).mint(vault, 10000 ether);

        vm.startPrank(user);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
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

    // TESTING THE UTILIZATION RATIO

    function testUtilizationRatioOnOrBeforeFirstDeposit() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.stopPrank();
        uint256 initalUtilizationRatio = interestRateModel.getUtilizationRatio(
            weth
        );

        assertEq(initalUtilizationRatio, 0);
    }

    function testUtilizationRatioUnitTest() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(vault, 2 * DEPOSITING_AMOUNT);
        lendingPoolContract.depositLiquidity(weth, 2 * DEPOSITING_AMOUNT);
        vm.stopPrank();
        vm.prank(address(lendingPoolContract));
        ERC20Mock(address(stableCoin)).mint(vault, 10000 ether);
        vm.startPrank(user1);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);

        uint256 borrowingAmount = (DEPOSITING_AMOUNT * 75e16) / 1e18;
        lendingPoolContract.borrowLoan(
            weth,
            lendingPoolContract.getUsdValue(weth, borrowingAmount)
        );
        vm.stopPrank();

        uint256 expectedUtilizationRatio = (borrowingAmount * 1e18) /
            ((2 * DEPOSITING_AMOUNT) + borrowingAmount);
        uint256 calculatedUtilizationRatio = interestRateModel
            .getUtilizationRatio(weth);

        assertEq(calculatedUtilizationRatio, expectedUtilizationRatio);
    }

    // TEST INTEREST RATE MODEL

    //  we need to check the interest rate model, borrower index

    // TESTING THE INTEREST RATE MODEL

    function testInterestRateModelReverBecauseTokenIsNotApproved() public {
        vm.expectRevert(
            abi.encodeWithSignature("InterestRateModel__TokenNotSupported()")
        );
        interestRateModel.getInterestRate(address(lpToken));
    }

    function testInterestRateModelUnitTest() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(vault, 2 * DEPOSITING_AMOUNT);
        lendingPoolContract.depositLiquidity(weth, 2 * DEPOSITING_AMOUNT);
        vm.stopPrank();
        vm.prank(address(lendingPoolContract));
        ERC20Mock(address(stableCoin)).mint(vault, 10000 ether);
        vm.startPrank(user1);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        // 272727272727272727
        // 700000000000000000
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);

        uint256 borrowingAmount = (DEPOSITING_AMOUNT * 75e16) / 1e18;
        lendingPoolContract.borrowLoan(
            weth,
            lendingPoolContract.getUsdValue(weth, borrowingAmount)
        );
        vm.stopPrank();
        uint256 utilizationRatio = interestRateModel.getUtilizationRatio(weth);
        uint256 expectedInterestRate = baseInterestRate +
            (((maxInterestRate - baseInterestRate) * utilizationRatio) / kink);
        uint256 calculatedInterestRate = interestRateModel.getInterestRate(
            weth
        );

        assertEq(calculatedInterestRate, expectedInterestRate);
    }

    // REPAY FUNCTION TESTING

    function testRepayLoanRevertBecauseAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__AmountShouldBeGreaterThanZero()"
            )
        );
        lendingPoolContract.repayLoan(weth, 0);
        vm.stopPrank();
    }

    function testRepayLoanRevertBecauseTokenIsInvalid() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSignature(
                "LendingPoolContract__TokenIsNotAllowedToDeposit(address)",
                address(lpToken)
            )
        );
        lendingPoolContract.repayLoan(address(lpToken), 10);
        vm.stopPrank();
    }

    function testRepayLoanUnitTestFinal() public {
        vm.prank(address(lendingPoolContract));
        ERC20Mock(address(stableCoin)).mint(vault, 100000 ether);

        vm.startPrank(user1);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);
        uint256 collateralAvailableForBorrowing = (DEPOSITING_AMOUNT * 75e16) /
            1e18;
        uint256 collateralAvailableForBorrowingInUsd = lendingPoolContract
            .getUsdValue(weth, collateralAvailableForBorrowing);
        lendingPoolContract.borrowLoan(
            weth,
            collateralAvailableForBorrowingInUsd
        );
        vm.stopPrank();

        vm.startPrank(user3);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);

        // 7500000000000000000000
        // 309686888442240000000
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user4);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);
        uint256 collateralAvailableForBorrowing4 = (DEPOSITING_AMOUNT * 75e16) /
            1e18;
        uint256 collateralAvailableForBorrowingInUsd4 = lendingPoolContract
            .getUsdValue(weth, collateralAvailableForBorrowing4);
        lendingPoolContract.borrowLoan(
            weth,
            collateralAvailableForBorrowingInUsd4
        );
        vm.stopPrank();

        vm.startPrank(user6);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);
        uint256 collateralAvailableForBorrowing3 = (DEPOSITING_AMOUNT * 75e16) /
            1e18;
        uint256 collateralAvailableForBorrowingInUsd3 = lendingPoolContract
            .getUsdValue(weth, collateralAvailableForBorrowing3);
        lendingPoolContract.borrowLoan(
            weth,
            collateralAvailableForBorrowingInUsd3
        );
        vm.stopPrank();

        vm.startPrank(user5);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositLiquidity(weth, DEPOSITING_AMOUNT);
        vm.stopPrank();

        // now the user is going to repay the loan
        vm.warp(block.timestamp + 30 days);

        LendingPoolContract.LoanDetails memory loanSummary = lendingPoolContract
            .getLoanDetails(user4, weth);

        uint256 principalLoanAmount = loanSummary.amountBorrowedInUSDT;
        uint256 userBorrowIndex = loanSummary.userBorrowIndex;

        uint256 scaledLoanAmount = (principalLoanAmount *
            lendingPoolContract.getBorrowerIndex(weth)) / userBorrowIndex;

        vm.prank(address(lendingPoolContract));
        ERC20Mock(address(stableCoin)).mint(user4, scaledLoanAmount);
        vm.startPrank(user4);
        stableCoin.approve(vault, scaledLoanAmount);
        lendingPoolContract.repayLoan(weth, scaledLoanAmount);
        LendingPoolContract.LoanDetails
            memory loanSummary2 = lendingPoolContract.getLoanDetails(
                user4,
                weth
            );
        assertEq(loanSummary2.amountBorrowedInUSDT, 0);
        vm.stopPrank();
    }

    //15000000000000000000000
    //7500000000000000000000

    function testLiquidation() public {
        vm.prank(address(lendingPoolContract));
        ERC20Mock(address(stableCoin)).mint(vault, 100000 ether);
        vm.startPrank(user1);
        ERC20Mock(weth).approve(vault, DEPOSITING_AMOUNT);
        lendingPoolContract.depositCollateral(weth, DEPOSITING_AMOUNT);
        uint256 collateralAvailableForBorrowing3 = (DEPOSITING_AMOUNT * 75e16) /
            1e18;
        uint256 collateralAvailableForBorrowingInUsd3 = lendingPoolContract
            .getUsdValue(weth, collateralAvailableForBorrowing3);
        lendingPoolContract.borrowLoan(
            weth,
            collateralAvailableForBorrowingInUsd3
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 181 days);

        (bool upkeepNeeded, bytes memory performData) = lendingPoolContract
            .checkUpkeep("");

        if (upkeepNeeded) {
            lendingPoolContract.performUpkeep(performData);
        }

        LendingPoolContract.LoanDetails
            memory loanSummery1 = lendingPoolContract.getLoanDetails(
                user1,
                weth
            );
        assertEq(loanSummery1.penaltyCount, 1);

        vm.warp(block.timestamp + 31 days);

        (bool upkeepNeeded2, bytes memory performData2) = lendingPoolContract
            .checkUpkeep("");

        if (upkeepNeeded2) {
            lendingPoolContract.performUpkeep(performData2);
        }

        LendingPoolContract.LoanDetails
            memory loanSummery2 = lendingPoolContract.getLoanDetails(
                user1,
                weth
            );

        assertEq(loanSummery2.penaltyCount, 2);

        vm.warp(block.timestamp + 32 days);

        (bool upkeepNeeded3, bytes memory performData3) = lendingPoolContract
            .checkUpkeep("");

        if (upkeepNeeded3) {
            lendingPoolContract.performUpkeep(performData3);
        }

        assertEq(
            lendingPoolContract
                .getLoanDetails(user1, weth)
                .amountBorrowedInUSDT,
            0
        );
    }
}
