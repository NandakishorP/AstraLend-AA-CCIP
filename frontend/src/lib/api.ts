import type {
  ActivityFeed,
  CrossChainFeed,
  IndexerChainStatus,
  MarketHistory,
  ProtocolHistory,
  ProtocolStats,
  Range,
  DemoStatus,
  KeeperCandidate,
  KeeperRunResult,
  ApiEnvelope,
  ApiErrorBody,
  BuildResult,
  ChainKey,
  FaucetStatus,
  FeeEstimate,
  FeeOperation,
  MarketOverview,
  ReadinessReport,
  UserPortfolio,
} from "./types";

export const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, "") ?? "http://localhost:3000";

/**
 * Error thrown for any non-2xx backend response.
 *
 * The backend decodes Solidity custom errors into readable sentences before they
 * reach us, so `message` is safe to show directly in the UI. `contractError`
 * carries the raw Solidity error name for the cases where the UI wants to react
 * programmatically (e.g. routing "not enough collateral" to the deposit flow).
 */
export class ApiError extends Error {
  readonly code: string;
  readonly status: number;
  readonly contractError?: string;
  readonly contractErrorArgs?: Record<string, string>;
  readonly requestId?: string;

  constructor(status: number, body: ApiErrorBody) {
    super(body.message || "Request failed");
    this.name = "ApiError";
    this.status = status;
    this.code = body.error;
    this.contractError = body.contractError;
    this.contractErrorArgs = body.contractErrorArgs;
    this.requestId = body.requestId;
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${API_BASE}${path}`, {
      ...init,
      headers: {
        "content-type": "application/json",
        ...init?.headers,
      },
      cache: "no-store",
    });
  } catch {
    // A network-level failure means the API is unreachable, not that the
    // request was rejected — say so plainly instead of surfacing "fetch failed".
    throw new ApiError(0, {
      success: false,
      error: "NETWORK_ERROR",
      message: `Cannot reach the AstraLend API at ${API_BASE}. Is the backend running?`,
    });
  }

  const text = await response.text();
  const body = text ? JSON.parse(text) : {};

  if (!response.ok || body.success === false) {
    throw new ApiError(response.status, body as ApiErrorBody);
  }

  return (body as ApiEnvelope<T>).data;
}

/**
 * Fetches an endpoint that returns its payload directly, with no envelope.
 *
 * A degraded readiness report comes back as HTTP 503 with a usable body — that
 * is the answer, not a failure, so the status code is not treated as an error.
 */
async function requestRaw<T>(path: string): Promise<T> {
  try {
    const response = await fetch(`${API_BASE}${path}`, { cache: "no-store" });
    return (await response.json()) as T;
  } catch {
    throw new ApiError(0, {
      success: false,
      error: "NETWORK_ERROR",
      message: `Cannot reach the AstraLend API at ${API_BASE}.`,
    });
  }
}

function query(params: Record<string, string | number | undefined>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== "") search.set(key, String(value));
  }
  const encoded = search.toString();
  return encoded ? `?${encoded}` : "";
}

// ─── Reads ────────────────────────────────────────────────────────────────────

export const api = {
  // The health probes answer with a bare report rather than the `{success, data}`
  // envelope, since they double as container liveness/readiness endpoints.
  readiness: () => requestRaw<ReadinessReport>("/health/ready"),

  markets: (chain: ChainKey) => request<MarketOverview>(`/markets${query({ chain })}`),

  portfolio: (address: string, chain: ChainKey) =>
    request<UserPortfolio>(`/portfolio/${address}${query({ chain })}`),

  activity: (address: string, chain: ChainKey, limit = 40) =>
    request<ActivityFeed>(`/activity/${address}${query({ chain, limit })}`),

  repayAmount: (args: {
    loanChainId: string;
    tokenId: number;
    loanId: string;
    userAddress: string;
    chain: ChainKey;
  }) =>
    request<{ amountToRepay: string }>(
      `/loan/repay-amount${query({
        loanChainId: args.loanChainId,
        tokenId: args.tokenId,
        loanId: args.loanId,
        userAddress: args.userAddress,
        chain: args.chain,
      })}`
    ),

  feeEstimate: (operation: FeeOperation, tokenId: number, amount: string, chain: ChainKey) =>
    request<FeeEstimate>(`/fees/estimate${query({ operation, tokenId, amount, chain })}`),

  faucetStatus: (chain: ChainKey) => request<FaucetStatus>(`/faucet/status${query({ chain })}`),

  // ─── Indexed analytics ──────────────────────────────────────────────────────
  // These answer questions chain state cannot: how a value moved over time, how
  // many addresses have ever interacted, how long delivery takes.

  protocolHistory: (chain: ChainKey, range: Range) =>
    request<ProtocolHistory>(`/analytics/tvl${query({ chain, range })}`),

  marketHistory: (chain: ChainKey, tokenId: number, range: Range) =>
    request<MarketHistory>(`/analytics/market/${tokenId}${query({ chain, range })}`),

  protocolStats: (chain: ChainKey) =>
    request<ProtocolStats>(`/analytics/stats${query({ chain })}`),

  crossChainFeed: (limit = 25, userAddress?: string) =>
    request<CrossChainFeed>(`/analytics/cross-chain${query({ limit, userAddress })}`),

  indexerStatus: () =>
    request<{ chains: IndexerChainStatus[] }>("/analytics/indexer"),

  // ─── Local demo environment ─────────────────────────────────────────────────
  // These answer `available: false` outside the two-chain local setup.

  demoStatus: () => request<DemoStatus>("/demo/status"),

  keeperCandidates: (address: string) =>
    request<{ candidates: KeeperCandidate[]; upkeepNeeded: boolean }>(`/demo/keeper/${address}`),

  timeTravel: (days: number) =>
    request<{ advancedSeconds: number }>("/demo/time-travel", {
      method: "POST",
      body: JSON.stringify({ days }),
    }),

  runKeeper: (userAddress: string) =>
    request<KeeperRunResult>("/demo/keeper", {
      method: "POST",
      body: JSON.stringify({ userAddress }),
    }),

  // ─── Writes ─────────────────────────────────────────────────────────────────

  drip: (target: string, recipient: string, amount: string, chain: ChainKey) =>
    request<{ symbol: string; amount: string; tx: { txHash: string } }>("/faucet/drip", {
      method: "POST",
      body: JSON.stringify({ target, recipient, amount, chain }),
    }),

  // ─── Transaction builders ───────────────────────────────────────────────────
  // These return unsigned transactions; the connected wallet signs and submits
  // them, so the user's own key is the only thing that can move their funds.

  build: {
    depositLiquidity: (body: BuildBody) => buildRequest("/tx/liquidity/deposit", body),
    withdrawLiquidity: (body: BuildBody) => buildRequest("/tx/liquidity/withdraw", body),
    depositCollateral: (body: BuildBody) => buildRequest("/tx/collateral/deposit", body),
    withdrawCollateral: (body: BuildBody) => buildRequest("/tx/collateral/withdraw", body),
    borrowLoan: (body: BuildBody & { collateralChainId: number }) =>
      buildRequest("/tx/loan/borrow", body),
    repayLoan: (body: BuildBody & { loanChainId: number; loanId: number }) =>
      buildRequest("/tx/loan/repay", body),
  },
};

export interface BuildBody {
  userAddress: string;
  tokenId: number;
  amount: string;
  ccipFee?: string;
  chain?: ChainKey;
}

function buildRequest(path: string, body: unknown): Promise<BuildResult> {
  return request<BuildResult>(path, { method: "POST", body: JSON.stringify(body) });
}
