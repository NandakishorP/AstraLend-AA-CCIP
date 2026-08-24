"use client";

import { useQuery } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { api } from "@/lib/api";
import { CHAINS } from "@/lib/chains";
import {
  formatEth,
  formatPercent,
  formatToken,
  formatUsd,
  healthTone,
  parseAmount,
} from "@/lib/format";
import { useChainKey } from "@/components/providers";
import { useTxRunner } from "@/lib/use-tx-runner";
import { Modal } from "@/components/ui/modal";
import { AmountField } from "./amount-field";
import { Badge, Button, Meter, cx } from "@/components/ui/primitives";
import type {
  BuildResult,
  FeeOperation,
  Market,
  MarketOverview,
  UserLoan,
  UserPortfolio,
} from "@/lib/types";

export type ActionKind =
  | "supply"
  | "withdraw-supply"
  | "deposit-collateral"
  | "withdraw-collateral"
  | "borrow"
  | "repay";

export interface ActionRequest {
  kind: ActionKind;
  tokenId: number;
  /** Required for `repay` — identifies which loan is being settled. */
  loan?: UserLoan;
}

const COPY: Record<
  ActionKind,
  { title: string; verb: string; blurb: string; feeOperation: FeeOperation }
> = {
  supply: {
    title: "Supply liquidity",
    verb: "Supply",
    blurb: "Deposit into the pool and receive LP tokens. Earns the borrow rate scaled by utilization.",
    feeOperation: "depositLiquidity",
  },
  "withdraw-supply": {
    title: "Withdraw liquidity",
    verb: "Withdraw",
    blurb: "Burn LP tokens and reclaim your share of the pool.",
    feeOperation: "withdrawLiquidity",
  },
  "deposit-collateral": {
    title: "Deposit collateral",
    verb: "Deposit",
    blurb: "Lock assets to back loans. Collateral counts toward borrowing power on every chain.",
    feeOperation: "depositCollateral",
  },
  "withdraw-collateral": {
    title: "Withdraw collateral",
    verb: "Withdraw",
    blurb: "Reclaim collateral that is not backing an active loan.",
    feeOperation: "withdrawCollateral",
  },
  borrow: {
    title: "Borrow",
    verb: "Borrow",
    blurb: "Draw a stablecoin loan against your collateral. 180-day term, 75% maximum LTV.",
    feeOperation: "borrowLoan",
  },
  repay: {
    title: "Repay loan",
    verb: "Repay",
    blurb: "Interest is settled before principal. Full repayment releases the locked collateral.",
    feeOperation: "repayLoan",
  },
};

