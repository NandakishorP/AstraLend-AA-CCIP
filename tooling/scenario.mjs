#!/usr/bin/env node
/**
 * Walks the complete cross-chain story across both local nodes.
 *
 *   node tooling/scenario.mjs           # everything
 *   node tooling/scenario.mjs --seed    # stop after seeding, leave a live position
 *
 * Requires the chains, the deployment and the relayer to be up
 * (tooling/start-demo.sh does all three).
 *
 * The story, which is also the panel demo:
 *
 *   1. supply liquidity on the hub                        — lenders fund the pool
 *   2. post collateral on the SATELLITE chain             — travels to the hub over CCIP
 *   3. borrow stablecoin on the HUB against it            — collateral from another chain
 *   4. repay from the SATELLITE chain                     — debt settles across chains
 *   5. fast-forward past the due date and liquidate       — the keeper path
 */

import fs from "node:fs";
import { ethers } from "ethers";
import { CHAINS, DEPLOYER, DEPLOYMENT_FILE } from "./config.mjs";

const POOL_ABI = [
  "function depositLiquidity(uint64 tokenId, uint256 amount) payable",
  "function depositCollateral(uint64 tokenId, uint256 amount) payable",
  "function borrowLoan(uint256 collateralChainId, uint64 tokenId, uint256 amount) payable",
  "function repayLoan(uint256 loanChainId, uint64 tokenId, uint256 amount, uint256 loanId) payable",
  "function getCollateralDetailsOfUser(uint256 chainId, address user, uint64 tokenId) view returns (uint256)",
  "function getUserBalance(uint256 chainId, address user, uint64 tokenId) view returns (uint256)",
  "function getUserLoanCount(uint256 chainId, address user, uint64 tokenId) view returns (uint256)",
  "function getLoanDetails(uint256 chainId, address user, uint64 tokenId, uint256 loanId) view returns (tuple(address token, uint256 amountBorrowedInUSDT, uint256 principalAmount, uint256 collateralUsed, uint256 collateralChainId, uint256 lastUpdate, address asset, uint256 userBorrowIndex, uint256 interestPaid, uint256 liquidationPoint, uint256 loanChainId, uint256 dueDate, bool isClosed, uint256 loanId, uint8 penaltyCount, bool isLiquidated))",
  "function getUsdValue(uint64 tokenId, uint256 amount) view returns (uint256)",
];

const ERC20_ABI = [
  "function mint(address to, uint256 amount)",
  "function approve(address spender, uint256 amount)",
  "function balanceOf(address account) view returns (uint256)",
];

const GSM_ABI = [
  "function checkUpkeep(bytes) view returns (bool upkeepNeeded, bytes performData)",
  "function performUpkeep(bytes performData)",
];

const WETH_ID = 0;
const CCIP_FEE = ethers.parseEther("0.05");

const deployment = JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));

// ─── Chain handles ────────────────────────────────────────────────────────────

function connect(chainKey) {
  const chain = CHAINS[chainKey];
  const provider = new ethers.JsonRpcProvider(chain.rpcUrl, chain.chainId, {
    staticNetwork: ethers.Network.from(chain.chainId),
  });
  const wallet = new ethers.Wallet(DEPLOYER.privateKey, provider);
  const addrs = deployment.chains[chainKey];

  // Nonces are tracked by hand: several transactions are fired per step and the
  // provider's cached count goes stale between them.
  let nonce = null;
  const send = async (contract, method, args, overrides = {}) => {
    if (nonce === null) nonce = await provider.getTransactionCount(wallet.address, "pending");
    const tx = await contract[method](...args, { ...overrides, nonce });
    nonce += 1;
    const receipt = await tx.wait();
    if (receipt.status !== 1) throw new Error(`${method} reverted`);
    return receipt;
  };

  return {
    chain,
    provider,
    wallet,
    addrs,
    send,
    pool: new ethers.Contract(addrs.lendingPool, POOL_ABI, wallet),
    weth: new ethers.Contract(addrs.weth, ERC20_ABI, wallet),
    stable: new ethers.Contract(addrs.stableCoin, ERC20_ABI, wallet),
    resetNonce: () => { nonce = null; },
  };
}

// ─── Output helpers ───────────────────────────────────────────────────────────

let stepNumber = 0;
const step = (title) => process.stdout.write(`\n\x1b[35m${++stepNumber}. ${title}\x1b[0m\n`);
const note = (text) => process.stdout.write(`   ${text}\n`);
const ok = (text) => process.stdout.write(`   \x1b[32m✓\x1b[0m ${text}\n`);
const usd = (v) => `$${Number(ethers.formatEther(v)).toLocaleString("en-US", { maximumFractionDigits: 2 })}`;
const sc = (v) => `${Number(ethers.formatUnits(v, 6)).toLocaleString("en-US", { maximumFractionDigits: 2 })} SC`;

/** Gives the relayer time to pick up, deliver and have the state settle. */
async function settle(label = "cross-chain message") {
  process.stdout.write(`   \x1b[36m⇢\x1b[0m waiting for ${label}…`);
  await new Promise((resolve) => setTimeout(resolve, 6000));
  process.stdout.write("\r\x1b[K");
}

// ─── Scenario ─────────────────────────────────────────────────────────────────

