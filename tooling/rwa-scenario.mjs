#!/usr/bin/env node
/**
 * Drives the real-world-asset collateral lifecycle end to end.
 *
 *   node tooling/rwa-scenario.mjs
 *
 * What it demonstrates, in order:
 *   1. A holder owns a tokenised 364-day Treasury bill.
 *   2. They pledge most of it. The balance does not change.
 *   3. Moving the pledged part is refused — by the token itself.
 *   4. A rival protocol with a full approval also cannot pull it.
 *   5. They borrow on the *satellite* against collateral that never left the hub.
 *   6. Default, foreclosure, self-redemption, debt settled.
 *
 * The single fact worth watching: `balanceOf` is identical before the pledge,
 * during the loan, and right up to foreclosure. The tokens never move until a
 * legal person enforces a recorded charge.
 *
 * Requires the two-chain stack (tooling/start-demo.sh) and the RWA module
 * (script/DeployRwa.s.sol) to be deployed.
 */

import fs from "node:fs";
import { ethers } from "ethers";
import { CHAINS, DEPLOYMENT_FILE } from "./config.mjs";

/**
 * Dedicated accounts, deliberately not the deployer.
 *
 * tooling/relayer.mjs signs every cross-chain delivery with the deployer key and
 * runs continuously, so anything sharing that account loses the nonce race
 * mid-scenario. Holder and trustee are also separate from each other because
 * they are separate legal parties — the whole point is that enforcement is
 * exercised by someone other than the borrower.
 */
const HOLDER = {
  address: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
  privateKey: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
};
const TRUSTEE = {
  address: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
  privateKey: "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
};

const RWA_TOKEN_ID = 10;

const TOKEN_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function encumberedOf(address) view returns (uint256)",
  "function freeBalanceOf(address) view returns (uint256)",
  "function transfer(address,uint256) returns (bool)",
  "function approve(address,uint256) returns (bool)",
  "function transferFrom(address,address,uint256) returns (bool)",
  "function symbol() view returns (string)",
];
const ISSUER_ABI = [
  "function fundReserve(uint256)",
  "function mint(address,uint256)",
  "function owner() view returns (address)",
  "function redeem(uint256) returns (uint256)",
  "function nav() view returns (uint256)",
  "function getReserve() view returns (uint256)",
  "function quoteRedemption(uint256) view returns (uint256)",
];
const LIENS_ABI = [
  "function computeLienId(address,address,bytes32) pure returns (bytes32)",
  "function getLien(bytes32) view returns (tuple(address borrower,address token,uint256 amount,bytes32 loanRef,uint64 perfectedAt,uint64 releasedAt,bool foreclosed))",
  "function foreclose(bytes32)",
  "function isActive(bytes32) view returns (bool)",
];
const POOL_ABI = [
  "function depositRwaCollateral(uint64,uint256) payable",
  // collateralChainId first, then tokenId. Getting this order wrong encodes a
  // selector no function answers to, and the fallback reverts with empty data.
  "function borrowLoan(uint256 collateralChainId, uint64 tokenId, uint256 amount) payable",
  "function getCollateralDetailsOfUser(uint256,address,uint64) view returns (uint256)",
  "function getLtv(uint64) view returns (uint256)",
  "function getAssetMaturity(uint64) view returns (uint64)",
  "function isRwaAsset(uint64) view returns (bool)",
  "function getUsdValue(uint64,uint256) view returns (uint256)",
  "function repayLoan(uint256 loanChainId, uint64 tokenId, uint256 amount, uint256 loanId) payable",
  "function withdrawCollateral(uint64 tokenId, uint256 amount) payable",
  "function getUserLoanCount(uint256,address,uint64) view returns (uint256)",
  "function getBorrowerIndex(uint64) returns (uint256)",
  "function getLoanDetails(uint256,address,uint64,uint256) view returns (tuple(address token,uint256 amountBorrowedInUSDT,uint256 principalAmount,uint256 collateralUsed,uint256 collateralChainId,uint256 lastUpdate,address asset,uint256 userBorrowIndex,uint256 interestPaid,uint256 liquidationPoint,uint256 loanChainId,uint256 dueDate,bool isClosed,uint256 loanId,uint8 penaltyCount,bool isLiquidated))",
];
const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function mint(address,uint256) returns (bool)",
  "function approve(address,uint256) returns (bool)",
];