export function ActionDialog({
  request,
  overview,
  portfolio,
  onClose,
}: {
  request: ActionRequest | null;
  overview: MarketOverview | undefined;
  portfolio: UserPortfolio | undefined;
  onClose: () => void;
}) {
  const chain = useChainKey();
  const { address, isConnected } = useAccount();
  const { run, state, reset } = useTxRunner();
  const [input, setInput] = useState("");

  const market = overview?.markets.find((m) => m.tokenId === request?.tokenId);
  const position = portfolio?.positions.find((p) => p.tokenId === request?.tokenId);
  const copy = request ? COPY[request.kind] : null;

  // Borrow and repay are denominated in the stablecoin; everything else in the
  // market's own token.
  const isStableDenominated = request?.kind === "borrow" || request?.kind === "repay";
  const decimals = isStableDenominated
    ? (portfolio?.stableCoinDecimals ?? overview?.parameters.stableCoin.decimals ?? 6)
    : (market?.decimals ?? 18);
  const symbol = isStableDenominated
    ? (portfolio?.stableCoinSymbol ?? overview?.parameters.stableCoin.symbol ?? "USD")
    : (market?.symbol ?? "");

  // Clear the field whenever a different action is opened. Done during render
  // rather than in an effect so the dialog never paints last action's amount
  // for a frame.
  const [lastRequest, setLastRequest] = useState<ActionRequest | null>(null);
  if (request !== lastRequest) {
    setLastRequest(request);
    if (input !== "") setInput("");
    if (state.phase !== "idle") reset();
  }

  // ── Live repay quote ──────────────────────────────────────────────────────
  // Debt accrues every block, so a full repayment has to be priced against the
  // contract at the moment of the transaction, not against a cached snapshot.
  const repayQuote = useQuery({
    queryKey: ["repay-amount", chain, address, request?.loan?.loanId, request?.tokenId],
    queryFn: () =>
      api.repayAmount({
        loanChainId: request!.loan!.loanChainId,
        tokenId: request!.tokenId,
        loanId: request!.loan!.loanId,
        userAddress: address as string,
        chain,
      }),
    enabled: Boolean(request?.kind === "repay" && request.loan && address),
    refetchInterval: 20_000,
  });

  const maxAmount = useMemo(
    () => computeMax(request, market, position, portfolio, repayQuote.data?.amountToRepay),
    [request, market, position, portfolio, repayQuote.data]
  );

  const amount = parseAmount(input, decimals);
  const amountUsd = useMemo(() => {
    if (amount === null) return undefined;
    if (isStableDenominated) return (amount * 10n ** BigInt(18 - decimals)).toString();
    if (!market) return undefined;
    return ((amount * BigInt(market.priceUsd)) / 10n ** BigInt(market.decimals)).toString();
  }, [amount, decimals, isStableDenominated, market]);

  // ── CCIP fee ──────────────────────────────────────────────────────────────
  // Only satellite chains pay one; the hub updates state directly.
  const feeQuery = useQuery({
    queryKey: ["fee", chain, copy?.feeOperation, request?.tokenId, amount?.toString()],
    queryFn: () =>
      api.feeEstimate(copy!.feeOperation, request!.tokenId, (amount ?? 0n).toString(), chain),
    enabled: Boolean(request && chain !== "eth" && amount !== null),
    staleTime: 30_000,
  });
  const ccipFee = chain === "eth" ? "0" : (feeQuery.data?.recommendedValueWei ?? "0");

  const validationError = validate(request, amount, input, maxAmount, symbol, decimals);
  const projection = useMemo(
    () => project(request, amount, amountUsd, portfolio, overview),
    [request, amount, amountUsd, portfolio, overview]
  );

  const busy = state.phase === "building" || state.phase === "signing" || state.phase === "confirming";

  /**
   * The chain id whose collateral backs a new loan.
   *
   * The contract looks collateral up by the chain it was deposited on and
   * reverts if that chain holds none — so a borrower whose collateral sits on a
   * satellite must pass the satellite's id, not the chain they are borrowing
   * from. Cross-chain collateral is the entire point of the protocol, so
   * defaulting to the connected chain is wrong more often than it is right.
   * Falls back to the current chain when nothing is deposited anywhere.
   */
  function collateralChainId(): number {
    const byChain = position?.collateralByChain ?? {};
    const best = Object.entries(byChain).sort(
      ([, a], [, b]) => (BigInt(b) > BigInt(a) ? 1 : BigInt(b) < BigInt(a) ? -1 : 0)
    )[0];
    return best ? Number(best[0]) : CHAINS[chain].id;
  }

  async function submit() {
    if (!request || !copy || amount === null || !address) return;

    const build = (): Promise<BuildResult> => {
      const base = { userAddress: address, tokenId: request.tokenId, amount: amount.toString(), ccipFee, chain };
      switch (request.kind) {
        case "supply":
          return api.build.depositLiquidity(base);
        case "withdraw-supply":
          return api.build.withdrawLiquidity(base);
        case "deposit-collateral":
          return api.build.depositCollateral(base);
        case "withdraw-collateral":
          return api.build.withdrawCollateral(base);
        case "borrow":
          return api.build.borrowLoan({ ...base, collateralChainId: collateralChainId() });
        case "repay":
          return api.build.repayLoan({
            ...base,
            loanChainId: Number(request.loan!.loanChainId),
            loanId: Number(request.loan!.loanId),
          });
      }
    };

    const ok = await run(chain, copy.title, build);
    if (ok) onClose();
  }

  if (!request || !copy) return null;

  return (
    <Modal
      open
      // Closing mid-flight is allowed: the transaction is already with the
      // wallet and the dashboard reflects it regardless. Blocking the close
      // meant a stalled receipt trapped the user with no way out.
      onClose={onClose}
      title={copy.title}
      subtitle={copy.blurb}
      footer={
        <div className="flex flex-col gap-3">
          {state.error ? (
            <p className="rounded-lg border border-rose/30 bg-rose/10 px-3 py-2 text-xs leading-relaxed text-rose">
              {state.error}
            </p>
          ) : null}
          <Button
            onClick={submit}
            loading={busy}
            disabled={!isConnected || amount === null || Boolean(validationError)}
            className="w-full"
            size="lg"
          >
            {busy ? phaseLabel(state.phase, state.step, state.total) : `${copy.verb} ${symbol}`}
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        <AmountField
          value={input}
          onChange={setInput}
          symbol={symbol}
          decimals={decimals}
          max={maxAmount.value}
          maxLabel={maxAmount.label}
          usdValue={amountUsd ? formatUsd(amountUsd) : undefined}
          error={validationError}
          disabled={busy}
        />

        {request.kind === "repay" && request.loan ? (
          <RepaySummary loan={request.loan} quote={repayQuote.data?.amountToRepay} decimals={decimals} symbol={symbol} />
        ) : null}

        {projection ? <HealthProjection {...projection} /> : null}

        <dl className="space-y-2 rounded-xl border border-hairline bg-surface-2/40 p-4 text-xs">
          <Row label="Network">{CHAINS[chain].name}</Row>
          {chain === "eth" ? (
            <Row label="Settlement">Direct — state updates on the hub chain</Row>
          ) : (
            <>
              <Row label="Settlement">Forwarded to Ethereum over CCIP</Row>
              <Row label="CCIP fee">
                {feeQuery.isFetching ? (
                  <span className="text-ink-faint">estimating…</span>
                ) : feeQuery.isError ? (
                  <span className="text-amber">unavailable</span>
                ) : (
                  <span className="text-ink">{formatEth(ccipFee)}</span>
                )}
              </Row>
            </>
          )}
          {market && !isStableDenominated ? (
            <Row label={`${market.symbol} price`}>{formatUsd(market.priceUsd)}</Row>
          ) : null}
          {request.kind === "supply" && market ? (
            <Row label="Supply APR">{formatPercent(market.supplyApr)}</Row>
          ) : null}
          {request.kind === "borrow" && market ? (
            <Row label="Borrow APR">{formatPercent(market.borrowApr)}</Row>
          ) : null}
          {request.kind === "borrow" && overview ? (
            <Row label="Loan term">{overview.parameters.loanDurationDays} days</Row>
          ) : null}
        </dl>

        {chain !== "eth" ? (
          <p className="rounded-lg border border-glow/25 bg-glow/8 px-3 py-2.5 text-xs leading-relaxed text-ink-muted">
            Cross-chain actions settle asynchronously. Your balance on Arbitrum updates immediately;
            the hub reflects it once CCIP delivers the message, usually within a few minutes.
          </p>
        ) : null}
      </div>
    </Modal>
  );
}

// ─── Pieces ───────────────────────────────────────────────────────────────────

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <dt className="text-ink-faint">{label}</dt>
      <dd className="tabular text-right font-medium text-ink-muted">{children}</dd>
    </div>
  );
}

