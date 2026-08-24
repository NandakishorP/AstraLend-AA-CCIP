import { ethers } from "ethers";
import { createRequire } from "module";
import { type ChainKey, CHAIN_CONFIGS, requireAddress } from "../config/env.js";
import { getProvider } from "../blockchain/providers.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { getResolvedTokens } from "./token.service.js";
import { cached } from "../utils/cache.js";

const require = createRequire(import.meta.url);
const { abi: LendingPoolABI } = require("../abis/LendingPoolContract.json") as {
  abi: ethers.InterfaceAbi;
};

const poolInterface = new ethers.Interface(LendingPoolABI);

import { eventRepo, indexerRepo, type EventRow } from "../db/repositories.js";

/** How far back to scan when the caller does not specify a starting block. */
const DEFAULT_LOOKBACK_BLOCKS = 100_000;

/** Providers cap `eth_getLogs` spans; scan in windows and merge the results. */
const LOG_WINDOW_BLOCKS = 45_000;

const ACTIVITY_TTL_MS = 15_000;

/**
 * Every protocol event the UI renders, mapped to a stable, human-facing kind.
 * Events not listed here (cross-chain plumbing, admin) are ignored.
 */
const EVENT_KINDS: Record<string, { kind: ActivityKind; label: string }> = {
  LiquidityDeposited: { kind: "supply", label: "Supplied liquidity" },
  DepositWithdrawn: { kind: "withdraw", label: "Withdrew liquidity" },
  CollateralDeposited: { kind: "collateral-deposit", label: "Deposited collateral" },
  CollateralWithdrawed: { kind: "collateral-withdraw", label: "Withdrew collateral" },
  CollateralReleased: { kind: "collateral-release", label: "Collateral released" },
  LoanBorrowed: { kind: "borrow", label: "Borrowed" },
  LoanRepaid: { kind: "repay", label: "Repaid loan" },
  LpTokensBurned: { kind: "lp-burn", label: "Burned LP tokens" },
  DepositCollateralInitiated: { kind: "ccip-out", label: "Cross-chain collateral sent" },
  TokenTransferInitiated: { kind: "ccip-out", label: "Cross-chain transfer sent" },
  TokensReceivedFromCrossChain: { kind: "ccip-in", label: "Cross-chain transfer received" },
};

export type ActivityKind =
  | "supply"
  | "withdraw"
  | "collateral-deposit"
  | "collateral-withdraw"
  | "collateral-release"
  | "borrow"
  | "repay"
  | "lp-burn"
  | "ccip-out"
  | "ccip-in";

export interface ActivityEvent {
  kind: ActivityKind;
  /** Human-readable action, e.g. "Supplied liquidity" */
  label: string;
  /** Raw Solidity event name */
  eventName: string;
  txHash: string;
  blockNumber: number;
  logIndex: number;
  /** Unix seconds; null when the block header could not be fetched */
  timestamp: number | null;
  timestampISO: string | null;
  /** Token address involved, when the event carries one */
  tokenAddress: string | null;
  tokenSymbol: string | null;
  tokenDecimals: number | null;
  /** Primary amount, in the smallest unit of the token above */
  amount: string | null;
  /** Remaining decoded fields, stringified — rendered in the detail drawer */
  extra: Record<string, string>;
}

export interface ActivityFeed {
  userAddress: string;
  chain: ChainKey;
  chainId: number;
  events: ActivityEvent[];
  /** First block scanned — pass back as `fromBlock` to page further back */
  fromBlock: number;
  toBlock: number;
}

/**
 * Reads a user's protocol history.
 *
 * Served from the indexed database, which turns a multi-second `eth_getLogs`
 * sweep into a keyed index lookup. When the indexer is disabled or has not yet
 * reached the blocks in question, this falls back to scanning the chain directly
 * so the endpoint never depends on the indexer being healthy.
 *
 * @param userAddress - Wallet whose history to read
 * @param chain       - Chain to read
 * @param limit       - Maximum events to return, newest first
 * @param fromBlock   - Optional explicit start block for the fallback scan
 */