/** Needed to turn a raw revert selector back into a name. */
const TOKEN_ERRORS = [
  "error RWAToken__Encumbered(uint256 free, uint256 requested)",
  "error RWAToken__OverEncumbered(uint256 balance, uint256 alreadyEncumbered, uint256 requested)",
  "error RWAToken__RecipientNotEligible(address to)",
  "error RWAToken__OnlyLienRegistry(address caller)",
  "error RWAToken__OnlyEnforcementAgent(address caller)",
];

const PLEDGE_REF = ethers.keccak256(ethers.toUtf8Bytes("ASTRALEND_COLLATERAL_PLEDGE"));
const CCIP_FEE = ethers.parseEther("0.05");

let n = 0;
const step = (t) => process.stdout.write(`\n\x1b[35m${++n}. ${t}\x1b[0m\n`);
const note = (t) => process.stdout.write(`   ${t}\n`);
const ok = (t) => process.stdout.write(`   \x1b[32m✓\x1b[0m ${t}\n`);
const bad = (t) => process.stdout.write(`   \x1b[31m✗\x1b[0m ${t}\n`);
const usd = (v) => `$${Number(ethers.formatEther(v)).toLocaleString("en-US", { maximumFractionDigits: 2 })}`;
const tk = (v) => `${Number(ethers.formatEther(v)).toLocaleString("en-US", { maximumFractionDigits: 2 })}`;

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `${name} is not set. Run script/DeployRwa.s.sol and export the DEPLOY addresses it prints.`
    );
  }
  return value;
}

/**
 * Expects a call to be refused *for a specific reason*.
 *
 * Naming the expected error is not pedantry. An earlier version accepted any
 * failure and duly reported success when the transaction had actually died on a
 * nonce conflict — it would have passed with the encumbrance check removed
 * entirely, which makes it worse than no check at all.
 */
async function expectRefusal(label, expectedError, iface, fn) {
  try {
    await fn();
    bad(`${label} — SUCCEEDED, which it must not have`);
    process.exitCode = 1;
    return;
  } catch (error) {
    const data = error?.data ?? error?.info?.error?.data ?? error?.revert?.data;
    let name = error?.revert?.name ?? null;

    if (!name && typeof data === "string" && data.startsWith("0x") && data.length >= 10) {
      name = iface.parseError(data)?.name ?? null;
    }

    if (name === expectedError) {
      ok(`${label} — refused with ${name}`);
    } else {
      bad(`${label} — refused, but with ${name ?? error?.shortMessage ?? "an unknown error"}, not ${expectedError}`);
      process.exitCode = 1;
    }
  }
}

/**
 * Sends with an explicitly fetched nonce.
 *
 * Impersonation interleaves transactions from other accounts, after which the
 * provider's cached count for this wallet is stale and the next send fails with
 * "nonce too low". Fetching per send is cheap and removes the whole class.
 */
async function send(contract, method, args = [], overrides = {}) {
  const runner = contract.runner;
  const address = await runner.getAddress();

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const nonce = await runner.provider.getTransactionCount(address, "pending");
    try {
      const tx = await contract[method](...args, { ...overrides, nonce });
      const receipt = await tx.wait();
      if (receipt.status !== 1) throw new Error(`${method} reverted`);
      return receipt;
    } catch (error) {
      if (error?.code !== "NONCE_EXPIRED" || attempt === 3) throw error;
      await new Promise((r) => setTimeout(r, 250));
    }
  }
}

/**
 * Polls until a cross-chain effect lands, instead of sleeping a fixed interval.
 *
 * Delivery latency is not fixed — the relayer batches, and the round trip for a
 * loan is satellite → hub → satellite. A flat sleep either wastes time or reads
 * state that has not arrived, which is how the loan count came back as zero
 * immediately after a borrow that had in fact succeeded.
 */