function RepaySummary({
  loan,
  quote,
  decimals,
  symbol,
}: {
  loan: UserLoan;
  quote: string | undefined;
  decimals: number;
  symbol: string;
}) {
  return (
    <div className="rounded-xl border border-hairline bg-surface-2/40 p-4">
      <div className="flex items-center justify-between">
        <p className="text-xs font-medium uppercase tracking-[0.14em] text-ink-faint">
          Loan #{loan.loanId}
        </p>
        <Badge tone={loan.isOverdue ? "danger" : "neutral"}>
          {loan.isOverdue ? "Overdue" : `${loan.daysUntilDue}d left`}
        </Badge>
      </div>
      <dl className="mt-3 space-y-2 text-xs">
        <Row label="Principal">{formatToken(loan.principalAmount, decimals)} {symbol}</Row>
        <Row label="Accrued interest">{formatToken(loan.accruedInterest, decimals)} {symbol}</Row>
        <Row label="Payoff amount">
          <span className="text-ink">
            {formatToken(quote ?? loan.currentDebt, decimals)} {symbol}
          </span>
        </Row>
        <Row label="Collateral locked">
          {formatToken(loan.collateralUsed, 18)} {loan.tokenSymbol}
        </Row>
      </dl>
    </div>
  );
}

function HealthProjection({
  beforeHealth,
  afterHealth,
  beforeLtv,
  afterLtv,
  liquidationLtv,
}: {
  beforeHealth: number | null;
  afterHealth: number | null;
  beforeLtv: number;
  afterLtv: number;
  liquidationLtv: number;
}) {
  const after = healthTone(afterHealth);
  const willLiquidate = afterHealth !== null && afterHealth < 1;

  return (
    <div
      className={cx(
        "rounded-xl border p-4",
        willLiquidate ? "border-rose/40 bg-rose/8" : "border-hairline bg-surface-2/40"
      )}
    >
      <div className="flex items-center justify-between text-xs">
        <span className="font-medium uppercase tracking-[0.14em] text-ink-faint">Health factor</span>
        <span className="tabular flex items-center gap-2 font-medium">
          <span className="text-ink-faint">{beforeHealth === null ? "—" : beforeHealth.toFixed(2)}</span>
          <svg viewBox="0 0 16 16" className="size-3 text-ink-faint" fill="none" stroke="currentColor" strokeWidth="1.8">
            <path d="M3 8h10M9 4l4 4-4 4" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span
            className={cx(
              after.tone === "danger" && "text-rose",
              after.tone === "warn" && "text-amber",
              after.tone === "safe" && "text-mint",
              after.tone === "neutral" && "text-ink-muted"
            )}
          >
            {afterHealth === null ? "—" : afterHealth.toFixed(2)}
          </span>
        </span>
      </div>

      <div className="mt-3">
        <Meter
          value={afterLtv}
          max={100}
          markerAt={liquidationLtv}
          markerLabel={`Liquidation at ${liquidationLtv}% LTV`}
          tone={afterLtv >= liquidationLtv ? "danger" : afterLtv > liquidationLtv * 0.85 ? "warn" : "accent"}
        />
        <div className="tabular mt-2 flex justify-between text-[11px] text-ink-faint">
          <span>
            LTV {formatPercent(beforeLtv, 1)} → {formatPercent(afterLtv, 1)}
          </span>
          <span>Liquidation at {formatPercent(liquidationLtv, 0)}</span>
        </div>
      </div>

      {willLiquidate ? (
        <p className="mt-3 text-xs leading-relaxed text-rose">
          This would put your position below the liquidation threshold. Reduce the amount or add
          collateral first.
        </p>
      ) : null}
    </div>
  );
}

