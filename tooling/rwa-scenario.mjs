#!/usr/bin/env node
/**
 * Lends against a third-party tokenised security, across two chains.
 *
 *   source tooling/rwa.env && node tooling/rwa-scenario.mjs
 *
 * The security is not ours. It is an ERC-3643 issuance — the standard behind
 * OUSG, BUIDL and most permissioned RWA — and the protocol touches it only
 * through the standard interface. What makes any of this possible is one thing:
 * the issuer has appointed our lien registry as an *agent* on the token. That
 * appointment is the on-chain half of the tri-party agreement.
 *
 * What it demonstrates, in order:
 *   1. A holder owns a tokenised 364-day Treasury bill. We did not mint it.
 *   2. Our registry holds agent rights, granted by the issuer.
 *   3. Pledging freezes part of the balance in place. Nothing transfers.
 *   4. Nobody can move the frozen part — not the holder, not a rival protocol.
 *   5. They borrow on the *satellite* against collateral that never left the hub.
 *   6. They repay, and the loan closes on the chain it was drawn from.
 *   7. Withdrawal lifts the charge; the same tokens move freely again.
 *   8. A second charge runs the other way: default, foreclosure, realisation.
 *
 * Requires the two-chain stack (tooling/start-demo.sh).
 */

import fs from "node:fs";
import { ethers } from "ethers";
import { CHAINS, DEPLOYMENT_FILE } from "./config.mjs";

// Anvil #2 and #3. Not #0: relayer.mjs signs with the deployer key continuously
// and anything sharing it loses the nonce race. Holder and trustee are separate
// from each other because they are separate legal parties — the point is that
// enforcement is exercised by someone other than the borrower.
const HOLDER = {
  address: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
  privateKey: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
};
const TRUSTEE = {
  address: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
  privateKey: "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
};

const RWA_TOKEN_ID = 10;
const CCIP_FEE = ethers.parseEther("0.05");
const PLEDGE_REF = ethers.keccak256(ethers.toUtf8Bytes("ASTRALEND_COLLATERAL_PLEDGE"));

// The ERC-3643 surface the protocol depends on, plus agent introspection.
const SECURITY_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function getFrozenTokens(address) view returns (uint256)",
  "function freePartialBalanceOf(address) view returns (uint256)",
  "function transfer(address,uint256) returns (bool)",
  "function approve(address,uint256) returns (bool)",
  "function transferFrom(address,address,uint256) returns (bool)",
  "function symbol() view returns (string)",
  "function isAgent(address) view returns (bool)",
  "function mint(address,uint256)",
  "function owner() view returns (address)",
  "function unfreezePartialTokens(address,uint256)",
];
const SECURITY_ERRORS = [
  "error MockERC3643__InsufficientFreeBalance(uint256 free, uint256 requested)",
  "error MockERC3643__FreezeExceedsBalance(uint256 balance, uint256 frozen, uint256 requested)",
  "error MockERC3643__NotAgent(address caller)",
  "error MockERC3643__RecipientNotVerified(address to)",
];
const LIENS_ABI = [
  "function computeLienId(address,address,bytes32) view returns (bytes32)",
  "function getLien(bytes32) view returns (tuple(address borrower,address token,uint256 amount,bytes32 loanRef,uint64 perfectedAt,uint64 releasedAt,bool foreclosed))",
  "function foreclose(bytes32)",
  "function isActive(bytes32) view returns (bool)",
  "function assertIsAgent(address) view",
];
const DESK_ABI = [
  "function sell(uint256) returns (uint256)",
  "function fund(uint256)",
  "function quote(uint256) view returns (uint256)",
  "function cash() view returns (uint256)",
];
const POOL_ABI = [
  "function depositRwaCollateral(uint64,uint256) payable",
  "function borrowLoan(uint256 collateralChainId, uint64 tokenId, uint256 amount) payable",
  "function repayLoan(uint256 loanChainId, uint64 tokenId, uint256 amount, uint256 loanId) payable",
  "function withdrawCollateral(uint64 tokenId, uint256 amount) payable",
  "function getCollateralDetailsOfUser(uint256,address,uint64) view returns (uint256)",
  "function getUserLoanCount(uint256,address,uint64) view returns (uint256)",
  "function getBorrowerIndex(uint64) returns (uint256)",
  "function getLtv(uint64) view returns (uint256)",
  "function getAssetMaturity(uint64) view returns (uint64)",
  "function isRwaAsset(uint64) view returns (bool)",
  "function getUsdValue(uint64,uint256) view returns (uint256)",
  // Field order copied verbatim from LoanManager.LoanDetails. Inventing it
  // decodes every field against the wrong slot and silently yields zeros.
  "function getLoanDetails(uint256,address,uint64,uint256) view returns (tuple(address token,uint256 amountBorrowedInUSDT,uint256 principalAmount,uint256 collateralUsed,uint256 collateralChainId,uint256 lastUpdate,address asset,uint256 userBorrowIndex,uint256 interestPaid,uint256 liquidationPoint,uint256 loanChainId,uint256 dueDate,bool isClosed,uint256 loanId,uint8 penaltyCount,bool isLiquidated))",
];
const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function mint(address,uint256) returns (bool)",
  "function approve(address,uint256) returns (bool)",
];

