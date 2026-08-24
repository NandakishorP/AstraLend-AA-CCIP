import { ethers } from "ethers";
import { getProvider } from "../blockchain/providers.js";
import { env } from "../config/env.js";
import { ConfigError } from "../errors.js";
import RWATokenAbi from "../abis/RWAToken.json" with { type: "json" };
import LienRegistryAbi from "../abis/LienRegistry.json" with { type: "json" };
import EligibilityAbi from "../abis/EligibilityRegistry.json" with { type: "json" };
import NavOracleAbi from "../abis/TBillNavOracle.json" with { type: "json" };
import type { ChainKey } from "../config/env.js";

/**
 * Reads for encumbered real-world collateral.
 *
 * The distinction that shapes every function here: an encumbrance leaves no
 * balance anywhere to read. With crypto collateral you can ask the vault what
 * it holds. With a pledged instrument the borrower still holds the tokens, and
 * the only evidence of the charge is the register. So "how much collateral does
 * this user have" becomes two numbers that must be reported side by side —
 * what they hold, and how much of it is spoken for.
 *
 * Hub-only throughout. The instrument exists on one chain; satellites see
 * mirrored state, never the asset.
 */

const HUB: ChainKey = "eth";

function requireAddress(value: string | undefined, name: string): string {
  if (!value) {
    throw new ConfigError(
      `${name} is not configured. Deploy the RWA module and set it in the environment.`
    );
  }
  return value;
}

function token() {
  return new ethers.Contract(
    requireAddress(env.RWA_TOKEN_ADDRESS, "RWA_TOKEN_ADDRESS"),
    RWATokenAbi,
    getProvider(HUB)
  );
}

function lienRegistry() {
  return new ethers.Contract(
    requireAddress(env.RWA_LIEN_REGISTRY_ADDRESS, "RWA_LIEN_REGISTRY_ADDRESS"),
    LienRegistryAbi,
    getProvider(HUB)
  );
}

function eligibilityRegistry() {
  return new ethers.Contract(
    requireAddress(env.RWA_ELIGIBILITY_ADDRESS, "RWA_ELIGIBILITY_ADDRESS"),
    EligibilityAbi,
    getProvider(HUB)
  );
}

function navOracle() {
  return new ethers.Contract(
    requireAddress(env.RWA_NAV_ORACLE_ADDRESS, "RWA_NAV_ORACLE_ADDRESS"),
    NavOracleAbi,
    getProvider(HUB)
  );
}

export interface RwaHolding {
  userAddress: string;
  tokenAddress: string;
  symbol: string;
  decimals: number;
  /** Everything the holder owns. Unchanged by pledging — that is the point. */
  balance: string;
  /** The charge standing against it. */
  encumbered: string;
  /** What remains transferable. */
  free: string;
  balanceUsd: string;
  encumberedUsd: string;
  freeUsd: string;
  navPerToken: string;
  eligible: boolean;
  eligibilityExpiry: number | null;
}

export interface NavSnapshot {
  tokenAddress: string;
  description: string;
  navPerToken: string;
  navDecimals: number;
  issuePrice: string;
  faceValue: string;
  issueDate: number;
  maturityDate: number;
  isMatured: boolean;
  /** Fraction of the discount already earned, 0 to 1. */
  accretionProgress: number;
  daysToMaturity: number;
  /**
   * Always false. A bill's value is arithmetic, not an observation, so it is
   * recomputed on every read. Reported explicitly because every other RWA
   * design has to answer "what if the feed goes stale" and this one does not.
   */
  isStale: false;
}

function toUsd(amount: bigint, decimals: number, nav: bigint, navDecimals: number): string {
  // Multiply before dividing so the small numbers survive the round trip.
  const scaled = (amount * nav) / 10n ** BigInt(navDecimals);
  return ethers.formatUnits(scaled, decimals);
}

export async function getNav(): Promise<NavSnapshot> {
  const oracle = navOracle();
  const [description, roundData, navDecimals, issuePrice, faceValue, issueDate, maturityDate, matured] =
    await Promise.all([
      oracle.description() as Promise<string>,
      oracle.latestRoundData() as Promise<[bigint, bigint, bigint, bigint, bigint]>,
      oracle.decimals() as Promise<bigint>,
      oracle.issuePrice() as Promise<bigint>,
      oracle.faceValue() as Promise<bigint>,
      oracle.issueDate() as Promise<bigint>,
      oracle.maturityDate() as Promise<bigint>,
      oracle.isMatured() as Promise<boolean>,
    ]);

  const nav = roundData[1];
  const discount = faceValue - issuePrice;
  const earned = nav - issuePrice;
  const now = Math.floor(Date.now() / 1000);
  const maturity = Number(maturityDate);

  return {
    tokenAddress: requireAddress(env.RWA_TOKEN_ADDRESS, "RWA_TOKEN_ADDRESS"),
    description,
    navPerToken: ethers.formatUnits(nav, Number(navDecimals)),
    navDecimals: Number(navDecimals),
    issuePrice: ethers.formatUnits(issuePrice, Number(navDecimals)),
    faceValue: ethers.formatUnits(faceValue, Number(navDecimals)),
    issueDate: Number(issueDate),
    maturityDate: maturity,
    isMatured: matured,
    accretionProgress: discount === 0n ? 1 : Number((earned * 10000n) / discount) / 10000,
    daysToMaturity: Math.max(0, Math.ceil((maturity - now) / 86400)),
    isStale: false,
  };
}