// ─── Logic ────────────────────────────────────────────────────────────────────

interface MaxBound {
  value: bigint | undefined;
  label: string;
}

function computeMax(
  request: ActionRequest | null,
  market: Market | undefined,
  position: UserPortfolio["positions"][number] | undefined,
  portfolio: UserPortfolio | undefined,
  repayQuote: string | undefined
): MaxBound {
  if (!request) return { value: undefined, label: "Available" };

  switch (request.kind) {
    case "supply":
    case "deposit-collateral":
      return { value: position ? BigInt(position.walletBalance) : undefined, label: "Wallet" };

    case "withdraw-supply":
      return { value: position ? BigInt(position.liquidityDeposited) : undefined, label: "Supplied" };

    case "withdraw-collateral":
      return {
        value: position ? BigInt(position.collateralDeposited) : undefined,
        label: "Deposited",
      };

    case "borrow": {
      if (!portfolio) return { value: undefined, label: "Borrowable" };
      // Borrowing power is quoted in 1e18 USD; the loan is drawn in stablecoin
      // units, so scale down by the difference in precision.
      const scale = 10n ** BigInt(18 - portfolio.stableCoinDecimals);
      return {
        value: BigInt(portfolio.summary.availableToBorrowUsd) / scale,
        label: "Borrowable",
      };
    }

    case "repay": {
      if (!portfolio || !request.loan) return { value: undefined, label: "Owed" };
      const owed = BigInt(repayQuote ?? request.loan.currentDebt);
      const wallet = BigInt(portfolio.stableCoinBalance);
      // Overpaying reverts, and paying more than the wallet holds fails on
      // transfer — the usable ceiling is whichever is smaller.
      return { value: owed < wallet ? owed : wallet, label: owed < wallet ? "Owed" : "Wallet" };
    }
  }
}

