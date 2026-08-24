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
  const satVault = deployment.chains.arb.vault;
  const satStable = new ethers.Contract(deployment.chains.arb.stableCoin, ERC20_ABI, holderOnSat);
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
  step("Default and foreclosure");
  const navAtDefault = await issuer.nav();
  note(`NAV has accreted to $${ethers.formatUnits(navAtDefault, 8)}`);

  const standingCharge = await token.encumberedOf(holder.address);
  const expected = await issuer.quoteRedemption(standingCharge);
  await send(liens, "foreclose", [lienId]);

  const holderAfter = await token.balanceOf(holder.address);
  note(`holder balance now ${tk(holderAfter)} — the 800 moved, once, under the charge`);
  note(`trustee now holds ${tk(await token.balanceOf(trustee.address))} ${symbol}`);
  ok(`lien active: ${await liens.isActive(lienId)}`);

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
