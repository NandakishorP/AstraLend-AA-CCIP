import { type ChainKey, CHAIN_CONFIGS } from "../config/env.js";
import { LTV, LIQUIDATION_THRESHOLD, PRECISION } from "../config/constants.js";
import { getLendingPoolRead, getERC20Read } from "../blockchain/contracts.js";
import { getProvider } from "../blockchain/providers.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { type LoanDetails, parseLoanDetailsRaw } from "./protocol.service.js";
import { getMarketOverview, type Market } from "./market.service.js";
import { getStableCoinMeta, getLpTokenMeta } from "./token.service.js";
import { ratioToPercent } from "../utils/format.js";

export interface TokenPosition {
  tokenId: number;
  symbol: string;
  decimals: number;
  tokenAddress: string;
  /** Liquidity deposited (earns LP tokens), token smallest unit */
  liquidityDeposited: string;
  /** Collateral deposited (backs loans), token smallest unit */
  collateralDeposited: string;
  /**
   * Collateral split by the chain id it was deposited on.
   *
   * `borrowLoan` takes the chain id whose collateral backs the loan and reverts
   * if that chain holds none — so a borrower whose collateral sits on a
   * satellite must pass the satellite's id, not the chain they are calling from.
   */
  collateralByChain: Record<string, string>;
  /** Wallet balance of this token, token smallest unit */
  walletBalance: string;
  /** USD price of one whole token, 1e18-scaled */
  priceUsd: string;
  /** USD value of the supplied liquidity, 1e18-scaled */
  liquidityUsd: string;
  /** USD value of the deposited collateral, 1e18-scaled */
  collateralUsd: string;
  /** USD value of the wallet balance, 1e18-scaled */
  walletUsd: string;
  /** Current supply APR for this market, percent */
  supplyApr: number;
  /** Current borrow APR for this market, percent */
  borrowApr: number;
}

export interface UserLoan extends LoanDetails {
  tokenSymbol: string;
  tokenId: number;
  /** Principal plus accrued interest right now, stablecoin smallest unit */
  currentDebt: string;
  /** Interest accrued since the loan was opened, stablecoin smallest unit */
  accruedInterest: string;
  /** USD value of the current debt, 1e18-scaled */
  currentDebtUsd: string;
  /** USD value of the collateral locked against this loan, 1e18-scaled */
  collateralUsedUsd: string;
  /** collateralValue × liquidationThreshold ÷ debt. Below 1.0 is liquidatable. */
  healthFactor: number | null;
  /** debt ÷ collateralValue, percent */
  ltvPercent: number;
  /** Whole days until the due date; negative once overdue */
  daysUntilDue: number;
}

export interface AccountSummary {
  /** Total USD value of supplied liquidity, 1e18-scaled */
  suppliedUsd: string;
  /** Total USD value of deposited collateral, 1e18-scaled */
  collateralUsd: string;
  /** Total current debt in USD, 1e18-scaled */
  debtUsd: string;
  /** collateralUsd × LTV — the maximum debt the account may carry, 1e18-scaled */
  borrowPowerUsd: string;
  /** borrowPower − debt, floored at zero, 1e18-scaled */
  availableToBorrowUsd: string;
  /** supplied + collateral − debt, 1e18-scaled (may be negative) */
  netWorthUsd: string;
  /** Account-wide health factor. null when the account has no debt. */
  healthFactor: number | null;
  /** debt ÷ collateralValue, percent */
  currentLtvPercent: number;
  /** Risk bucket derived from the health factor, for UI colour coding */
  riskLevel: "none" | "safe" | "moderate" | "high" | "liquidation";
}