async function main() {
  const seedOnly = process.argv.includes("--seed");
  const hub = connect("eth");
  const satellite = connect("arb");
  const user = hub.wallet.address;

  process.stdout.write(
    `\n\x1b[35mAstraLend cross-chain scenario\x1b[0m\n` +
      `   hub       ${hub.chain.name}  ${hub.chain.rpcUrl}\n` +
      `   satellite ${satellite.chain.name}  ${satellite.chain.rpcUrl}\n` +
      `   user      ${user}\n`
  );

  // ── 1. Supply liquidity on the hub ─────────────────────────────────────────
  step("Supply liquidity on the hub chain");
  await hub.send(hub.weth, "mint", [user, ethers.parseEther("50")]);
  await hub.send(hub.weth, "approve", [hub.addrs.vault, ethers.MaxUint256]);
  await hub.send(hub.pool, "depositLiquidity", [WETH_ID, ethers.parseEther("20")], { value: CCIP_FEE });
  ok(`supplied 20 WETH on ${hub.chain.name}`);
  await settle("LP mirror to the satellite");

  // ── 2. Collateral on the satellite chain ───────────────────────────────────
  step("Post collateral on the SATELLITE chain");
  await satellite.send(satellite.weth, "mint", [user, ethers.parseEther("10")]);
  await satellite.send(satellite.weth, "approve", [satellite.addrs.vault, ethers.MaxUint256]);
  await satellite.send(satellite.pool, "depositCollateral", [WETH_ID, ethers.parseEther("4")], {
    value: CCIP_FEE,
  });
  ok(`posted 4 WETH of collateral on ${satellite.chain.name}`);
  await settle("collateral to reach the hub");

  const onHub = await hub.pool.getCollateralDetailsOfUser(satellite.chain.chainId, user, WETH_ID);
  if (onHub === 0n) throw new Error("collateral never reached the hub — is the relayer running?");
  ok(`hub now sees ${ethers.formatEther(onHub)} WETH from ${satellite.chain.name}`);
  ok(`worth ${usd(await hub.pool.getUsdValue(WETH_ID, onHub))} of borrowing power at 75% LTV`);

  // ── 3. Borrow on the hub against satellite collateral ──────────────────────
  step("Borrow on the HUB against collateral held on the satellite");
  const borrowAmount = 1_000_000_000n; // 1,000 SC (6 decimals)
  const before = await hub.stable.balanceOf(user);
  await hub.send(hub.pool, "borrowLoan", [satellite.chain.chainId, WETH_ID, borrowAmount], {
    value: CCIP_FEE,
  });
  const after = await hub.stable.balanceOf(user);
  ok(`borrowed ${sc(after - before)} against collateral posted on another chain`);
  await settle("loan mirror to the satellite");

  // Loans are keyed by the chain they were *taken* on, which is the hub here —
  // the collateral chain is recorded inside the loan, not used as the key.
  const loanChainId = hub.chain.chainId;
  const loanCount = await hub.pool.getUserLoanCount(loanChainId, user, WETH_ID);
  ok(`hub records ${loanCount} loan(s), collateralised from ${satellite.chain.name}`);

  if (seedOnly) {
    process.stdout.write("\n\x1b[32mSeeded.\x1b[0m Live position left in place for the UI.\n\n");
    return;
  }

  // ── 4. Repay from the satellite chain ──────────────────────────────────────
  step("Repay from the SATELLITE chain");
  // Loan ids are 1-based (LoanController does `loan.loanId = ++loanId`), so the
  // most recent loan is at index `count`, and slot 0 is never populated.
  const loanId = loanCount;
  const loan = await hub.pool.getLoanDetails(loanChainId, user, WETH_ID, loanId);
  note(`outstanding: ${sc(loan.amountBorrowedInUSDT)}`);

  await satellite.send(satellite.stable, "approve", [satellite.addrs.vault, ethers.MaxUint256]);
  const repayAmount = loan.amountBorrowedInUSDT / 2n;
  // `loanChainId` is the hub — the loan lives there; the repayment originates
  // here and is carried across by CCIP.
  await satellite.send(satellite.pool, "repayLoan", [loanChainId, WETH_ID, repayAmount, loanId], {
    value: CCIP_FEE,
  });
  ok(`repaid ${sc(repayAmount)} from ${satellite.chain.name}`);
  await settle("repayment to reach the hub");

  const afterRepay = await hub.pool.getLoanDetails(loanChainId, user, WETH_ID, loanId);
  ok(`hub now shows ${sc(afterRepay.amountBorrowedInUSDT)} outstanding`);

  // ── 5. Liquidation ─────────────────────────────────────────────────────────
  step("Fast-forward past the due date and run the keeper");
  note("a 180-day term cannot be demonstrated on a testnet — a local node can");
  await hub.provider.send("evm_increaseTime", [200 * 24 * 60 * 60]);
  await hub.provider.send("evm_mine", []);
  ok("advanced the hub chain by 200 days");

  const gsm = new ethers.Contract(deployment.chains.eth.gsm, GSM_ABI, hub.wallet);
  hub.resetNonce();

  // The contract escalates: two penalties, then liquidation. Run the keeper
  // until it either liquidates or reports nothing left to do.
  for (let round = 1; round <= 3; round++) {
    const [needed, performData] = await gsm.checkUpkeep("0x");
    if (!needed) {
      note(`round ${round}: keeper reports nothing to do`);
      break;
    }
    await hub.send(gsm, "performUpkeep", [performData]);
    const state = await hub.pool.getLoanDetails(loanChainId, user, WETH_ID, loanId);
    ok(
      `round ${round}: penalties=${state.penaltyCount} liquidated=${state.isLiquidated} ` +
        `outstanding=${sc(state.amountBorrowedInUSDT)}`
    );
    if (state.isLiquidated) break;
    await hub.provider.send("evm_increaseTime", [40 * 24 * 60 * 60]);
    await hub.provider.send("evm_mine", []);
  }

  process.stdout.write("\n\x1b[32mScenario complete.\x1b[0m\n\n");
}

main().catch((error) => {
  process.stderr.write(`\n\x1b[31mscenario failed\x1b[0m ${error.message}\n\n`);
  process.exit(1);
});
