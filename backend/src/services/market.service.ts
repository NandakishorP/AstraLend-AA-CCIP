import { type ChainKey, CHAIN_CONFIGS } from "../config/env.js";
import {
  BASE_INTEREST_RATE,
  MAX_INTEREST_RATE,
  INTEREST_RATE_KINK,
  PRECISION,
  LTV,
  LIQUIDATION_THRESHOLD,
  LIQUIDATION_PENALTY,
  LOAN_DURATION_SECONDS,
} from "../config/constants.js";
import { getLendingPoolRead } from "../blockchain/contracts.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { getResolvedTokens, getStableCoinMeta, getLpTokenMeta } from "./token.service.js";
import { cached } from "../utils/cache.js";
import { ratioToPercent, safeRatio, aprToApy } from "../utils/format.js";

/** Market data changes with every block but polling every second is wasteful. */
const MARKET_TTL_MS = 10_000;

export interface Market {
  tokenId: number;
  symbol: string;
  name: string;
  decimals: number;
  address: string;
  /** False when the protocol has no price feed for this token ID. */
  registered: boolean;

  /** Supplied liquidity, token smallest unit */
  totalLiquidity: string;
  /** Collateral locked by borrowers, token smallest unit */
  totalCollateral: string;
  /** Outstanding borrows, stablecoin smallest unit */
  totalBorrowed: string;

  /** USD price of one whole token, 1e18-scaled */
  priceUsd: string;
  /** USD value of supplied liquidity, 1e18-scaled */
  totalLiquidityUsd: string;
  /** USD value of locked collateral, 1e18-scaled */
  totalCollateralUsd: string;

  /** Utilization as a percentage, e.g. 42.5 */
  utilizationPercent: number;
  /** Borrow APR as a percentage, from the on-chain kink model */
  borrowApr: number;
  /** Borrow APY (continuously compounded) as a percentage */
  borrowApy: number;
  /** Supply APR as a percentage — borrow APR scaled by utilization */
  supplyApr: number;

  /** Current borrower interest index, 1e18-scaled */
  borrowerIndex: string;
}

export interface MarketOverview {
  chain: ChainKey;
  chainId: number;
  chainName: string;
  markets: Market[];
  /** Protocol-wide TVL in USD, 1e18-scaled */
  totalValueLockedUsd: string;
  /** Protocol-wide borrows in USD, 1e18-scaled */
  totalBorrowedUsd: string;
  /** Protocol-wide collateral in USD, 1e18-scaled */
  totalCollateralUsd: string;
  /** USD value of one LP token, 1e18-scaled. "0" before the first deposit. */
  lpTokenValueUsd: string;
  /** Liquidity-weighted average supply APR across markets, percent */
  averageSupplyApr: number;
  parameters: ProtocolParameters;
  snapshotAt: string;
}

export interface ProtocolParameters {
  ltvPercent: number;
  liquidationThresholdPercent: number;
  liquidationPenaltyPercent: number;
  loanDurationDays: number;
  baseInterestRatePercent: number;
  maxInterestRatePercent: number;
  kinkPercent: number;
  stableCoin: { address: string; symbol: string; decimals: number };
  lpToken: { address: string; symbol: string; decimals: number };
}

/**
 * Reproduces InterestRateModel._calculateUtilizationRatio.
 *
 * The on-chain model measures utilization as collateral against the sum of
 * liquidity and collateral, not borrows against liquidity. This service mirrors
 * that formula exactly so the rate shown in the UI matches the rate the borrower
 * index actually accrues at.
 */
function utilizationRatio(liquidity: bigint, collateral: bigint): bigint {
  const denominator = liquidity + collateral;
  if (denominator === 0n) return 0n;
  return (collateral * PRECISION) / denominator;
}

/** Reproduces InterestRateModel._calculateInterestRate — the kinked rate curve. */
function interestRate(utilization: bigint): bigint {
  if (utilization < INTEREST_RATE_KINK) {
    return (
      BASE_INTEREST_RATE +
      ((MAX_INTEREST_RATE - BASE_INTEREST_RATE) * utilization) / INTEREST_RATE_KINK
    );
  }
  return (
    MAX_INTEREST_RATE +
    (MAX_INTEREST_RATE * (utilization - INTEREST_RATE_KINK)) / (PRECISION - INTEREST_RATE_KINK)
  );
}

/**
 * Builds the full market overview for a chain: per-token liquidity, collateral,
 * borrows, prices, utilization and rates, plus protocol-wide aggregates.
 *
 * This is the single read the markets page and the landing page stats bar use.
 * Results are cached briefly so a dashboard polling loop does not exhaust the
 * provider's rate limit.
 */
