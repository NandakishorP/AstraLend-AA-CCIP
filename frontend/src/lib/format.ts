import { formatUnits, parseUnits } from "viem";

/** USD values from the backend are 1e18-scaled integers. */
const USD_DECIMALS = 18;

/**
 * Formats a 1e18-scaled USD integer as currency.
 *
 * Large balances collapse to compact notation ($1.2M) because a lending
 * dashboard is scanned, not read — precision past four significant figures is
 * noise at that size. Small balances keep cents.
 */
export function formatUsd(scaled1e18: string | bigint | undefined, options?: { compact?: boolean }): string {
  if (scaled1e18 === undefined) return "—";
  const value = Number(formatUnits(BigInt(scaled1e18), USD_DECIMALS));
  return formatUsdNumber(value, options);
}

export function formatUsdNumber(value: number, options?: { compact?: boolean }): string {
  if (!Number.isFinite(value)) return "—";
  const compact = options?.compact ?? Math.abs(value) >= 1_000_000;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    notation: compact ? "compact" : "standard",
    maximumFractionDigits: compact ? 2 : Math.abs(value) >= 1000 ? 0 : 2,
    minimumFractionDigits: compact || Math.abs(value) >= 1000 ? 0 : 2,
  }).format(value);
}

/** Formats a raw token amount using its decimals, trimming trailing zeros. */
export function formatToken(
  raw: string | bigint | undefined,
  decimals: number,
  maxFractionDigits = 4
): string {
  if (raw === undefined) return "—";
  const value = Number(formatUnits(BigInt(raw), decimals));
  if (value === 0) return "0";
  // Anything below the display precision would render as "0" and read as empty.
  if (value < 10 ** -maxFractionDigits) return `<${10 ** -maxFractionDigits}`;
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: value >= 1000 ? 2 : maxFractionDigits,
  }).format(value);
}

/** Formats a token amount together with its symbol. */
export function formatTokenAmount(
  raw: string | bigint | undefined,
  decimals: number,
  symbol: string,
  maxFractionDigits = 4
): string {
  return `${formatToken(raw, decimals, maxFractionDigits)} ${symbol}`;
}

export function formatPercent(value: number | undefined, digits = 2): string {
  if (value === undefined || !Number.isFinite(value)) return "—";
  return `${value.toFixed(digits)}%`;
}

/** Parses user input into the token's smallest unit; returns null when invalid. */
export function parseAmount(input: string, decimals: number): bigint | null {
  const trimmed = input.trim();
  if (!trimmed) return null;
  if (!/^\d*\.?\d*$/.test(trimmed)) return null;
  try {
    const value = parseUnits(trimmed as `${number}`, decimals);
    return value > 0n ? value : null;
  } catch {
    return null;
  }
}

/** Converts a raw token amount to a plain decimal string for an input field. */
export function toInputValue(raw: string | bigint, decimals: number): string {
  return formatUnits(BigInt(raw), decimals);
}

export function shortAddress(address: string | undefined, size = 4): string {
  if (!address) return "";
  return `${address.slice(0, 2 + size)}…${address.slice(-size)}`;
}

export function shortHash(hash: string): string {
  return `${hash.slice(0, 10)}…${hash.slice(-8)}`;
}

/** Relative time for activity rows: "3m ago", "2d ago". */
export function timeAgo(timestampSeconds: number | null): string {
  if (timestampSeconds === null) return "pending";
  const seconds = Math.floor(Date.now() / 1000) - timestampSeconds;
  if (seconds < 60) return "just now";
  const units: [number, string][] = [
    [60, "m"],
    [3600, "h"],
    [86_400, "d"],
    [604_800, "w"],
  ];
  let label = `${Math.floor(seconds / 604_800)}w`;
  for (let i = 0; i < units.length; i++) {
    const [threshold, suffix] = units[i]!;
    const next = units[i + 1]?.[0] ?? Infinity;
    if (seconds < next) {
      label = `${Math.floor(seconds / threshold)}${suffix}`;
      break;
    }
  }
  return `${label} ago`;
}

/** Human duration for loan due dates: "in 178 days", "overdue by 3 days". */
export function formatDueIn(days: number): string {
  if (days < 0) return `overdue by ${Math.abs(days)}d`;
  if (days === 0) return "due today";
  if (days === 1) return "due tomorrow";
  return `due in ${days}d`;
}

/** Native gas token amount, e.g. CCIP fees. */
export function formatEth(wei: string | bigint | undefined, digits = 5): string {
  if (wei === undefined) return "—";
  const value = Number(formatUnits(BigInt(wei), 18));
  if (value === 0) return "0 ETH";
  if (value < 10 ** -digits) return `<${10 ** -digits} ETH`;
  return `${value.toFixed(digits)} ETH`;
}

/**
 * Maps a health factor onto the colour ramp used across the app.
 * Kept here so the gauge, the loan rows and the summary card never disagree.
 */
export function healthTone(healthFactor: number | null): {
  tone: "neutral" | "safe" | "warn" | "danger";
  label: string;
} {
  if (healthFactor === null) return { tone: "neutral", label: "No debt" };
  if (healthFactor < 1) return { tone: "danger", label: "Liquidatable" };
  if (healthFactor < 1.2) return { tone: "danger", label: "At risk" };
  if (healthFactor < 1.6) return { tone: "warn", label: "Moderate" };
  return { tone: "safe", label: "Healthy" };
}