export interface UserPortfolio {
  userAddress: string;
  chain: ChainKey;
  chainId: number;
  /** LP token balance, in LP token smallest unit */
  lpTokenBalance: string;
  /** USD value of the LP position, 1e18-scaled */
  lpTokenValueUsd: string;
  positions: TokenPosition[];
  activeLoans: UserLoan[];
  /** Loans already settled — kept for history views */
  closedLoans: UserLoan[];
  /** Stablecoin wallet balance, stablecoin smallest unit */
  stableCoinBalance: string;
  stableCoinSymbol: string;
  stableCoinDecimals: number;
  /** Native gas token balance in wei — used to warn before CCIP-fee transactions */
  nativeBalance: string;
  summary: AccountSummary;
  snapshotAt: string;
}

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/**
 * Every chain the protocol spans.
 *
 * Positions are keyed by the chain they originated on, so a complete picture of
 * a user requires reading each key — the hub holds satellite-originated
 * balances under the satellite's id, not its own.
 */
const ALL_CHAIN_IDS: number[] = (Object.keys(CHAIN_CONFIGS) as ChainKey[]).map(
  (key) => CHAIN_CONFIGS[key].chainId
);

/**
 * Aggregates the complete on-chain state for a user into a single response.
 *
 * This is the primary endpoint the frontend dashboard uses — it replaces a dozen
 * individual calls, and layers on the derived numbers the UI needs (USD values,
 * accrued interest, health factors, borrowing power) so the same risk math is
 * not reimplemented client-side.
 *
 * @param userAddress - Wallet address to query
 * @param chain       - Which chain to read from
 */