export async function getMarketOverview(chain: ChainKey): Promise<MarketOverview> {
  return cached(`markets:${chain}`, MARKET_TTL_MS, async () => {
    try {
      const config = CHAIN_CONFIGS[chain];
      const pool = getLendingPoolRead(chain);

      const [tokens, stableCoin, lpToken] = await Promise.all([
        getResolvedTokens(chain),
        getStableCoinMeta(chain),
        getLpTokenMeta(chain),
      ]);

      const markets = await Promise.all(
        tokens.map(async (token): Promise<Market> => {
          if (!token.registered) {
            return emptyMarket(token);
          }

          const oneToken = 10n ** BigInt(token.decimals);
          const [liquidity, collateral, borrowed, priceUsd, borrowerIndex] = await Promise.all([
            pool.getTotalLiquidityPerToken(token.tokenId) as Promise<bigint>,
            pool.getCollateralPerToken(token.tokenId) as Promise<bigint>,
            pool.getTotalBorroweedForAToken(token.tokenId) as Promise<bigint>,
            pool.getUsdValue(token.tokenId, oneToken) as Promise<bigint>,
            // getBorrowerIndex is nonpayable (it accrues before returning) — read it
            // via staticCall so this stays a free query.
            (pool.getBorrowerIndex.staticCall(token.tokenId) as Promise<bigint>).catch(() => 0n),
          ]);

          const utilization = utilizationRatio(liquidity, collateral);
          const apr = interestRate(utilization);
          const aprPercent = ratioToPercent(apr);

          return {
            tokenId: token.tokenId,
            symbol: token.symbol,
            name: token.name,
            decimals: token.decimals,
            address: token.address,
            registered: true,
            totalLiquidity: liquidity.toString(),
            totalCollateral: collateral.toString(),
            totalBorrowed: borrowed.toString(),
            priceUsd: priceUsd.toString(),
            totalLiquidityUsd: ((liquidity * priceUsd) / oneToken).toString(),
            totalCollateralUsd: ((collateral * priceUsd) / oneToken).toString(),
            utilizationPercent: ratioToPercent(utilization),
            borrowApr: aprPercent,
            borrowApy: aprToApy(apr),
            supplyApr: (aprPercent * ratioToPercent(utilization)) / 100,
            borrowerIndex: borrowerIndex.toString(),
          };
        })
      );

      // ── Aggregates ────────────────────────────────────────────────────────
      const totalLiquidityUsd = markets.reduce((sum, m) => sum + BigInt(m.totalLiquidityUsd), 0n);
      const totalCollateralUsd = markets.reduce((sum, m) => sum + BigInt(m.totalCollateralUsd), 0n);

      // Borrows are denominated in the stablecoin — scale to 1e18 USD.
      const stableScale = 10n ** BigInt(stableCoin.decimals);
      const totalBorrowedUsd = markets.reduce(
        (sum, m) => sum + (BigInt(m.totalBorrowed) * PRECISION) / stableScale,
        0n
      );

      // getValueOfLpToken divides by LP supply; it returns 0 before any deposit,
      // but a stale deployment can still revert — degrade to 0 rather than 500.
      const lpTokenValueUsd = await (pool.getValueOfLpToken() as Promise<bigint>).catch(() => 0n);

      const weightedSupplyApr =
        totalLiquidityUsd === 0n
          ? 0
          : markets.reduce((sum, m) => {
              const weight = Number((BigInt(m.totalLiquidityUsd) * 10_000n) / totalLiquidityUsd) / 10_000;
              return sum + m.supplyApr * weight;
            }, 0);

      return {
        chain,
        chainId: config.chainId,
        chainName: config.name,
        markets,
        totalValueLockedUsd: (totalLiquidityUsd + totalCollateralUsd).toString(),
        totalBorrowedUsd: totalBorrowedUsd.toString(),
        totalCollateralUsd: totalCollateralUsd.toString(),
        lpTokenValueUsd: lpTokenValueUsd.toString(),
        averageSupplyApr: weightedSupplyApr,
        parameters: {
          ltvPercent: ratioToPercent(LTV),
          liquidationThresholdPercent: ratioToPercent(LIQUIDATION_THRESHOLD),
          liquidationPenaltyPercent: ratioToPercent(LIQUIDATION_PENALTY),
          loanDurationDays: LOAN_DURATION_SECONDS / 86400,
          baseInterestRatePercent: ratioToPercent(BASE_INTEREST_RATE),
          maxInterestRatePercent: ratioToPercent(MAX_INTEREST_RATE),
          kinkPercent: ratioToPercent(INTEREST_RATE_KINK),
          stableCoin,
          lpToken,
        },
        snapshotAt: new Date().toISOString(),
      };
    } catch (err) {
      wrapBlockchainError(err);
    }
  });
}

/** A market for a token ID the protocol has not registered a price feed for. */
function emptyMarket(token: { tokenId: number; symbol: string; name: string; decimals: number; address: string }): Market {
  return {
    ...token,
    registered: false,
    totalLiquidity: "0",
    totalCollateral: "0",
    totalBorrowed: "0",
    priceUsd: "0",
    totalLiquidityUsd: "0",
    totalCollateralUsd: "0",
    utilizationPercent: 0,
    borrowApr: 0,
    borrowApy: 0,
    supplyApr: 0,
    borrowerIndex: "0",
  };
}

/** Convenience accessor used by the risk and portfolio services. */
export async function getMarket(tokenId: number, chain: ChainKey): Promise<Market | undefined> {
  const overview = await getMarketOverview(chain);
  return overview.markets.find((m) => m.tokenId === tokenId);
}

export { safeRatio };
