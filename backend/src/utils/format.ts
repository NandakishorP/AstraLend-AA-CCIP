import { PRECISION } from "../config/constants.js";

/**
 * Formatting helpers shared by the market / portfolio aggregation services.
 *
 * Everything crossing the HTTP boundary is a decimal string — JavaScript numbers
 * lose precision above 2^53 and wei values routinely exceed that. Percentages and
 * ratios are the exception: they are bounded and small, so they are emitted as
 * numbers to save the frontend a parse step.
 */

/** Converts a 1e18-scaled ratio to a percentage number, e.g. 75e16 → 75. */
export function ratioToPercent(scaled: bigint): number {
  // Multiply before dividing to keep 4 decimal places of precision.
  return Number((scaled * 10_000n) / PRECISION) / 100;
}

/** Converts a 1e18-scaled USD value to a plain number of dollars. */
export function usdToNumber(scaled1e18: bigint): number {
  return Number((scaled1e18 * 100n) / PRECISION) / 100;
}

/** Safe division for 1e18-scaled ratios; returns 0 when the denominator is 0. */
export function safeRatio(numerator: bigint, denominator: bigint): bigint {
  if (denominator === 0n) return 0n;
  return (numerator * PRECISION) / denominator;
}

/**
 * Converts a per-annum simple interest rate (1e18-scaled) into an APY that
 * accounts for continuous compounding, matching how the borrower index accrues.
 *
 * APY = e^r - 1
 */
export function aprToApy(apr1e18: bigint): number {
  const apr = Number(apr1e18) / 1e18;
  return (Math.exp(apr) - 1) * 100;
}