export async function getUserPortfolio(
  userAddress: string,
  chain: ChainKey
): Promise<UserPortfolio> {
  try {
    const config = CHAIN_CONFIGS[chain];
    const pool = getLendingPoolRead(chain);
    const chainId = config.chainId;

    const [overview, stableCoin, lpToken] = await Promise.all([
      getMarketOverview(chain),
      getStableCoinMeta(chain),
      getLpTokenMeta(chain),
    ]);

    const stableScale = 10n ** BigInt(stableCoin.decimals);

    // ── Per-token positions ─────────────────────────────────────────────────
    const positions = await Promise.all(
      overview.markets.map(async (market): Promise<TokenPosition> => {
        const oneToken = 10n ** BigInt(market.decimals);
        const price = BigInt(market.priceUsd);

        // Balances are keyed by the chain the funds were deposited on, so a
        // position opened on a satellite and mirrored here lives under *that*
        // chain's id. Reading only the local id hides every cross-chain
        // position — which is the whole point of the protocol.
        const perChain = await Promise.all(
          ALL_CHAIN_IDS.map(async (originChainId) => {
            const [liquidity, collateral] = await Promise.all([
              (pool.getUserBalance(originChainId, userAddress, market.tokenId) as Promise<bigint>).catch(
                () => 0n
              ),
              (
                pool.getCollateralDetailsOfUser(
                  originChainId,
                  userAddress,
                  market.tokenId
                ) as Promise<bigint>
              ).catch(() => 0n),
            ]);
            return { originChainId, liquidity, collateral };
          })
        );

        const liquidityDeposited = perChain.reduce((sum, entry) => sum + entry.liquidity, 0n);
        const collateralDeposited = perChain.reduce((sum, entry) => sum + entry.collateral, 0n);
        const walletBalance =
          market.address !== ZERO_ADDRESS
            ? await (getERC20Read(market.address, chain).balanceOf(userAddress) as Promise<bigint>)
            : 0n;

        return {
          tokenId: market.tokenId,
          symbol: market.symbol,
          decimals: market.decimals,
          tokenAddress: market.address,
          liquidityDeposited: liquidityDeposited.toString(),
          collateralDeposited: collateralDeposited.toString(),
          collateralByChain: Object.fromEntries(
            perChain
              .filter((entry) => entry.collateral > 0n)
              .map((entry) => [String(entry.originChainId), entry.collateral.toString()])
          ),
          walletBalance: walletBalance.toString(),
          priceUsd: market.priceUsd,
          liquidityUsd: ((liquidityDeposited * price) / oneToken).toString(),
          collateralUsd: ((collateralDeposited * price) / oneToken).toString(),
          walletUsd: ((walletBalance * price) / oneToken).toString(),
          supplyApr: market.supplyApr,
          borrowApr: market.borrowApr,
        };
      })
    );

    // ── Loans ───────────────────────────────────────────────────────────────
    const activeLoans: UserLoan[] = [];
    const closedLoans: UserLoan[] = [];

    await Promise.all(
      overview.markets.flatMap((market) =>
        // Loans are keyed by the chain they were taken on, which may be either
        // chain regardless of where the collateral sits.
        ALL_CHAIN_IDS.map(async (loanChainId) => {
          const loanCount: bigint = await (
            pool.getUserLoanCount(loanChainId, userAddress, market.tokenId) as Promise<bigint>
          ).catch(() => 0n);

          // Loan ids are 1-based: LoanController assigns `loan.loanId = ++loanId`,
          // so a user with N loans holds them at 1..N and slot 0 is always empty.
          const loans = await Promise.all(
            Array.from({ length: Number(loanCount) }, (_, index) =>
              pool
                .getLoanDetails(loanChainId, userAddress, market.tokenId, index + 1)
                .then(parseLoanDetailsRaw)
                // A loan slot can be unreadable while a CCIP mirror update is
                // still in flight — skip it rather than failing the portfolio.
                .catch(() => null)
            )
          );

          for (const details of loans) {
            if (!details) continue;
            // Guard against a gap in the sequence (a deleted or not-yet-mirrored
            // slot) rendering as a phantom zero-value loan.
            if (details.token === ZERO_ADDRESS) continue;
            const loan = enrichLoan(details, market, stableScale);
            if (details.isClosed) closedLoans.push(loan);
            else activeLoans.push(loan);
          }
        })
      )
    );

    activeLoans.sort((a, b) => Number(a.dueDate) - Number(b.dueDate));
    closedLoans.sort((a, b) => Number(b.dueDate) - Number(a.dueDate));

    // ── Balances ────────────────────────────────────────────────────────────
    const [lpTokenBalance, stableCoinBalance, nativeBalance] = await Promise.all([
      pool.getTotalLPTokensForTheUser(userAddress) as Promise<bigint>,
      stableCoin.address !== ZERO_ADDRESS
        ? (getERC20Read(stableCoin.address, chain).balanceOf(userAddress) as Promise<bigint>)
        : Promise.resolve(0n),
      getProvider(chain).getBalance(userAddress),
    ]);

    const lpTokenValueUsd =
      (lpTokenBalance * BigInt(overview.lpTokenValueUsd)) / 10n ** BigInt(lpToken.decimals);

    return {
      userAddress,
      chain,
      chainId,
      lpTokenBalance: lpTokenBalance.toString(),
      lpTokenValueUsd: lpTokenValueUsd.toString(),
      positions,
      activeLoans,
      closedLoans,
      stableCoinBalance: stableCoinBalance.toString(),
      stableCoinSymbol: stableCoin.symbol,
      stableCoinDecimals: stableCoin.decimals,
      nativeBalance: nativeBalance.toString(),
      summary: buildSummary(positions, activeLoans),
      snapshotAt: new Date().toISOString(),
    };
  } catch (err) {
    wrapBlockchainError(err);
  }
}

/**
 * Layers derived risk numbers onto a raw loan struct.
 *
 * Current debt is recomputed exactly the way `LendingPoolContract.getAmountToRepay`
 * does — principal scaled by the ratio of the live borrower index to the index
 * captured when the loan was opened — so no per-loan RPC round trip is needed.
 */