async function waitUntil(label, read, ok_, timeoutMs = 30_000) {
  const started = Date.now();
  let last;
  while (Date.now() - started < timeoutMs) {
    last = await read();
    if (ok_(last)) return last;
    process.stdout.write(`   \x1b[36m⇢\x1b[0m waiting for ${label}…\r`);
    await new Promise((r) => setTimeout(r, 1500));
  }
  process.stdout.write("\r\x1b[K");
  throw new Error(`timed out waiting for ${label} (last value: ${last})`);
}

async function settle(label = "cross-chain message") {
  process.stdout.write(`   \x1b[36m⇢\x1b[0m waiting for ${label}…`);
  await new Promise((r) => setTimeout(r, 6000));
  process.stdout.write("\r\x1b[K");
}

async function main() {
  const deployment = JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));

  const hub = new ethers.JsonRpcProvider(CHAINS.eth.rpcUrl, CHAINS.eth.chainId, {
    staticNetwork: ethers.Network.from(CHAINS.eth.chainId),
  });
  const sat = new ethers.JsonRpcProvider(CHAINS.arb.rpcUrl, CHAINS.arb.chainId, {
    staticNetwork: ethers.Network.from(CHAINS.arb.chainId),
  });

  const satVault = JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8")).chains.arb.vault;
  const holder = new ethers.Wallet(HOLDER.privateKey, hub);
  const holderOnSat = new ethers.Wallet(HOLDER.privateKey, sat);
  const trustee = new ethers.Wallet(TRUSTEE.privateKey, hub);

  const tokenAddress = requireEnv("RWA_TOKEN");
  const issuerAddress = requireEnv("RWA_ISSUER");
  const liensAddress = requireEnv("RWA_LIENS");

  const token = new ethers.Contract(tokenAddress, TOKEN_ABI, holder);
  const issuer = new ethers.Contract(issuerAddress, ISSUER_ABI, holder);
  const liens = new ethers.Contract(liensAddress, LIENS_ABI, trustee);
  const pool = new ethers.Contract(deployment.chains.eth.lendingPool, POOL_ABI, holder);
  const satPool = new ethers.Contract(deployment.chains.arb.lendingPool, POOL_ABI, holderOnSat);
  const stable = new ethers.Contract(deployment.chains.eth.stableCoin, ERC20_ABI, holder);
  const satStable = new ethers.Contract(deployment.chains.arb.stableCoin, ERC20_ABI, holderOnSat);

  // ─── 1 ────────────────────────────────────────────────────────────────────
  step("The instrument");
  const symbol = await token.symbol();
  const opening = await token.balanceOf(holder.address);
  const nav = await issuer.nav();
  const maturity = await pool.getAssetMaturity(RWA_TOKEN_ID);
  const ltv = await pool.getLtv(RWA_TOKEN_ID);

  note(`holder holds ${tk(opening)} ${symbol}`);
  note(`NAV $${ethers.formatUnits(nav, 8)} per token, matures ${new Date(Number(maturity) * 1000).toDateString()}`);
  note(`LTV ${ethers.formatUnits(ltv, 16)}% — a government bill, not a volatile crypto asset`);
  if (!(await pool.isRwaAsset(RWA_TOKEN_ID))) throw new Error("asset not registered as RWA");
  ok("registered as encumbrance-based collateral");

  // Rerunnability on a persistent node. Two things can carry over: foreclosure
  // permanently removes tokens, and a run that stopped before foreclosure left
  // its charge standing. Topping up against *free* balance rather than total
  // handles both — an existing charge is deepened rather than colliding with a
  // fresh one.
  const TARGET = ethers.parseEther("1000");
  const openingFree = await token.freeBalanceOf(holder.address);
  if (openingFree < TARGET) {
    const issuerOwner = await issuer.owner();
    await hub.send("anvil_impersonateAccount", [issuerOwner]);
    await hub.send("anvil_setBalance", [issuerOwner, "0x56BC75E2D63100000"]);
    await send(
      new ethers.Contract(issuerAddress, ISSUER_ABI, await hub.getSigner(issuerOwner)),
      "mint",
      [holder.address, TARGET - openingFree]
    );
    await hub.send("anvil_stopImpersonatingAccount", [issuerOwner]);
    const carried = await token.encumberedOf(holder.address);
    if (carried > 0n) note(`a charge of ${tk(carried)} carried over from an earlier run`);
    note(`free balance topped up to ${tk(await token.freeBalanceOf(holder.address))} ${symbol}`);
  }

  // ─── 2 ────────────────────────────────────────────────────────────────────
  step("Seed the redemption reserve");
  // The stablecoin is owned by the pool, so locally we borrow its authority.
  // In production this stablecoin arrives from the custodian remitting realised
  // proceeds — an obligation of the trust deed, not something code enforces.
  const poolAddress = deployment.chains.eth.lendingPool;
  await hub.send("anvil_impersonateAccount", [poolAddress]);
  await hub.send("anvil_setBalance", [poolAddress, "0x56BC75E2D63100000"]);
  const asPool = await hub.getSigner(poolAddress);
  await send(new ethers.Contract(stable.target, ERC20_ABI, asPool), "mint",
    [holder.address, ethers.parseEther("200000")]);
  await hub.send("anvil_stopImpersonatingAccount", [poolAddress]);

  await send(stable, "approve", [issuerAddress, ethers.parseEther("150000")]);
  await send(issuer, "fundReserve", [ethers.parseEther("150000")]);
  ok(`issuer reserve ${tk(await issuer.getReserve())} SC`);

  // ─── 3 ────────────────────────────────────────────────────────────────────
  step("Pledge 800 of 1,000 — without transferring anything");
  const pledge = ethers.parseEther("800");
  const beforePledge = await token.balanceOf(holder.address);
  const chargedBefore = await token.encumberedOf(holder.address);

  // The GSM accumulates across runs on a persistent node, so the mirror check
  // later compares the delta rather than an absolute — otherwise a second run
  // reads as double-counting when it is simply prior state.
  const mirroredBefore = await satPool.getCollateralDetailsOfUser(
    CHAINS.eth.chainId, holder.address, RWA_TOKEN_ID
  );
  await send(pool, "depositRwaCollateral", [RWA_TOKEN_ID, pledge], { value: CCIP_FEE });

  const afterBalance = await token.balanceOf(holder.address);
  const encumbered = await token.encumberedOf(holder.address);
  const free = await token.freeBalanceOf(holder.address);

  note(`balance    ${tk(afterBalance)}  (was ${tk(beforePledge)})`);
  note(`encumbered ${tk(encumbered)}  (this pledge added ${tk(encumbered - chargedBefore)})`);
  note(`free       ${tk(free)}`);

  if (afterBalance !== beforePledge) {
    bad("balance changed — the tokens moved, which defeats the whole design");
    process.exitCode = 1;
  } else {
    ok("balance unchanged. The bill never left the wallet.");
  }

  if (encumbered - chargedBefore !== pledge) {
    bad(`charge rose by ${tk(encumbered - chargedBefore)}, expected ${tk(pledge)}`);
    process.exitCode = 1;
  }

  const lienId = await liens.computeLienId(holder.address, tokenAddress, PLEDGE_REF);
  const lien = await liens.getLien(lienId);
  ok(`charge perfected at ${new Date(Number(lien.perfectedAt) * 1000).toISOString()}`);

  // ─── 4 ────────────────────────────────────────────────────────────────────
  step("The pledged balance cannot be moved");
  const tokenIface = new ethers.Interface(TOKEN_ERRORS);

  // The recipient must itself be eligible, or this would be refused for holder
  // restriction rather than encumbrance and prove nothing about the charge.
  const eligibleFriend = TRUSTEE.address;

  await expectRefusal(
    "holder sends 900 to an eligible wallet",
    "RWAToken__Encumbered",
    tokenIface,
    () => send(token, "transfer", [eligibleFriend, ethers.parseEther("900")])
  );

  // ...but the free 200 moves without complaint, which is what shows the charge
  // is targeted rather than a blanket freeze.
  await send(token, "transfer", [eligibleFriend, ethers.parseEther("50")]);
  ok("the free remainder still transfers normally");

  // A rival lending protocol, eligible to hold and fully approved — i.e. the
  // ordinary DeFi deposit path, with nothing missing but the free balance.
  const rival = TRUSTEE.address;
  await send(token, "approve", [rival, ethers.parseEther("1000")]);
  await expectRefusal(
    "a rival protocol pulls it with a full approval",
    "RWAToken__Encumbered",
    tokenIface,
    () => send(
      new ethers.Contract(tokenAddress, TOKEN_ABI, trustee),
      "transferFrom",
      [holder.address, rival, ethers.parseEther("800")]
    )
  );
  note("the same holding therefore cannot back two loans anywhere");

  // ─── 5 ────────────────────────────────────────────────────────────────────
  step("Borrow on the satellite against collateral held on the hub");
  await settle("lien to mirror to the satellite");

  const mirroredAfter = await satPool.getCollateralDetailsOfUser(
    CHAINS.eth.chainId, holder.address, RWA_TOKEN_ID
  );
  const delta = mirroredAfter - mirroredBefore;
  note(`satellite collateral ${tk(mirroredBefore)} → ${tk(mirroredAfter)} (this pledge: ${tk(delta)})`);

  if (delta !== pledge) {
    bad(`mirror moved by ${tk(delta)}, expected ${tk(pledge)} — is the relayer running against this deployment?`);
    process.exitCode = 1;
  } else {
    ok("the charge crossed as a message. The asset stayed on the hub.");
    note(`the satellite has no ${symbol} contract at all — there is nothing there to bridge`);
  }

  // The satellite prices the instrument with its own copy of the accretion
  // curve. No feed, no cross-chain quote: for a bill the value is arithmetic
  // over four constants, so both chains derive it independently.
  const satNav = await satPool.getUsdValue(RWA_TOKEN_ID, ethers.parseEther("1"));
  const hubNav = await pool.getUsdValue(RWA_TOKEN_ID, ethers.parseEther("1"));
  note(`hub values 1 ${symbol} at ${usd(hubNav)}, satellite at ${usd(satNav)}`);
  note("the gap is clock skew between the nodes, not a disagreement about the curve");

  // The satellite's vault is what actually pays out, so it needs stablecoin.
  // Locally we mint it; in a real deployment it is supplied liquidity.
  const satPoolAddress = deployment.chains.arb.lendingPool;
  if ((await satStable.balanceOf(satVault)) < ethers.parseEther("50000")) {
    await sat.send("anvil_impersonateAccount", [satPoolAddress]);
    await sat.send("anvil_setBalance", [satPoolAddress, "0x56BC75E2D63100000"]);
    await send(
      new ethers.Contract(satStable.target, ERC20_ABI, await sat.getSigner(satPoolAddress)),
      "mint",
      [satVault, ethers.parseEther("500000")]
    );
    await sat.send("anvil_stopImpersonatingAccount", [satPoolAddress]);
    note(`seeded the satellite vault with ${tk(await satStable.balanceOf(satVault))} SC of lendable liquidity`);
  }

  const borrowAmount = ethers.parseEther("50000");
  const balanceBefore = await satStable.balanceOf(holder.address);

  // Captured before the borrow. Waiting on `count > 0` afterwards would be
  // satisfied instantly by any loan an earlier run left behind, and the id
  // would point at that one instead of this one.
  const loanCountBefore = await satPool.getUserLoanCount(
    CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID
  );

  await send(satPool, "borrowLoan", [CHAINS.eth.chainId, RWA_TOKEN_ID, borrowAmount], { value: CCIP_FEE });

  const received = (await satStable.balanceOf(holder.address)) - balanceBefore;
  note(`holder received ${tk(received)} SC on the satellite`);

  if (received !== borrowAmount) {
    bad(`expected ${tk(borrowAmount)} SC, received ${tk(received)}`);
    process.exitCode = 1;
  } else {
    ok("borrowed on a chain where the collateral does not exist");
  }

  // The bill has not moved, and is still fully charged.
  const stillHeld = await token.balanceOf(holder.address);
  const stillCharged = await token.encumberedOf(holder.address);
  note(`meanwhile on the hub: balance ${tk(stillHeld)}, encumbered ${tk(stillCharged)} — untouched`);

  // ─── 6 ────────────────────────────────────────────────────────────────────
  // ─── 6 ────────────────────────────────────────────────────────────────────
  step("Repay the loan on the satellite");

  // The loan is recorded on the hub and mirrored back, so it is not readable
  // the instant borrowLoan returns. The counter and the details arrive
  // separately, so waiting on the counter alone yields an empty struct — poll
  // the loan itself.
  // Two waits, and both are needed.
  //
  // Loan ids are 1-based — the counter advances before the record is written,
  // so the newest loan sits at id == count, and `count - 1` reads an empty
  // struct rather than failing. And the counter itself is mirrored back from
  // the hub, so reading it the instant borrowLoan returns gives 0, which then
  // pins the id to a slot that will never be filled.
  const loanCount = await waitUntil(
    "the loan counter to settle back to the satellite",
    () => satPool.getUserLoanCount(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID),
    (count) => count > loanCountBefore
  );
  const loanId = loanCount;

  const loanBefore = await waitUntil(
    "the loan record to settle back to the satellite",
    () => satPool.getLoanDetails(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID, loanId),
    (loan) => loan.amountBorrowedInUSDT > 0n
  );
  process.stdout.write("\r\x1b[K");
  note(`loan #${loanId} outstanding ${tk(loanBefore.amountBorrowedInUSDT)} SC, due ${new Date(Number(loanBefore.dueDate) * 1000).toDateString()}`);

  // Interest means the payoff exceeds what was borrowed, so the loan proceeds
  // alone can never settle it — a borrower funds interest from elsewhere. Give
  // the holder a small float; without it repayment fails on
  // ERC20InsufficientBalance for a few wei of accrued interest.
  await sat.send("anvil_impersonateAccount", [satPoolAddress]);
  await sat.send("anvil_setBalance", [satPoolAddress, "0x56BC75E2D63100000"]);
  await send(
    new ethers.Contract(satStable.target, ERC20_ABI, await sat.getSigner(satPoolAddress)),
    "mint",
    [holder.address, ethers.parseEther("1000")]
  );
  await sat.send("anvil_stopImpersonatingAccount", [satPoolAddress]);
  note("funded the holder with 1,000 SC to cover accrued interest");

  // The vault pulls the repayment, so it needs an allowance.
  await send(satStable, "approve", [satVault, ethers.MaxUint256]);

  /**
   * Repaying the principal alone does not close the loan.
   *
   * The controller applies payment to accrued interest first, so sending
   * exactly `amountBorrowedInUSDT` clears the interest and leaves that much
   * principal behind. The full payoff is principal scaled by
   * currentIndex / userBorrowIndex — and that number grows every second, while
   * overpaying reverts with LoanAmountExceeded. So recompute and repay until
   * it closes, which converges immediately once the remainder is dust.
   */
  let loanAfter = loanBefore;
  for (let attempt = 0; attempt < 3 && !loanAfter.isClosed; attempt += 1) {
    const index = await satPool.getBorrowerIndex.staticCall(RWA_TOKEN_ID);
    const payoff = (loanAfter.amountBorrowedInUSDT * index) / loanAfter.userBorrowIndex;
    const outstandingBefore = loanAfter.amountBorrowedInUSDT;

    await send(satPool, "repayLoan", [CHAINS.arb.chainId, RWA_TOKEN_ID, payoff, loanId], {
      value: CCIP_FEE,
    });

    // Critical: the repayment is applied on the hub and mirrored back, so the
    // satellite still reports the old figure for a moment. Reading it straight
    // away and looping would repay a second time against state that had already
    // been settled — which drains the borrower rather than closing the loan.
    loanAfter = await waitUntil(
      "the repayment to be reflected",
      () => satPool.getLoanDetails(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID, loanId),
      (loan) => loan.isClosed || loan.amountBorrowedInUSDT < outstandingBefore
    );
    process.stdout.write("\r\x1b[K");

    if (!loanAfter.isClosed) {
      note(`interest accrued mid-payment; ${tk(loanAfter.amountBorrowedInUSDT)} SC left, settling it`);
    }
  }
  note(`outstanding now ${tk(loanAfter.amountBorrowedInUSDT)} SC, closed: ${loanAfter.isClosed}`);

  if (!loanAfter.isClosed) {
    bad("loan did not close on full repayment");
    process.exitCode = 1;
  } else {
    ok("debt discharged on the chain it was drawn from");
  }

  // ─── 7 ────────────────────────────────────────────────────────────────────
  step("Withdraw the collateral — the charge lifts");

  await waitUntil(
    "the repayment to settle on the hub",
    () => pool.getLoanDetails(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID, loanId),
    (loan) => loan.isClosed
  );
  process.stdout.write("\r\x1b[K");
  ok("the hub agrees the debt is discharged");

  const chargeBeforeRelease = await token.encumberedOf(holder.address);
  await send(pool, "withdrawCollateral", [RWA_TOKEN_ID, pledge], { value: CCIP_FEE });

  const chargeAfter = await token.encumberedOf(holder.address);
  const freeAfter = await token.freeBalanceOf(holder.address);
  note(`encumbered ${tk(chargeBeforeRelease)} → ${tk(chargeAfter)}, free ${tk(freeAfter)}`);

  // The whole point: what was pledged is transferable again, and nothing ever
  // had to be sent anywhere and sent back.
  const recipient = TRUSTEE.address;
  const heldBefore = await token.balanceOf(recipient);
  await send(token, "transfer", [recipient, pledge]);
  const moved = (await token.balanceOf(recipient)) - heldBefore;

  if (moved !== pledge) {
    bad(`expected to move ${tk(pledge)} after release, moved ${tk(moved)}`);
    process.exitCode = 1;
  } else {
    ok(`the ${tk(pledge)} that could not move a moment ago now moves freely`);
  }

  // Put it back so the default path below has something to work with.
  await send(new ethers.Contract(tokenAddress, TOKEN_ABI, trustee), "transfer", [holder.address, pledge]);

  // ─── 8 ────────────────────────────────────────────────────────────────────
  step("The other ending: default and foreclosure");

  // A fresh charge. The earlier one closed, and the register advanced past it.
  await send(pool, "depositRwaCollateral", [RWA_TOKEN_ID, pledge], { value: CCIP_FEE });
  const lienId2 = await liens.computeLienId(holder.address, tokenAddress, PLEDGE_REF);
  note(`a second charge of ${tk(await token.encumberedOf(holder.address))} recorded after the first was discharged`);
  const navAtDefault = await issuer.nav();
  note(`NAV has accreted to $${ethers.formatUnits(navAtDefault, 8)}`);

  const standingCharge = await token.encumberedOf(holder.address);
  const expected = await issuer.quoteRedemption(standingCharge);
  await send(liens, "foreclose", [lienId2]);

  const holderAfter = await token.balanceOf(holder.address);
  note(`holder balance now ${tk(holderAfter)} — the 800 moved, once, under the charge`);
  note(`trustee now holds ${tk(await token.balanceOf(trustee.address))} ${symbol}`);
  ok(`charge discharged by enforcement (active: ${await liens.isActive(lienId2)})`);

  const trusteeIssuer = new ethers.Contract(issuerAddress, ISSUER_ABI, trustee);
  const trusteeStable = new ethers.Contract(stable.target, ERC20_ABI, trustee);
  const before = await trusteeStable.balanceOf(trustee.address);
  await send(trusteeIssuer, "redeem", [standingCharge]);
  const recovered = (await trusteeStable.balanceOf(trustee.address)) - before;

  note(`redeemed for ${tk(recovered)} SC (quoted ${tk(expected)})`);
  ok("the instrument liquidated itself — no court, no auction, no buyer");

  process.stdout.write("\n\x1b[32mLifecycle complete.\x1b[0m\n");
  note("Every step above has a legal name and a transaction hash.\n");
}

main().catch((error) => {
  console.error(`\n\x1b[31m${error.message}\x1b[0m\n`);
  process.exit(1);
});
