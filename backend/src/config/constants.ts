// Protocol constants — sourced directly from LendingPoolContract.sol

/** Loan-to-Value ratio: 75% (1e18 precision) */
export const LTV = 75n * 10n ** 16n;

/** Liquidation threshold: 80% (1e18 precision) */
export const LIQUIDATION_THRESHOLD = 80n * 10n ** 16n;

/** Liquidation penalty: 5% (1e18 precision) */
export const LIQUIDATION_PENALTY = 5n * 10n ** 16n;

/** Standard precision used across the protocol */
export const PRECISION = 10n ** 18n;

/** Stablecoin decimals (USDT-like) */
export const STABLE_DECIMALS = 6;

/** LP token decimals */
export const LP_TOKEN_DECIMALS = 18;

/** Chainlink price feed additional precision multiplier */
export const PRICEFEED_PRECISION = 10n ** 10n;

// ─── Interest rate model ──────────────────────────────────────────────────────
// Mirrors InterestRateModel.sol. The model contract is not reachable from the
// LendingPool ABI, so the curve is reproduced here to render rates in the UI.
// Keep these in sync with src/InterestRate/InterestRateModel.sol.

/** Base borrow rate at 0% utilization: 5% APR (1e18 precision) */
export const BASE_INTEREST_RATE = 5n * 10n ** 16n;

/** Borrow rate ceiling before the kink slope takes over: 100% APR (1e18) */
export const MAX_INTEREST_RATE = 100n * 10n ** 16n;

/** Utilization point where the steep slope begins: 70% (1e18) */
export const INTEREST_RATE_KINK = 70n * 10n ** 16n;

/** Loan duration in seconds (180 days) */
export const LOAN_DURATION_SECONDS = 180 * 24 * 60 * 60;

/** Ethereum Sepolia chain ID */
export const ETH_CHAIN_ID = 11155111;

/** Arbitrum Sepolia chain ID */
export const ARB_CHAIN_ID = 421614;

/** Gas buffer percentage added on top of estimated gas (20%) */
export const GAS_BUFFER_PERCENT = 20n;

/** Maximum retry attempts for retriable blockchain errors */
export const MAX_TX_RETRIES = 3;

/** Base delay in ms for exponential backoff */
export const RETRY_BASE_DELAY_MS = 1000;

/** How long to wait for a transaction receipt before giving up (2 minutes) */
export const TX_TIMEOUT_MS = 120_000;