export async function getHolding(userAddress: string): Promise<RwaHolding> {
  const rwa = token();
  const eligibility = eligibilityRegistry();

  const [balance, encumbered, symbol, decimals, nav, eligible, status] = await Promise.all([
    rwa.balanceOf(userAddress) as Promise<bigint>,
    rwa.encumberedOf(userAddress) as Promise<bigint>,
    rwa.symbol() as Promise<string>,
    rwa.decimals() as Promise<bigint>,
    getNav(),
    eligibility.isEligible(userAddress) as Promise<boolean>,
    eligibility.getStatus(userAddress) as Promise<{ expiry: bigint }>,
  ]);

  const dec = Number(decimals);
  const navRaw = ethers.parseUnits(nav.navPerToken, nav.navDecimals);
  const free = balance - encumbered;

  return {
    userAddress,
    tokenAddress: nav.tokenAddress,
    symbol,
    decimals: dec,
    balance: ethers.formatUnits(balance, dec),
    encumbered: ethers.formatUnits(encumbered, dec),
    free: ethers.formatUnits(free, dec),
    balanceUsd: toUsd(balance, dec, navRaw, nav.navDecimals),
    encumberedUsd: toUsd(encumbered, dec, navRaw, nav.navDecimals),
    freeUsd: toUsd(free, dec, navRaw, nav.navDecimals),
    navPerToken: nav.navPerToken,
    eligible,
    eligibilityExpiry: status.expiry > 0n ? Number(status.expiry) : null,
  };
}

export interface LienView {
  lienId: string;
  /** Which charge in the holder's history this is, counting from zero. */
  sequence: number;
  borrower: string;
  tokenAddress: string;
  amount: string;
  loanRef: string;
  perfectedAt: number;
  releasedAt: number | null;
  foreclosed: boolean;
  active: boolean;
}

const PLEDGE_REF = ethers.keccak256(ethers.toUtf8Bytes("ASTRALEND_COLLATERAL_PLEDGE"));

/**
 * Lien id for a specific point in the holder's pledge history.
 *
 * Computed client-side because the contract's `computeLienId` only ever answers
 * for the *current* sequence, and reading closed charges means asking about
 * earlier ones.
 */
function lienIdAt(borrower: string, tokenAddress: string, sequence: number): string {
  return ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["address", "address", "bytes32", "uint256"],
      [borrower, tokenAddress, PLEDGE_REF, sequence]
    )
  );
}

/**
 * The borrower's most recent charge, open or closed.
 *
 * One running-account lien per (borrower, asset), matching how the pool
 * aggregates collateral — topping up deepens the same pledge rather than
 * opening another. When a charge closes the sequence advances, so the current
 * id points at a charge that does not exist yet; falling back one step is what
 * makes a foreclosed or released lien still readable. The register is
 * append-only and the UI should be able to show that.
 */
export async function getLien(userAddress: string): Promise<LienView | null> {
  const registry = lienRegistry();
  const tokenAddress = requireAddress(env.RWA_TOKEN_ADDRESS, "RWA_TOKEN_ADDRESS");

  const sequence = Number(await registry.pledgeSequence(userAddress, tokenAddress));

  // Current charge first; if none is open, the one that just closed.
  const candidates = sequence > 0 ? [sequence, sequence - 1] : [sequence];

  for (const seq of candidates) {
    const lienId = lienIdAt(userAddress, tokenAddress, seq);
    const lien = await registry.getLien(lienId);
    if (lien.perfectedAt === 0n) continue;

    const decimals = Number(await token().decimals());
    return {
      lienId,
      sequence: seq,
      borrower: lien.borrower,
      tokenAddress: lien.token,
      amount: ethers.formatUnits(lien.amount, decimals),
      loanRef: lien.loanRef,
      perfectedAt: Number(lien.perfectedAt),
      releasedAt: lien.releasedAt > 0n ? Number(lien.releasedAt) : null,
      foreclosed: lien.foreclosed,
      active: lien.releasedAt === 0n && !lien.foreclosed,
    };
  }

  return null;
}

export function isConfigured(): boolean {
  return Boolean(
    env.RWA_TOKEN_ADDRESS && env.RWA_LIEN_REGISTRY_ADDRESS && env.RWA_NAV_ORACLE_ADDRESS
  );
}
