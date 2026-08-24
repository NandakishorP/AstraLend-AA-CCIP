import { CHAIN_CONFIGS, env, type ChainKey } from "../config/env.js";
import { getProvider } from "../blockchain/providers.js";
import { getMarketOverview } from "../services/market.service.js";
import { snapshotRepo, type MarketSnapshot } from "../db/repositories.js";
import { PRECISION } from "../config/constants.js";

/**
 * Time-series writer.
 *
 * Chain state only ever answers "what is true now" — there is no way to ask a
 * contract what TVL was an hour ago. Every historical chart in the app is
 * therefore built from rows written here, on a timer, while the app runs.
 *
 * Rows are keyed by block number, so a chain that has not advanced overwrites
 * its previous row rather than accumulating duplicates at the same height. That
 * keeps an idle local node from filling the table with identical points.
 */

let timer: NodeJS.Timeout | null = null;
let running = false;

export function startSnapshotter(logger: { info: (msg: string) => void; warn: (msg: string) => void }): void {
  if (!env.INDEXER_ENABLED) return;

  const tick = async () => {
    if (running) return;
    running = true;
    try {
      await captureAll();
    } catch (error) {
      logger.warn(`snapshotter ${(error as Error).message}`);
    } finally {
      running = false;
    }
  };

  void tick();
  timer = setInterval(() => void tick(), env.SNAPSHOT_INTERVAL_MS);
  logger.info(`snapshotter started, every ${env.SNAPSHOT_INTERVAL_MS}ms`);
}

export function stopSnapshotter(): void {
  if (timer) clearInterval(timer);
  timer = null;
}

/** Captures every configured chain. Called on the timer and after demo actions. */
export async function captureAll(): Promise<void> {
  const chains = (Object.keys(CHAIN_CONFIGS) as ChainKey[]).filter(
    (chain) => CHAIN_CONFIGS[chain].lendingPool
  );
  await Promise.all(chains.map((chain) => capture(chain).catch(() => undefined)));
}

/**
 * Writes one protocol row and one row per market for `chain`.
 *
 * Timestamps come from the block header rather than the wall clock: the demo
 * fast-forwards chain time, and a chart mixing the two would show points
 * arriving out of order.
 */
export async function capture(chain: ChainKey): Promise<void> {
  const overview = await getMarketOverview(chain);
  const provider = getProvider(chain);

  const blockNumber = await provider.getBlockNumber();
  const block = await provider.getBlock(blockNumber).catch(() => null);
  const timestamp = block?.timestamp ?? Math.floor(Date.now() / 1000);

  const suppliedUsd = overview.markets.reduce(
    (total, market) => total + BigInt(market.totalLiquidityUsd),
    0n
  );

  snapshotRepo.insertProtocol({
    chain,
    blockNumber,
    timestamp,
    tvlUsd: overview.totalValueLockedUsd,
    borrowedUsd: overview.totalBorrowedUsd,
    collateralUsd: overview.totalCollateralUsd,
    suppliedUsd: suppliedUsd.toString(),
    lpTokenValueUsd: overview.lpTokenValueUsd,
    avgSupplyApr: overview.averageSupplyApr,
  });

  const marketRows: MarketSnapshot[] = overview.markets
    .filter((market) => market.registered)
    .map((market) => ({
      chain,
      tokenId: market.tokenId,
      symbol: market.symbol,
      blockNumber,
      timestamp,
      totalLiquidity: market.totalLiquidity,
      totalCollateral: market.totalCollateral,
      totalBorrowed: market.totalBorrowed,
      priceUsd: market.priceUsd,
      liquidityUsd: market.totalLiquidityUsd,
      collateralUsd: market.totalCollateralUsd,
      utilization: market.utilizationPercent,
      borrowApr: market.borrowApr,
      supplyApr: market.supplyApr,
    }));

  snapshotRepo.insertMarkets(marketRows);
}

/** Percentage change between the first and last point of a series. */
export function percentChange(first: string, last: string): number | null {
  const start = BigInt(first);
  if (start === 0n) return null;
  const end = BigInt(last);
  // Scale before dividing so sub-1% moves survive integer division.
  return Number(((end - start) * 10_000n) / start) / 100;
}

export { PRECISION };