function enrichLoan(details: LoanDetails, market: Market, stableScale: bigint): UserLoan {
  const principal = BigInt(details.amountBorrowedInUSDT);
  const userIndex = BigInt(details.userBorrowIndex);
  const currentIndex = BigInt(market.borrowerIndex);

  const currentDebt =
    userIndex === 0n || currentIndex === 0n ? principal : (principal * currentIndex) / userIndex;
  const accruedInterest = currentDebt > principal ? currentDebt - principal : 0n;

  const oneToken = 10n ** BigInt(market.decimals);
  const collateralUsed = BigInt(details.collateralUsed);
  const collateralUsedUsd = (collateralUsed * BigInt(market.priceUsd)) / oneToken;
  const currentDebtUsd = (currentDebt * PRECISION) / stableScale;

  // A loan records the collateral it locked, but for a cross-chain loan that
  // figure is written by the mirroring path and can be dust or zero while the
  // real collateral sits under the originating chain's key. Reporting a health
  // factor from it would flag a well-collateralised position as liquidatable,
  // so per-loan risk is left unknown and the account summary — which sums the
  // user's actual collateral across chains — is the authoritative view.
  // One cent, 1e18-scaled. The mirrored figure is often dust rather than
  // exactly zero, and dividing debt by dust produces an LTV in the trillions.
  const COLLATERAL_DUST_USD = 10n ** 16n;
  const hasMeaningfulCollateral = collateralUsedUsd >= COLLATERAL_DUST_USD;

  const healthFactor =
    currentDebtUsd === 0n || details.isClosed || !hasMeaningfulCollateral
      ? null
      : Number((collateralUsedUsd * LIQUIDATION_THRESHOLD * 1000n) / PRECISION / currentDebtUsd) / 1000;

  const ltvPercent = hasMeaningfulCollateral
    ? ratioToPercent((currentDebtUsd * PRECISION) / collateralUsedUsd)
    : 0;

  const dueMs = Number(details.dueDate) * 1000;

  return {
    ...details,
    tokenId: market.tokenId,
    tokenSymbol: market.symbol,
    currentDebt: currentDebt.toString(),
    accruedInterest: accruedInterest.toString(),
    currentDebtUsd: currentDebtUsd.toString(),
    collateralUsedUsd: collateralUsedUsd.toString(),
    healthFactor,
    ltvPercent,
    daysUntilDue: Math.floor((dueMs - Date.now()) / 86_400_000),
  };
}

/** Rolls per-position and per-loan numbers into the account-level risk summary. */
function buildSummary(positions: TokenPosition[], activeLoans: UserLoan[]): AccountSummary {
  const suppliedUsd = positions.reduce((sum, p) => sum + BigInt(p.liquidityUsd), 0n);
  const collateralUsd = positions.reduce((sum, p) => sum + BigInt(p.collateralUsd), 0n);
  const debtUsd = activeLoans.reduce((sum, l) => sum + BigInt(l.currentDebtUsd), 0n);

  const borrowPowerUsd = (collateralUsd * LTV) / PRECISION;
  const availableToBorrowUsd = borrowPowerUsd > debtUsd ? borrowPowerUsd - debtUsd : 0n;
  const liquidationValueUsd = (collateralUsd * LIQUIDATION_THRESHOLD) / PRECISION;

  const healthFactor =
    debtUsd === 0n ? null : Number((liquidationValueUsd * 1000n) / debtUsd) / 1000;

  const currentLtvPercent =
    collateralUsd === 0n ? 0 : ratioToPercent((debtUsd * PRECISION) / collateralUsd);

  return {
    suppliedUsd: suppliedUsd.toString(),
    collateralUsd: collateralUsd.toString(),
    debtUsd: debtUsd.toString(),
    borrowPowerUsd: borrowPowerUsd.toString(),
    availableToBorrowUsd: availableToBorrowUsd.toString(),
    netWorthUsd: (suppliedUsd + collateralUsd - debtUsd).toString(),
    healthFactor,
    currentLtvPercent,
    riskLevel: riskLevelFor(healthFactor),
  };
}

function riskLevelFor(healthFactor: number | null): AccountSummary["riskLevel"] {
  if (healthFactor === null) return "none";
  if (healthFactor < 1) return "liquidation";
  if (healthFactor < 1.2) return "high";
  if (healthFactor < 1.6) return "moderate";
  return "safe";
}
