/**
 * Liquidation escalation against the live node.
 *
 * Unlike the Foundry script, this moves the chain's real clock with
 * `evm_increaseTime`, so the keeper actually sees an overdue loan. The contract
 * escalates before it seizes: two 5% penalties, each pushing the due date out
 * 30 days, and only then liquidation.
 */
import { ethers } from "ethers";
import { readFileSync } from "node:fs";

const dep = JSON.parse(readFileSync(new URL("./deployment.local.json", import.meta.url)));
const KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const c = dep.chains.eth;

const p = new ethers.JsonRpcProvider("http://127.0.0.1:8545", 424242);
const w = new ethers.Wallet(KEY, p);
const user = w.address;

const pool = new ethers.Contract(c.lendingPool, [
  "function depositLiquidity(uint64,uint256) payable",
  "function depositCollateral(uint64,uint256) payable",
  "function borrowLoan(uint256,uint64,uint256) payable",
  "function getUserLoanCount(uint256,address,uint64) view returns (uint256)",
], w);
const gsm = new ethers.Contract(c.gsm, [
  "function performUpkeep(bytes)",
  "function readLoanDetailsOfUser(uint256,address,uint64,uint256) view returns (tuple(address token,uint256 amountBorrowedInUSDT,uint256 principalAmount,uint256 collateralUsed,uint256 collateralChainId,uint256 lastUpdate,address asset,uint256 userBorrowIndex,uint256 interestPaid,uint256 liquidationPoint,uint256 loanChainId,uint256 dueDate,bool isClosed,uint256 loanId,uint8 penaltyCount,bool isLiquidated))",
], w);
const weth = new ethers.Contract(c.weth, [
  "function mint(address,uint256)", "function approve(address,uint256) returns (bool)",
], w);

/**
 * Sends one transaction, retrying on nonce collisions.
 *
 * The backend's signer uses this same key for its faucet and demo endpoints, so
 * another process can consume a nonce between our read and our send. Letting
 * ethers resolve the nonce and retrying on conflict is simpler and more robust
 * than trying to own a counter we do not exclusively control.
 */
const send = async (fn, ...args) => {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const tx = await fn(...args, { gasLimit: 3_000_000 });
      return await tx.wait();
    } catch (error) {
      if (!/nonce/i.test(error.shortMessage ?? error.message) || attempt === 4) throw error;
      await new Promise((r) => setTimeout(r, 300));
    }
  }
};

console.log("setting up a fresh loan…");
await send(weth.mint, user, ethers.parseEther("20"));
await send(weth.approve, c.vault, ethers.MaxUint256);
await send(pool.depositLiquidity, 0, ethers.parseEther("10"));
await send(pool.depositCollateral, 0, ethers.parseEther("10"));

// Loan ids are 1-based.
const loanId = (await pool.getUserLoanCount(424242, user, 0)) + 1n;
await send(pool.borrowLoan, 424242, 0, 1_000_000_000n);
console.log(`  loan #${loanId} opened for 1,000 SC\n`);

const performData = ethers.AbiCoder.defaultAbiCoder().encode(
  ["uint256", "address", "uint64", "uint256"], [424242, user, 0, loanId]
);

const advance = async (days) => {
  await p.send("evm_increaseTime", [days * 86400]);
  await p.send("evm_mine", []);
};

await advance(181);
console.log("advanced 181 days — past the 180-day term\n");

for (let round = 1; round <= 3; round++) {
  await send(gsm.performUpkeep, performData);
  const l = await gsm.readLoanDetailsOfUser(424242, user, 0, loanId);
  console.log(`round ${round}: penalties=${l.penaltyCount} liquidated=${l.isLiquidated} ` +
              `owed=${(Number(l.amountBorrowedInUSDT) / 1e6).toFixed(2)} SC closed=${l.isClosed}`);
  await advance(31);
}
