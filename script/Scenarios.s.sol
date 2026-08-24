// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {LendingPoolContract} from "../src/LendingPoolContract.sol";
import {GlobalStateManager} from "../src/GSM/GlobalStateManager.sol";
import {LoanManager} from "../src/GSM/LoanManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/**
 * @title Scenarios
 * @notice Exercises the protocol's full lifecycle against a running local node.
 *
 * This is a *script*, not a test, on purpose: it runs against the same deployed
 * contracts the web app and indexer are pointed at, so whatever it does shows up
 * in the database and on the dashboard. `forge test` would run against a private
 * in-memory EVM that nothing else can see.
 *
 * IMPORTANT — `vm.warp` does NOT move a live node's clock. Under
 * `forge script --broadcast`, Foundry executes the script against a local
 * simulation and then broadcasts the resulting transactions; the warp applies
 * only to that simulation. Anything this script *logs* after a warp is
 * simulated, and the transactions that land on the node run at the node's real
 * timestamp. Verified the hard way: `liquidationEscalation()` logged two
 * penalties and the chain still reported `penaltyCount: 0`.
 *
 * Consequence: use the non-time-dependent scenarios here for logic checks, and
 * drive anything time-dependent through RPC (`evm_increaseTime`) instead — see
 * `tooling/escalation.mjs`, or the /demo/time-travel and /demo/keeper endpoints
 * the dashboard's demo panel uses.
 *
 * Nothing in `src/` is modified or required to change; every entry point used
 * here is already public API.
 *
 * Usage:
 *   forge script script/Scenarios.s.sol:Scenarios --sig "happyPath()" \
 *     --rpc-url http://127.0.0.1:8545 --broadcast --private-key $KEY
 */
