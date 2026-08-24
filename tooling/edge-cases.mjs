/**
 * Negative-path battery.
 *
 * Every case here *should* revert. A silent success is the failure condition —
 * these are the guards that stop a user draining the pool or over-repaying.
 * Run as static calls so nothing is committed and the run is repeatable.
 */
import { ethers } from "ethers";
import { readFileSync } from "node:fs";

const dep = JSON.parse(readFileSync(new URL("./deployment.local.json", import.meta.url)));
const c = dep.chains.eth;
const USER = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const p = new ethers.JsonRpcProvider("http://127.0.0.1:8545", 424242);

const pool = new ethers.Contract(c.lendingPool, [
  "function depositLiquidity(uint64,uint256) payable",
  "function depositCollateral(uint64,uint256) payable",
  "function withdrawDeposit(uint64,uint256) payable",
  "function withdrawCollateral(uint64,uint256) payable",
  "function borrowLoan(uint256,uint64,uint256) payable",
  "function repayLoan(uint256,uint64,uint256,uint256) payable",
  "function getUserLoanCount(uint256,address,uint64) view returns (uint256)",
], p);

const cases = [
  ["deposit zero liquidity",        () => pool.depositLiquidity.staticCall(0, 0, { from: USER })],
  ["deposit zero collateral",       () => pool.depositCollateral.staticCall(0, 0, { from: USER })],
  ["borrow zero",                   () => pool.borrowLoan.staticCall(424242, 0, 0, { from: USER })],
  ["unsupported token id 99",       () => pool.depositCollateral.staticCall(99, 1n, { from: USER })],
  ["borrow far beyond 75% LTV",     () => pool.borrowLoan.staticCall(424242, 0, 10_000_000_000_000n, { from: USER })],
  ["withdraw more liquidity than supplied",
                                    () => pool.withdrawDeposit.staticCall(0, ethers.parseEther("1000000"), { from: USER })],
  ["withdraw more collateral than posted",
                                    () => pool.withdrawCollateral.staticCall(0, ethers.parseEther("1000000"), { from: USER })],
  ["repay a loan id that does not exist",
                                    () => pool.repayLoan.staticCall(424242, 0, 1_000_000n, 9999, { from: USER })],
  ["borrow against a chain holding no collateral",
                                    () => pool.borrowLoan.staticCall(999999, 0, 1_000_000n, { from: USER })],
];

let rejected = 0, accepted = 0;
for (const [name, run] of cases) {
  try {
    await run();
    console.log(`  ACCEPTED  ${name}   <-- expected a revert`);
    accepted++;
  } catch (e) {
    const m = (e.shortMessage ?? e.message).replace(/\s+/g, " ").slice(0, 60);
    console.log(`  rejected  ${name.padEnd(45)} ${m}`);
    rejected++;
  }
}
console.log(`\n${rejected} rejected, ${accepted} unexpectedly accepted`);