let n = 0;
const step = (t) => process.stdout.write(`\n\x1b[35m${++n}. ${t}\x1b[0m\n`);
const note = (t) => process.stdout.write(`   ${t}\n`);
const ok = (t) => process.stdout.write(`   \x1b[32m✓\x1b[0m ${t}\n`);
const bad = (t) => { process.stdout.write(`   \x1b[31m✗\x1b[0m ${t}\n`); process.exitCode = 1; };
const tk = (v) => Number(ethers.formatEther(v)).toLocaleString("en-US", { maximumFractionDigits: 2 });
const usd = (v) => `$${Number(ethers.formatEther(v)).toLocaleString("en-US", { maximumFractionDigits: 2 })}`;
const clear = () => process.stdout.write("\r\x1b[K");

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set. Run: source tooling/rwa.env`);
  return value;
}

/**
 * Sends with an explicitly fetched nonce, retrying on conflict.
 *
 * Impersonation interleaves transactions from other accounts, after which the
 * provider's cached count is stale and the next send dies with "nonce too low".
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
 * Polls until a cross-chain effect lands, rather than sleeping a fixed time.
 * Delivery latency varies and a loan is a satellite → hub → satellite round
 * trip, so a flat sleep either wastes time or reads state that has not arrived.
 */
async function waitUntil(label, read, predicate, timeoutMs = 40_000) {
  const started = Date.now();
  let last;
  while (Date.now() - started < timeoutMs) {
    last = await read();
    if (predicate(last)) { clear(); return last; }
    process.stdout.write(`   \x1b[36m⇢\x1b[0m waiting for ${label}…\r`);
    await new Promise((r) => setTimeout(r, 1500));
  }
  clear();
  throw new Error(`timed out waiting for ${label}`);
}

/** Expects a refusal, and insists on the specific reason. */
async function expectRefusal(label, expectedError, iface, fn) {
  try {
    await fn();
    bad(`${label} — SUCCEEDED, which it must not have`);
  } catch (error) {
    const data = error?.data ?? error?.info?.error?.data ?? error?.revert?.data;
    let name = error?.revert?.name ?? null;
    if (!name && typeof data === "string" && data.startsWith("0x") && data.length >= 10) {
      name = iface.parseError(data)?.name ?? null;
    }
    if (name === expectedError) ok(`${label} — refused with ${name}`);
    else bad(`${label} — refused with ${name ?? error?.shortMessage ?? "an unknown error"}, not ${expectedError}`);
  }
}

async function main() {
  const deployment = JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));
  const hub = new ethers.JsonRpcProvider(CHAINS.eth.rpcUrl, CHAINS.eth.chainId, {
    staticNetwork: ethers.Network.from(CHAINS.eth.chainId),
  });
  const sat = new ethers.JsonRpcProvider(CHAINS.arb.rpcUrl, CHAINS.arb.chainId, {
    staticNetwork: ethers.Network.from(CHAINS.arb.chainId),
  });

  const holder = new ethers.Wallet(HOLDER.privateKey, hub);
  const holderOnSat = new ethers.Wallet(HOLDER.privateKey, sat);
  const trustee = new ethers.Wallet(TRUSTEE.privateKey, hub);

  const securityAddress = requireEnv("RWA_SECURITY");
  const liensAddress = requireEnv("RWA_LIENS");
  const deskAddress = requireEnv("RWA_DESK");

  const security = new ethers.Contract(securityAddress, SECURITY_ABI, holder);
  const liens = new ethers.Contract(liensAddress, LIENS_ABI, trustee);
  const desk = new ethers.Contract(deskAddress, DESK_ABI, trustee);
  const pool = new ethers.Contract(deployment.chains.eth.lendingPool, POOL_ABI, holder);
  const satPool = new ethers.Contract(deployment.chains.arb.lendingPool, POOL_ABI, holderOnSat);
  const stable = new ethers.Contract(deployment.chains.eth.stableCoin, ERC20_ABI, holder);
  const satStable = new ethers.Contract(deployment.chains.arb.stableCoin, ERC20_ABI, holderOnSat);
  const satVault = deployment.chains.arb.vault;
  const satPoolAddress = deployment.chains.arb.lendingPool;
  const errors = new ethers.Interface(SECURITY_ERRORS);

  /** Mints via the issuer's own agency. We could not do this in production. */
  async function issuerMint(to, amount) {
    const issuer = await security.owner();
    await hub.send("anvil_impersonateAccount", [issuer]);
    await hub.send("anvil_setBalance", [issuer, "0x56BC75E2D63100000"]);
    await send(new ethers.Contract(securityAddress, SECURITY_ABI, await hub.getSigner(issuer)),
      "mint", [to, amount]);
    await hub.send("anvil_stopImpersonatingAccount", [issuer]);
  }

  async function mintStable(provider, tokenAddress, owner, to, amount) {
    await provider.send("anvil_impersonateAccount", [owner]);
    await provider.send("anvil_setBalance", [owner, "0x56BC75E2D63100000"]);
    await send(new ethers.Contract(tokenAddress, ERC20_ABI, await provider.getSigner(owner)),
      "mint", [to, amount]);
    await provider.send("anvil_stopImpersonatingAccount", [owner]);
  }

  // ─── 1 ────────────────────────────────────────────────────────────────────
  step("The security — somebody else's issuance");
  const symbol = await security.symbol();
  const maturity = await pool.getAssetMaturity(RWA_TOKEN_ID);
  const ltv = await pool.getLtv(RWA_TOKEN_ID);

  note(`ERC-3643 security ${symbol} at ${securityAddress}`);
  note(`issued by ${await security.owner()} — not by this protocol`);
  note(`matures ${new Date(Number(maturity) * 1000).toDateString()}, LTV ${ethers.formatUnits(ltv, 16)}%`);
  if (!(await pool.isRwaAsset(RWA_TOKEN_ID))) throw new Error("asset not registered as RWA");
  ok("registered as encumbrance-based collateral");

  // ─── 2 ────────────────────────────────────────────────────────────────────
  step("The tri-party agreement, on-chain");
  const isAgent = await security.isAgent(liensAddress);
  note(`lien registry ${liensAddress}`);
  if (!isAgent) { bad("registry is NOT an agent — every pledge would revert"); return; }
  await liens.assertIsAgent(securityAddress);
  ok("the issuer has appointed our registry an agent on the security");
  note("that appointment is what lets us freeze a holding without ever holding it");

  // Rerunnability: top up against *free* balance, so a charge left standing by
  // an earlier run is deepened rather than colliding with a fresh one.
  const TARGET = ethers.parseEther("1000");
  const openingFree = await security.freePartialBalanceOf(holder.address);
  if (openingFree < TARGET) {
    await issuerMint(holder.address, TARGET - openingFree);
    note(`issuer minted the holder up to ${tk(await security.freePartialBalanceOf(holder.address))} free ${symbol}`);
  }

  // ─── 3 ────────────────────────────────────────────────────────────────────
  step("Pledge 800 of 1,000 — without transferring anything");
  const pledge = ethers.parseEther("800");
  const beforePledge = await security.balanceOf(holder.address);
  const frozenBefore = await security.getFrozenTokens(holder.address);
  const mirroredBefore = await satPool.getCollateralDetailsOfUser(
    CHAINS.eth.chainId, holder.address, RWA_TOKEN_ID
  );

  await send(pool, "depositRwaCollateral", [RWA_TOKEN_ID, pledge], { value: CCIP_FEE });

  const afterBalance = await security.balanceOf(holder.address);
  const frozen = await security.getFrozenTokens(holder.address);
  note(`balance  ${tk(afterBalance)}  (was ${tk(beforePledge)})`);
  note(`frozen   ${tk(frozen)}  (this pledge added ${tk(frozen - frozenBefore)})`);
  note(`free     ${tk(await security.freePartialBalanceOf(holder.address))}`);

  if (afterBalance !== beforePledge) bad("balance changed — the security moved, which defeats the design");
  else ok("balance unchanged. The bill never left the wallet.");

  const lienId = await liens.computeLienId(holder.address, securityAddress, PLEDGE_REF);
  ok(`charge perfected at ${new Date(Number((await liens.getLien(lienId)).perfectedAt) * 1000).toISOString()}`);

  // ─── 4 ────────────────────────────────────────────────────────────────────
  step("The frozen balance cannot be moved");
  await expectRefusal(
    "holder sends 900 to a verified wallet", "MockERC3643__InsufficientFreeBalance", errors,
    () => send(security, "transfer", [TRUSTEE.address, ethers.parseEther("900")])
  );
  await send(security, "transfer", [TRUSTEE.address, ethers.parseEther("50")]);
  ok("the free remainder still transfers normally");

  await send(security, "approve", [TRUSTEE.address, ethers.parseEther("1000")]);
  await expectRefusal(
    "a rival protocol pulls it with a full approval", "MockERC3643__InsufficientFreeBalance", errors,
    () => send(new ethers.Contract(securityAddress, SECURITY_ABI, trustee),
      "transferFrom", [holder.address, TRUSTEE.address, ethers.parseEther("800")])
  );
  await expectRefusal(
    "holder tries to unfreeze their own collateral", "MockERC3643__NotAgent", errors,
    () => send(security, "unfreezePartialTokens", [holder.address, ethers.parseEther("800")])
  );
  note("the same holding therefore cannot back two loans, at this venue or any other");

  // ─── 5 ────────────────────────────────────────────────────────────────────
  step("Borrow on the satellite against collateral held on the hub");
  const mirroredAfter = await waitUntil(
    "the charge to mirror to the satellite",
    () => satPool.getCollateralDetailsOfUser(CHAINS.eth.chainId, holder.address, RWA_TOKEN_ID),
    (v) => v - mirroredBefore === pledge
  );
  note(`satellite collateral ${tk(mirroredBefore)} → ${tk(mirroredAfter)} (this pledge: ${tk(pledge)})`);
  ok("the charge crossed as a message. The security stayed on the hub.");
  note(`there is no ${symbol} contract on the satellite — nothing exists there to bridge`);

  note(`hub prices 1 ${symbol} at ${usd(await pool.getUsdValue(RWA_TOKEN_ID, ethers.parseEther("1")))}, ` +
       `satellite at ${usd(await satPool.getUsdValue(RWA_TOKEN_ID, ethers.parseEther("1")))}`);

  if ((await satStable.balanceOf(satVault)) < ethers.parseEther("100000")) {
    await mintStable(sat, satStable.target, satPoolAddress, satVault, ethers.parseEther("500000"));
    note(`seeded the satellite vault with ${tk(await satStable.balanceOf(satVault))} SC of lendable liquidity`);
  }

  const borrowAmount = ethers.parseEther("50000");
  const cashBefore = await satStable.balanceOf(holder.address);
  const loanCountBefore = await satPool.getUserLoanCount(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID);

  await send(satPool, "borrowLoan", [CHAINS.eth.chainId, RWA_TOKEN_ID, borrowAmount], { value: CCIP_FEE });

  const received = (await satStable.balanceOf(holder.address)) - cashBefore;
  if (received !== borrowAmount) bad(`expected ${tk(borrowAmount)} SC, received ${tk(received)}`);
  else ok(`borrowed ${tk(received)} SC on a chain where the collateral does not exist`);
  note(`meanwhile on the hub: balance ${tk(await security.balanceOf(holder.address))}, ` +
       `frozen ${tk(await security.getFrozenTokens(holder.address))} — untouched`);

  // ─── 6 ────────────────────────────────────────────────────────────────────
  step("Repay on the satellite");
  // Loan ids are 1-based (the counter advances before the record is written) and
  // both counter and record mirror back from the hub, arriving separately.
  const loanCount = await waitUntil(
    "the loan counter to settle back",
    () => satPool.getUserLoanCount(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID),
    (c) => c > loanCountBefore
  );
  const loanId = loanCount;
  let loan = await waitUntil(
    "the loan record to settle back",
    () => satPool.getLoanDetails(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID, loanId),
    (l) => l.amountBorrowedInUSDT > 0n
  );
  note(`loan #${loanId} outstanding ${tk(loan.amountBorrowedInUSDT)} SC, due ${new Date(Number(loan.dueDate) * 1000).toDateString()}`);

  // Interest means the payoff exceeds what was borrowed, so loan proceeds alone
  // can never settle it — a borrower funds interest from elsewhere.
  await mintStable(sat, satStable.target, satPoolAddress, holder.address, ethers.parseEther("1000"));
  await send(satStable, "approve", [satVault, ethers.MaxUint256]);
  note("funded the holder with 1,000 SC to cover accrued interest");

  for (let attempt = 0; attempt < 3 && !loan.isClosed; attempt += 1) {
    const index = await satPool.getBorrowerIndex.staticCall(RWA_TOKEN_ID);
    const payoff = (loan.amountBorrowedInUSDT * index) / loan.userBorrowIndex;
    const outstanding = loan.amountBorrowedInUSDT;

    await send(satPool, "repayLoan", [CHAINS.arb.chainId, RWA_TOKEN_ID, payoff, loanId], { value: CCIP_FEE });

    // The repayment applies on the hub and mirrors back, so the satellite still
    // reports the old figure briefly. Looping on that would repay twice.
    loan = await waitUntil(
      "the repayment to be reflected",
      () => satPool.getLoanDetails(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID, loanId),
      (l) => l.isClosed || l.amountBorrowedInUSDT < outstanding
    );
    if (!loan.isClosed) note(`interest accrued mid-payment; ${tk(loan.amountBorrowedInUSDT)} SC left`);
  }

  if (!loan.isClosed) bad("loan did not close on full repayment");
  else ok("debt discharged on the chain it was drawn from");

  // ─── 7 ────────────────────────────────────────────────────────────────────
  step("Withdraw the collateral — the charge lifts");
  await waitUntil(
    "the repayment to settle on the hub",
    () => pool.getLoanDetails(CHAINS.arb.chainId, holder.address, RWA_TOKEN_ID, loanId),
    (l) => l.isClosed
  );
  ok("the hub agrees the debt is discharged");

  const frozenBeforeRelease = await security.getFrozenTokens(holder.address);
  await send(pool, "withdrawCollateral", [RWA_TOKEN_ID, pledge], { value: CCIP_FEE });
  note(`frozen ${tk(frozenBeforeRelease)} → ${tk(await security.getFrozenTokens(holder.address))}`);

  const heldBefore = await security.balanceOf(TRUSTEE.address);
  await send(security, "transfer", [TRUSTEE.address, pledge]);
  if ((await security.balanceOf(TRUSTEE.address)) - heldBefore !== pledge) bad("release did not free the tokens");
  else ok(`the ${tk(pledge)} that could not move a moment ago now moves freely`);

  await send(new ethers.Contract(securityAddress, SECURITY_ABI, trustee), "transfer", [holder.address, pledge]);

  // ─── 8 ────────────────────────────────────────────────────────────────────
  step("The other ending: default and foreclosure");
  await send(pool, "depositRwaCollateral", [RWA_TOKEN_ID, pledge], { value: CCIP_FEE });
  const lienId2 = await liens.computeLienId(holder.address, securityAddress, PLEDGE_REF);
  note(`a second charge of ${tk(await security.getFrozenTokens(holder.address))} recorded after the first was discharged`);

  const standing = await security.getFrozenTokens(holder.address);
  if ((await desk.cash()) < ethers.parseEther("100000")) {
    await mintStable(hub, stable.target, deployment.chains.eth.lendingPool, holder.address, ethers.parseEther("300000"));
    await send(stable, "approve", [deskAddress, ethers.parseEther("300000")]);
    await send(new ethers.Contract(deskAddress, DESK_ABI, holder), "fund", [ethers.parseEther("300000")]);
    note(`redemption desk funded with ${tk(await desk.cash())} SC of buying power`);
  }

  const freeBefore = await security.freePartialBalanceOf(holder.address);
  await send(liens, "foreclose", [lienId2]);

  note(`holder balance ${tk(await security.balanceOf(holder.address))}, ` +
       `frozen ${tk(await security.getFrozenTokens(holder.address))}`);
  if ((await security.getFrozenTokens(holder.address)) !== 0n) {
    bad("a freeze survived a discharged charge");
  } else if ((await security.freePartialBalanceOf(holder.address)) !== freeBefore) {
    bad("foreclosure took the holder's free tokens instead of the pledged ones");
  } else {
    ok("enforcement took exactly what was pledged, and left no orphaned freeze");
  }
  note(`trustee now holds ${tk(await security.balanceOf(TRUSTEE.address))} ${symbol}`);

  const quoted = await desk.quote(standing);
  const trusteeStable = new ethers.Contract(stable.target, ERC20_ABI, trustee);
  const before = await trusteeStable.balanceOf(TRUSTEE.address);
  await send(new ethers.Contract(securityAddress, SECURITY_ABI, trustee), "approve", [deskAddress, standing]);
  await send(desk, "sell", [standing]);
  const recovered = (await trusteeStable.balanceOf(TRUSTEE.address)) - before;

  note(`realised for ${tk(recovered)} SC (quoted ${tk(quoted)})`);
  ok("collateral turned back into money — off-chain in reality, modelled here");

  process.stdout.write("\n\x1b[32mLifecycle complete.\x1b[0m\n");
  note("The security was never held by the protocol at any point.\n");
}

main().catch((error) => {
  process.stderr.write(`\n\x1b[31m${error.message}\x1b[0m\n`);
  process.exit(1);
});