async function getUserActivityFromChain(
  userAddress: string,
  chain: ChainKey,
  limit = 50,
  fromBlock?: number
): Promise<ActivityFeed> {
  const cacheKey = `activity:${chain}:${userAddress.toLowerCase()}:${limit}:${fromBlock ?? "auto"}`;

  return cached(cacheKey, ACTIVITY_TTL_MS, async () => {
    try {
      const config = CHAIN_CONFIGS[chain];
      const provider = getProvider(chain);
      const poolAddress = requireAddress(chain, "lendingPool");

      const latest = await provider.getBlockNumber();
      const start = Math.max(0, fromBlock ?? latest - DEFAULT_LOOKBACK_BLOCKS);
      const userTopic = ethers.zeroPadValue(ethers.getAddress(userAddress), 32);

      // ── Scan in windows, newest first, stopping once `limit` is satisfied ──
      const logs: ethers.Log[] = [];
      for (let to = latest; to >= start && logs.length < limit * 2; to -= LOG_WINDOW_BLOCKS) {
        const from = Math.max(start, to - LOG_WINDOW_BLOCKS + 1);
        try {
          const window = await provider.getLogs({
            address: poolAddress,
            topics: [null, userTopic],
            fromBlock: from,
            toBlock: to,
          });
          logs.push(...window);
        } catch {
          // A provider may reject an over-wide range or a pruned block span.
          // Skip the window rather than failing the whole feed.
        }
        if (from === start) break;
      }

      const tokens = await getResolvedTokens(chain);
      const symbolByAddress = new Map(
        tokens.map((t) => [t.address.toLowerCase(), { symbol: t.symbol, decimals: t.decimals }])
      );

      // ── Decode ────────────────────────────────────────────────────────────
      const decoded = logs
        .map((log) => decodeActivity(log, symbolByAddress))
        .filter((e): e is ActivityEvent => e !== null)
        .sort((a, b) => b.blockNumber - a.blockNumber || b.logIndex - a.logIndex)
        .slice(0, limit);

      // ── Timestamps: one header fetch per distinct block ───────────────────
      const blockNumbers = [...new Set(decoded.map((e) => e.blockNumber))];
      const timestamps = new Map<number, number>();
      await Promise.all(
        blockNumbers.map(async (n) => {
          const block = await provider.getBlock(n).catch(() => null);
          if (block) timestamps.set(n, block.timestamp);
        })
      );

      for (const event of decoded) {
        const ts = timestamps.get(event.blockNumber);
        if (ts !== undefined) {
          event.timestamp = ts;
          event.timestampISO = new Date(ts * 1000).toISOString();
        }
      }

      return {
        userAddress,
        chain,
        chainId: config.chainId,
        events: decoded,
        fromBlock: start,
        toBlock: latest,
      };
    } catch (err) {
      wrapBlockchainError(err);
    }
  });
}

/** Turns one raw log into an ActivityEvent, or null if it is not a UI-facing event. */
function decodeActivity(
  log: ethers.Log,
  symbolByAddress: Map<string, { symbol: string; decimals: number }>
): ActivityEvent | null {
  let parsed: ethers.LogDescription | null = null;
  try {
    parsed = poolInterface.parseLog({ topics: [...log.topics], data: log.data });
  } catch {
    return null;
  }
  if (!parsed) return null;

  const mapping = EVENT_KINDS[parsed.name];
  if (!mapping) return null;

  const extra: Record<string, string> = {};
  let tokenAddress: string | null = null;
  let amount: string | null = null;

  parsed.fragment.inputs.forEach((input, i) => {
    const value = parsed.args[i];
    // An indexed struct (LoanBorrowed carries one) is hashed by the EVM, so the
    // topic holds a digest rather than the fields — nothing useful to surface.
    if (input.type === "tuple") return;

    const asString = value?.toString() ?? "";
    if (input.name === "user" || input.name === "user_") return;

    if (input.type === "address" && tokenAddress === null && input.name !== "user") {
      tokenAddress = ethers.getAddress(asString);
      return;
    }
    if (amount === null && input.type.startsWith("uint") && /amount|total/i.test(input.name)) {
      amount = asString;
      return;
    }
    extra[input.name] = asString;
  });

  const meta = tokenAddress ? symbolByAddress.get((tokenAddress as string).toLowerCase()) : undefined;

  return {
    kind: mapping.kind,
    label: mapping.label,
    eventName: parsed.name,
    txHash: log.transactionHash,
    blockNumber: log.blockNumber,
    logIndex: log.index,
    timestamp: null,
    timestampISO: null,
    tokenAddress,
    tokenSymbol: meta?.symbol ?? null,
    tokenDecimals: meta?.decimals ?? null,
    amount,
    extra,
  };
}

// ─── Database-backed feed ─────────────────────────────────────────────────────

/**
 * Reads a user's activity from the indexer's database.
 *
 * This is the path every request takes once the indexer has caught up. It costs
 * one indexed lookup rather than a block-range sweep, so the feed responds in
 * single-digit milliseconds regardless of how far back the history goes.
 *
 * If the database has nothing for this user — indexer disabled, still catching
 * up, or a genuinely empty history — the chain scan runs instead. That keeps a
 * cold start correct at the cost of being slow, rather than wrongly reporting
 * "no activity".
 */
export async function getUserActivity(
  userAddress: string,
  chain: ChainKey,
  limit = 50,
  fromBlock?: number
): Promise<ActivityFeed> {
  const config = CHAIN_CONFIGS[chain];
  const address = userAddress.toLowerCase();

  const indexed = eventRepo.forUser(chain, address, limit);
  if (indexed.length > 0) {
    const state = indexerRepo.get(chain);
    return {
      userAddress,
      chain,
      chainId: config.chainId,
      events: indexed.map(toActivityEvent),
      fromBlock: state?.startBlock ?? 0,
      toBlock: state?.lastBlock ?? 0,
    };
  }

  return getUserActivityFromChain(userAddress, chain, limit, fromBlock);
}

/** Maps a stored row onto the wire shape the frontend already consumes. */
function toActivityEvent(row: EventRow): ActivityEvent {
  const mapping = EVENT_KINDS[row.eventName];
  return {
    kind: row.kind as ActivityKind,
    label: mapping?.label ?? row.eventName,
    eventName: row.eventName,
    txHash: row.txHash,
    blockNumber: row.blockNumber,
    logIndex: row.logIndex,
    timestamp: row.timestamp,
    timestampISO: new Date(row.timestamp * 1000).toISOString(),
    tokenAddress: row.tokenAddress,
    tokenSymbol: row.tokenSymbol,
    tokenDecimals: row.tokenDecimals,
    amount: row.amount,
    extra: row.args,
  };
}
