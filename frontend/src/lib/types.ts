/**
 * Response shapes returned by the AstraLend backend.
 *
 * Every on-chain quantity crosses the wire as a decimal string — wei values
 * routinely exceed JavaScript's safe integer range. Percentages and health
 * factors are the exception: they are bounded, so the backend sends numbers.
 */

export type ChainKey = "eth" | "arb";

export interface ApiEnvelope<T> {
  success: true;
  data: T;
  message?: string;
}

export interface ApiErrorBody {
  success: false;
  error: string;
  message: string;
  requestId?: string;
  contractError?: string;
  contractErrorArgs?: Record<string, string>;
  details?: unknown;
}

// ─── Markets ──────────────────────────────────────────────────────────────────

export interface Market {
  tokenId: number;
  symbol: string;
  name: string;
  decimals: number;
  address: string;
  registered: boolean;
  totalLiquidity: string;
  totalCollateral: string;
  totalBorrowed: string;
  priceUsd: string;
  totalLiquidityUsd: string;
  totalCollateralUsd: string;
  utilizationPercent: number;
  borrowApr: number;
  borrowApy: number;
  supplyApr: number;
  borrowerIndex: string;
}

export interface TokenRef {
  address: string;
  symbol: string;
  decimals: number;
}

export interface ProtocolParameters {
  ltvPercent: number;
  liquidationThresholdPercent: number;
  liquidationPenaltyPercent: number;
  loanDurationDays: number;
  baseInterestRatePercent: number;
  maxInterestRatePercent: number;
  kinkPercent: number;
  stableCoin: TokenRef;
  lpToken: TokenRef;
}

export interface MarketOverview {
  chain: ChainKey;
  chainId: number;
  chainName: string;
  markets: Market[];
  totalValueLockedUsd: string;
  totalBorrowedUsd: string;
  totalCollateralUsd: string;
  lpTokenValueUsd: string;
  averageSupplyApr: number;
  parameters: ProtocolParameters;
  snapshotAt: string;
}

// ─── Portfolio ────────────────────────────────────────────────────────────────

export interface TokenPosition {
  tokenId: number;
  symbol: string;
  decimals: number;
  tokenAddress: string;
  liquidityDeposited: string;
  collateralDeposited: string;
  /** Collateral split by the chain id it was deposited on. */
  collateralByChain: Record<string, string>;
  walletBalance: string;
  priceUsd: string;
  liquidityUsd: string;
  collateralUsd: string;
  walletUsd: string;
  supplyApr: number;
  borrowApr: number;
}

export interface UserLoan {
  tokenId: number;
  tokenSymbol: string;
  loanId: string;
  token: string;
  asset: string;
  amountBorrowedInUSDT: string;
  principalAmount: string;
  collateralUsed: string;
  collateralChainId: string;
  loanChainId: string;
  interestPaid: string;
  liquidationPoint: string;
  userBorrowIndex: string;
  lastUpdate: string;
  dueDate: string;
  dueDateISO: string;
  isOverdue: boolean;
  isClosed: boolean;
  isLiquidated: boolean;
  penaltyCount: number;
  currentDebt: string;
  accruedInterest: string;
  currentDebtUsd: string;
  collateralUsedUsd: string;
  healthFactor: number | null;
  ltvPercent: number;
  daysUntilDue: number;
}

export type RiskLevel = "none" | "safe" | "moderate" | "high" | "liquidation";

export interface AccountSummary {
  suppliedUsd: string;
  collateralUsd: string;
  debtUsd: string;
  borrowPowerUsd: string;
  availableToBorrowUsd: string;
  netWorthUsd: string;
  healthFactor: number | null;
  currentLtvPercent: number;
  riskLevel: RiskLevel;
}

export interface UserPortfolio {
  userAddress: string;
  chain: ChainKey;
  chainId: number;
  lpTokenBalance: string;
  lpTokenValueUsd: string;
  positions: TokenPosition[];
  activeLoans: UserLoan[];
  closedLoans: UserLoan[];
  stableCoinBalance: string;
  stableCoinSymbol: string;
  stableCoinDecimals: number;
  nativeBalance: string;
  summary: AccountSummary;
  snapshotAt: string;
}

// ─── Activity ─────────────────────────────────────────────────────────────────

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
  | "ccip-in"
  | "liquidation"
  | "lien-created"
  | "lien-released"
  | "lien-foreclosed"
  | "eligibility";

export interface ActivityEvent {
  kind: ActivityKind;
  label: string;
  eventName: string;
  txHash: string;
  blockNumber: number;
  logIndex: number;
  timestamp: number | null;
  timestampISO: string | null;
  tokenAddress: string | null;
  tokenSymbol: string | null;
  tokenDecimals: number | null;
  amount: string | null;
  extra: Record<string, string>;
}

export interface ActivityFeed {
  userAddress: string;
  chain: ChainKey;
  chainId: number;
  events: ActivityEvent[];
  fromBlock: number;
  toBlock: number;
}

// ─── Fees + transactions ──────────────────────────────────────────────────────

export type FeeOperation =
  | "depositLiquidity"
  | "withdrawLiquidity"
  | "depositCollateral"
  | "withdrawCollateral"
  | "borrowLoan"
  | "repayLoan";