function validate(
  request: ActionRequest | null,
  amount: bigint | null,
  input: string,
  max: MaxBound,
  symbol: string,
  decimals: number
): string | null {
  if (!request) return null;
  if (!input.trim()) return null;
  if (amount === null) return "Enter a valid amount greater than zero.";
  if (max.value !== undefined && amount > max.value) {
    return `Exceeds your ${max.label.toLowerCase()} balance of ${formatToken(max.value, decimals)} ${symbol}.`;
  }
  return null;
}

interface Projection {
  beforeHealth: number | null;
  afterHealth: number | null;
  beforeLtv: number;
  afterLtv: number;
  liquidationLtv: number;
}

/**
 * Projects the account's health after the pending action.
 *
 * Mirrors the backend's account summary math: borrowing power is collateral
 * value × LTV, and the health factor is collateral × liquidation threshold ÷
 * debt. Only actions that move collateral or debt shift the numbers, so supply
 * and withdraw of pool liquidity return nothing and the panel stays hidden.
 */
function project(
  request: ActionRequest | null,
  amount: bigint | null,
  amountUsd: string | undefined,
  portfolio: UserPortfolio | undefined,
  overview: MarketOverview | undefined
): Projection | null {
  if (!request || !portfolio || !overview) return null;
  if (request.kind === "supply" || request.kind === "withdraw-supply") return null;

  const threshold = overview.parameters.liquidationThresholdPercent;
  const collateral = Number(formatUsdNumberRaw(portfolio.summary.collateralUsd));
  const debt = Number(formatUsdNumberRaw(portfolio.summary.debtUsd));
  const delta = amount === null || !amountUsd ? 0 : Number(formatUsdNumberRaw(amountUsd));

  let nextCollateral = collateral;
  let nextDebt = debt;

  switch (request.kind) {
    case "deposit-collateral":
      nextCollateral = collateral + delta;
      break;
    case "withdraw-collateral":
      nextCollateral = Math.max(0, collateral - delta);
      break;
    case "borrow":
      nextDebt = debt + delta;
      break;
    case "repay":
      nextDebt = Math.max(0, debt - delta);
      break;
  }

  const health = (c: number, d: number) => (d === 0 ? null : (c * (threshold / 100)) / d);
  const ltv = (c: number, d: number) => (c === 0 ? 0 : (d / c) * 100);

  return {
    beforeHealth: health(collateral, debt),
    afterHealth: health(nextCollateral, nextDebt),
    beforeLtv: ltv(collateral, debt),
    afterLtv: ltv(nextCollateral, nextDebt),
    liquidationLtv: threshold,
  };
}

/** 1e18-scaled USD string → plain dollars, without currency formatting. */
function formatUsdNumberRaw(scaled1e18: string): number {
  return Number(BigInt(scaled1e18) / 10n ** 12n) / 1e6;
}

function phaseLabel(phase: string, step: number, total: number): string {
  if (phase === "building") return "Preparing…";
  if (phase === "signing") return total > 1 ? `Sign ${step + 1} of ${total}` : "Confirm in wallet";
  if (phase === "confirming") return "Confirming…";
  return "Working…";
}
