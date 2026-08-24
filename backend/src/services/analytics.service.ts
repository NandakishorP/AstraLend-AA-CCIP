import { type ChainKey } from "../config/env.js";
import {
  ccipRepo,
  eventRepo,
  participantRepo,
  snapshotRepo,
  type CcipMessageRow,
} from "../db/repositories.js";
import { percentChange } from "../indexer/snapshotter.js";

/**
 * Analytics served from the indexed database.
 *
 * Everything here is a question the chain cannot answer: how a value moved over
 * time, how many distinct addresses have ever interacted, how long cross-chain
 * delivery takes. Live state still comes from the chain — these are the reads
 * that only exist because something was recording.
 */

export type Range = "1h" | "6h" | "24h" | "7d" | "30d" | "all";

const RANGE_SECONDS: Record<Range, number> = {
  "1h": 3600,
  "6h": 6 * 3600,
  "24h": 24 * 3600,
  "7d": 7 * 86_400,
  "30d": 30 * 86_400,
  all: Number.MAX_SAFE_INTEGER,
};

/** Caps points per series so a long range stays renderable. */
const MAX_POINTS = 500;

function sinceFor(range: Range): number {
  if (range === "all") return 0;
  return Math.floor(Date.now() / 1000) - RANGE_SECONDS[range];
}

export interface SeriesPoint {
  timestamp: number;
  blockNumber: number;
  values: Record<string, string | number>;
}

export interface ProtocolHistory {
  chain: ChainKey;
  range: Range;
  points: SeriesPoint[];
  change: {
    tvlPercent: number | null;
    borrowedPercent: number | null;
    collateralPercent: number | null;
  };
  latest: SeriesPoint | null;
}

/** TVL, borrows and collateral over time, plus the change across the window. */
export function getProtocolHistory(chain: ChainKey, range: Range): ProtocolHistory {
  const rows = snapshotRepo.protocolHistory(chain, sinceFor(range), MAX_POINTS);

  const points: SeriesPoint[] = rows.map((row) => ({
    timestamp: row.timestamp,
    blockNumber: row.blockNumber,
    values: {
      tvlUsd: row.tvlUsd,
      borrowedUsd: row.borrowedUsd,
      collateralUsd: row.collateralUsd,
      suppliedUsd: row.suppliedUsd,
      lpTokenValueUsd: row.lpTokenValueUsd,
      avgSupplyApr: row.avgSupplyApr,
    },
  }));

  const first = rows[0];
  const last = rows[rows.length - 1];

  return {
    chain,
    range,
    points,
    change: {
      tvlPercent: first && last ? percentChange(first.tvlUsd, last.tvlUsd) : null,
      borrowedPercent: first && last ? percentChange(first.borrowedUsd, last.borrowedUsd) : null,
      collateralPercent:
        first && last ? percentChange(first.collateralUsd, last.collateralUsd) : null,
    },
    latest: points[points.length - 1] ?? null,
  };
}

export interface MarketHistory {
  chain: ChainKey;
  tokenId: number;
  symbol: string | null;
  range: Range;
  points: SeriesPoint[];
}

/** Utilization, rates, liquidity and price for one market over time. */
export function getMarketHistory(chain: ChainKey, tokenId: number, range: Range): MarketHistory {
  const rows = snapshotRepo.marketHistory(chain, tokenId, sinceFor(range), MAX_POINTS);

  return {
    chain,
    tokenId,
    symbol: rows[0]?.symbol ?? null,
    range,
    points: rows.map((row) => ({
      timestamp: row.timestamp,
      blockNumber: row.blockNumber,
      values: {
        utilization: row.utilization,
        borrowApr: row.borrowApr,
        supplyApr: row.supplyApr,
        priceUsd: row.priceUsd,
        liquidityUsd: row.liquidityUsd,
        collateralUsd: row.collateralUsd,
        totalBorrowed: row.totalBorrowed,
      },
    })),
  };
}

export interface ProtocolStats {
  chain: ChainKey;
  uniqueParticipants: number;
  totalEvents: number;
  /**
   * Outstanding debt derived from indexed borrow/repay events across every
   * chain, in stablecoin smallest units. The chain cannot report this — the
   * protocol's own aggregate counter is never incremented on borrow.
   */
  outstandingDebt: string;
  totalBorrowedEver: string;
  totalRepaid: string;
  eventsByKind: { kind: string; count: number }[];
  crossChain: ReturnType<typeof ccipRepo.stats>;
  topParticipants: { address: string; eventCount: number; lastSeen: number }[];
}

/** Aggregate protocol usage — only answerable with a full event history. */
export function getProtocolStats(chain: ChainKey): ProtocolStats {
  const eventsByKind = eventRepo.countsByKind(chain);
  const { borrowed, repaid } = eventRepo.outstandingBorrowed();
  const outstanding = BigInt(borrowed) > BigInt(repaid) ? BigInt(borrowed) - BigInt(repaid) : 0n;

  return {
    chain,
    uniqueParticipants: participantRepo.count(chain),
    totalEvents: eventsByKind.reduce((total, row) => total + row.count, 0),
    outstandingDebt: outstanding.toString(),
    totalBorrowedEver: borrowed,
    totalRepaid: repaid,
    eventsByKind,
    crossChain: ccipRepo.stats(),
    topParticipants: participantRepo.top(chain, 5),
  };
}

export interface CrossChainFeed {
  messages: CcipMessageRow[];
  stats: ReturnType<typeof ccipRepo.stats>;
}

/**
 * Cross-chain message log.
 *
 * Persisted rather than held in the relayer's memory, so a message that was in
 * flight when something restarted is still visible — and still visibly pending.
 */
export function getCrossChainFeed(limit: number, userAddress?: string): CrossChainFeed {
  return {
    messages: userAddress ? ccipRepo.forUser(userAddress, limit) : ccipRepo.recent(limit),
    stats: ccipRepo.stats(),
  };
}