export interface FeeEstimate {
  operation: FeeOperation;
  chain: ChainKey;
  ccipFeeWei: string;
  ccipFeeFormatted: string;
  requiresCcip: boolean;
  recommendedValueWei: string;
}

export interface UnsignedTx {
  to: string;
  data: string;
  value: string;
  gasLimit: string;
  chainId: number;
  description: string;
  type: string;
}

export interface BuildResult {
  transactions: UnsignedTx[];
  chainId: number;
  summary: string;
}

// ─── Faucet ───────────────────────────────────────────────────────────────────

export interface FaucetAsset {
  target: string;
  symbol: string;
  address: string;
  mintable: boolean;
}

export interface FaucetStatus {
  available: boolean;
  signer: string;
  assets: FaucetAsset[];
}

// ─── Health ───────────────────────────────────────────────────────────────────

export interface ChainHealth {
  status: "ok" | "error";
  chainId?: number;
  blockNumber?: number;
  latencyMs?: number;
  lendingPool?: string;
  contractReachable?: boolean;
  message?: string;
}

export interface ReadinessReport {
  status: "ready" | "degraded";
  chains: Record<string, ChainHealth>;
  timestamp: string;
}

// ─── Demo environment ─────────────────────────────────────────────────────────

export interface RelayerMessage {
  messageId: string;
  from: string;
  to: string;
  status: "pending" | "delivered" | "reverted" | "failed" | "undeliverable";
  sentAt: string;
  deliveredAt: string | null;
  sourceTxHash: string;
  destinationTxHash: string | null;
  error: string | null;
}

export interface DemoChainStatus {
  chain: ChainKey;
  name: string;
  chainId: number;
  role: "hub" | "satellite";
  blockNumber: number;
  timestamp: number;
  timestampISO: string;
  /** Seconds this chain's clock runs ahead of real time. */
  skewSeconds: number;
  reachable: boolean;
}

export interface DemoStatus {
  available: boolean;
  deployedAt: string | null;
  chains: DemoChainStatus[];
  relayer: { reachable: boolean; pending: number; delivered: number };
  messages: RelayerMessage[];
}

export interface KeeperCandidate {
  chainId: number;
  borrower: string;
  tokenId: number;
  loanId: number;
  dueDate: number;
  overdueDays: number;
  penaltyCount: number;
  outstanding: string;
}

export interface KeeperRunResult {
  scanned: number;
  acted: { candidate: KeeperCandidate; txHash: string; outcome: string }[];
  message: string;
}

// ─── Analytics (indexed history) ──────────────────────────────────────────────

export type Range = "1h" | "6h" | "24h" | "7d" | "30d" | "all";

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

export interface MarketHistory {
  chain: ChainKey;
  tokenId: number;
  symbol: string | null;
  range: Range;
  points: SeriesPoint[];
}

export interface CrossChainStats {
  total: number;
  delivered: number;
  pending: number;
  failed: number;
  avgLatencyMs: number;
}

export interface ProtocolStats {
  chain: ChainKey;
  uniqueParticipants: number;
  totalEvents: number;
  /** Derived from indexed events across all chains, in stablecoin units. */
  outstandingDebt: string;
  totalBorrowedEver: string;
  totalRepaid: string;
  eventsByKind: { kind: string; count: number }[];
  crossChain: CrossChainStats;
  topParticipants: { address: string; eventCount: number; lastSeen: number }[];
}

export interface CcipMessage {
  messageId: string;
  sourceChain: ChainKey;
  destChain: ChainKey | null;
  sender: string;
  receiver: string;
  userAddress: string | null;
  action: string | null;
  feePaid: string | null;
  status: "pending" | "delivered" | "failed";
  sentTx: string;
  sentBlock: number;
  sentAt: number;
  deliveredTx: string | null;
  deliveredAt: number | null;
  error: string | null;
}

export interface CrossChainFeed {
  messages: CcipMessage[];
  stats: CrossChainStats;
}

export interface IndexerChainStatus {
  chain: ChainKey;
  enabled: boolean;
  lastBlock: number;
  headBlock: number | null;
  blocksBehind: number | null;
  eventsIndexed: number;
  reorgsHandled: number;
  lastRunAt: number | null;
  lastError: string | null;
}

// ─── Real-world asset collateral ──────────────────────────────────────────────

/**
 * A holder's position in an encumbered instrument.
 *
 * `balance` and `encumbered` are reported together on purpose. Pledging does not
 * move the tokens, so the balance alone says nothing about what is committed —
 * only the gap between balance and free does.
 */
export interface RwaHolding {
  userAddress: string;
  tokenAddress: string;
  symbol: string;
  decimals: number;
  balance: string;
  encumbered: string;
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
  /** How much of the discount has been earned, 0 to 1. */
  accretionProgress: number;
  daysToMaturity: number;
  /** Always false — the value is computed on read, never reported. */
  isStale: false;
}

export interface LienView {
  lienId: string;
  borrower: string;
  tokenAddress: string;
  amount: string;
  loanRef: string;
  perfectedAt: number;
  releasedAt: number | null;
  foreclosed: boolean;
  active: boolean;
}

export interface RwaStatus {
  available: boolean;
}