contract Scenarios is Script {
    // Populated from tooling/deployment.local.json via environment variables so
    // the script never hard-codes an address that changes on every redeploy.
    LendingPoolContract pool;
    GlobalStateManager gsm;
    address weth;
    address stableCoin;
    address vault;
    uint64 constant TOKEN_ID = 0;
    uint256 deployerKey;
    address user;

    function setUp() public {
        pool = LendingPoolContract(payable(vm.envAddress("POOL")));
        gsm = GlobalStateManager(vm.envAddress("GSM"));
        weth = vm.envAddress("WETH");
        stableCoin = vm.envAddress("STABLECOIN");
        vault = vm.envAddress("VAULT");
        deployerKey = vm.envUint("DEPLOYER_KEY");
        user = vm.addr(deployerKey);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _fund(uint256 amount) internal {
        IMintable(weth).mint(user, amount);
        IERC20(weth).approve(vault, type(uint256).max);
    }

    function _label(string memory step) internal pure {
        console.log("");
        console.log(step);
    }

    function _report() internal view {
        uint256 collateral = pool.getCollateralDetailsOfUser(block.chainid, user, TOKEN_ID);
        uint256 supplied = pool.getUserBalance(block.chainid, user, TOKEN_ID);
        uint256 loans = pool.getUserLoanCount(block.chainid, user, TOKEN_ID);
        console.log("   supplied   ", supplied);
        console.log("   collateral ", collateral);
        console.log("   loans      ", loans);
    }

    // ─── 1. Happy path ────────────────────────────────────────────────────────

    /// Supply → collateral → borrow → partial repay → full repay.
    function happyPath() public {
        vm.startBroadcast(deployerKey);

        _label("1. Supply liquidity");
        _fund(50 ether);
        pool.depositLiquidity(TOKEN_ID, 20 ether);
        _report();

        _label("2. Deposit collateral");
        pool.depositCollateral(TOKEN_ID, 10 ether);
        _report();

        _label("3. Borrow against it");
        // Loan ids are 1-based: `getUserLoanCount` returns how many exist, so the
        // next one is count + 1. Using the count itself addresses the *previous*
        // loan, which is how this script first mis-targeted an older position.
        uint256 loanId = pool.getUserLoanCount(block.chainid, user, TOKEN_ID) + 1;
        pool.borrowLoan(block.chainid, TOKEN_ID, 1_000e6);
        console.log("   borrowed 1000 stablecoin, loanId", loanId);

        _label("4. Repay half");
        IERC20(stableCoin).approve(vault, type(uint256).max);
        pool.repayLoan(block.chainid, TOKEN_ID, 500e6, loanId);
        uint256 owed = pool.getAmountToRepay(block.chainid, TOKEN_ID, loanId);
        console.log("   still owed", owed);

        _label("5. Repay the rest");
        pool.repayLoan(block.chainid, TOKEN_ID, owed, loanId);
        console.log("   owed after full repayment", pool.getAmountToRepay(block.chainid, TOKEN_ID, loanId));
        _report();

        vm.stopBroadcast();
        console.log("");
        console.log("happyPath OK");
    }

    // ─── 2. Interest accrual over time ────────────────────────────────────────

    /// Borrows, jumps the chain clock forward, and shows the debt growing.
    function interestAccrual() public {
        vm.startBroadcast(deployerKey);

        _fund(30 ether);
        pool.depositLiquidity(TOKEN_ID, 10 ether);
        pool.depositCollateral(TOKEN_ID, 10 ether);

        // Loan ids are 1-based: `getUserLoanCount` returns how many exist, so the
        // next one is count + 1. Using the count itself addresses the *previous*
        // loan, which is how this script first mis-targeted an older position.
        uint256 loanId = pool.getUserLoanCount(block.chainid, user, TOKEN_ID) + 1;
        pool.borrowLoan(block.chainid, TOKEN_ID, 1_000e6);

        uint256 atOpen = pool.getAmountToRepay(block.chainid, TOKEN_ID, loanId);
        console.log("   owed at open      ", atOpen);

        vm.stopBroadcast();

        // The borrower index does not advance on its own: `getBorrowerIndex` is a
        // plain view, and `_accuredInterest` only runs inside a GSM state change.
        // So time alone changes nothing — a deposit, borrow or repay on the same
        // token is what actually applies the elapsed-time interest. Each step
        // below warps, then pokes the pool to trigger accrual, then reads.
        vm.warp(block.timestamp + 30 days);
        vm.startBroadcast(deployerKey);
        console.log("   owed after 30 days, before any action", pool.getAmountToRepay(block.chainid, TOKEN_ID, loanId));
        pool.depositLiquidity(TOKEN_ID, 0.01 ether);
        console.log("   owed after 30 days, once poked      ", pool.getAmountToRepay(block.chainid, TOKEN_ID, loanId));
        vm.stopBroadcast();

        vm.warp(block.timestamp + 150 days);
        vm.startBroadcast(deployerKey);
        pool.depositLiquidity(TOKEN_ID, 0.01 ether);
        console.log("   owed after 180 days, once poked     ", pool.getAmountToRepay(block.chainid, TOKEN_ID, loanId));
        vm.stopBroadcast();

        console.log("");
        console.log("interestAccrual OK");
    }

    // ─── 3. Liquidation escalation ────────────────────────────────────────────

    /**
     * Runs the keeper past the due date three times — IN SIMULATION ONLY.
     *
     * Kept because it documents the intended escalation, but see the warning on
     * this contract: the warps below do not affect the node, so the penalties
     * printed here are not applied on-chain. Use `tooling/escalation.mjs` for a
     * real one.
     *
     * The contract does not seize collateral on the first overdue check: it adds
     * a 5% penalty and extends the due date by 30 days, twice, and only
     * liquidates on the third pass. Demonstrating that requires warping between
     * each keeper run, which is why this cannot be shown on a public testnet.
     */
    function liquidationEscalation() public {
        vm.startBroadcast(deployerKey);
        _fund(30 ether);
        pool.depositLiquidity(TOKEN_ID, 10 ether);
        pool.depositCollateral(TOKEN_ID, 10 ether);
        // Loan ids are 1-based: `getUserLoanCount` returns how many exist, so the
        // next one is count + 1. Using the count itself addresses the *previous*
        // loan, which is how this script first mis-targeted an older position.
        uint256 loanId = pool.getUserLoanCount(block.chainid, user, TOKEN_ID) + 1;
        pool.borrowLoan(block.chainid, TOKEN_ID, 1_000e6);
        vm.stopBroadcast();

        console.log("   loan opened, id", loanId);

        // Past the 180-day term.
        vm.warp(block.timestamp + 181 days);

        bytes memory performData = abi.encode(block.chainid, user, TOKEN_ID, loanId);

        for (uint256 round = 1; round <= 3; round++) {
            vm.startBroadcast(deployerKey);
            gsm.performUpkeep(performData);
            LoanManager.LoanDetails memory loan =
                gsm.readLoanDetailsOfUser(block.chainid, user, TOKEN_ID, loanId);
            vm.stopBroadcast();

            console.log("   round", round);
            console.log("     penaltyCount ", loan.penaltyCount);
            console.log("     isLiquidated ", loan.isLiquidated);
            console.log("     owed         ", loan.amountBorrowedInUSDT);

            // Each penalty pushes the due date out 30 days; step past it.
            vm.warp(block.timestamp + 31 days);
        }

        console.log("");
        console.log("liquidationEscalation OK");
    }

    // ─── 4. Withdrawals ───────────────────────────────────────────────────────

    /// Supplies and withdraws liquidity, and withdraws unlocked collateral.
    function withdrawals() public {
        vm.startBroadcast(deployerKey);

        _fund(20 ether);
        pool.depositLiquidity(TOKEN_ID, 10 ether);
        pool.depositCollateral(TOKEN_ID, 5 ether);
        _report();

        _label("withdraw liquidity");
        pool.withdrawDeposit(TOKEN_ID, 4 ether);
        _report();

        _label("withdraw unlocked collateral");
        pool.withdrawCollateral(TOKEN_ID, 2 ether);
        _report();

        vm.stopBroadcast();
        console.log("");
        console.log("withdrawals OK");
    }
}
