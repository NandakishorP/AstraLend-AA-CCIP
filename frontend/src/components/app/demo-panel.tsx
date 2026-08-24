"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useAccount } from "wagmi";
import { api, ApiError } from "@/lib/api";
import { formatToken, timeAgo } from "@/lib/format";
import { useRefreshAfterTx } from "@/lib/hooks";
import { useToast } from "@/components/ui/toast";
import { Badge, Button, Card, CardHeader, Dot, cx } from "@/components/ui/primitives";
import type { DemoChainStatus, RelayerMessage } from "@/lib/types";

/**
 * Controls for the local two-chain environment.
 *
 * A 180-day loan term and a three-stage liquidation cascade cannot be shown on
 * a real network inside a demo, so the local nodes' clocks are movable and the
 * keeper is manually runnable. The panel hides itself entirely when the backend
 * reports it is not in that environment, so the product UI is unaffected
 * anywhere else.
 */
export function DemoPanel() {
  const { address } = useAccount();
  const toast = useToast();
  const refresh = useRefreshAfterTx();
  const queryClient = useQueryClient();
  const [expanded, setExpanded] = useState(true);

  const status = useQuery({
    queryKey: ["demo-status"],
    queryFn: () => api.demoStatus(),
    refetchInterval: 4000,
    retry: false,
  });

  const keeper = useQuery({
    queryKey: ["keeper-candidates", address],
    queryFn: () => api.keeperCandidates(address as string),
    enabled: Boolean(address && status.data?.available),
    refetchInterval: 8000,
    retry: false,
  });

  const invalidate = () => {
    refresh();
    void queryClient.invalidateQueries({ queryKey: ["demo-status"] });
    void queryClient.invalidateQueries({ queryKey: ["keeper-candidates"] });
  };

  const travel = useMutation({
    mutationFn: (days: number) => api.timeTravel(days),
    onSuccess: (_data, days) => {
      toast.push({
        tone: "success",
        title: `Advanced ${days} days`,
        body: "Both chain clocks moved forward. Interest and due dates update on the next read.",
      });
      invalidate();
    },
    onError: (error) =>
      toast.push({
        tone: "error",
        title: "Time travel failed",
        body: error instanceof ApiError ? error.message : "Unknown error.",
      }),
  });

  const runKeeper = useMutation({
    mutationFn: () => api.runKeeper(address as string),
    onSuccess: (result) => {
      toast.push({
        tone: result.acted.length > 0 ? "success" : "info",
        title: result.message,
        body: result.acted.map((a) => a.outcome).join(" · ") || undefined,
      });
      invalidate();
    },
    onError: (error) =>
      toast.push({
        tone: "error",
        title: "Keeper run failed",
        body: error instanceof ApiError ? error.message : "Unknown error.",
      }),
  });

  // Outside the local environment this renders nothing at all.
  if (!status.data?.available) return null;

  const messages = status.data.messages ?? [];
  const inFlight = messages.filter((m) => m.status === "pending").length;
  const candidates = keeper.data?.candidates ?? [];

  return (
    <Card className="border-amber/25">
      <CardHeader
        title={
          <span className="flex items-center gap-2">
            <Badge tone="warn">Demo environment</Badge>
            Local two-chain controls
          </span>
        }
        subtitle="Only present on local nodes — the deployed app never shows this."
        action={
          <button
            onClick={() => setExpanded((value) => !value)}
            className="text-xs text-ink-faint transition hover:text-ink"
          >
            {expanded ? "Hide" : "Show"}
          </button>
        }
      />

      {expanded ? (
        <div className="space-y-5 p-5">
          {/* ── Chains ─────────────────────────────────────────────────── */}
          <div className="grid gap-3 sm:grid-cols-2">
            {status.data.chains.map((chain) => (
              <ChainClock key={chain.chain} chain={chain} />
            ))}
          </div>

          {/* ── Time travel ────────────────────────────────────────────── */}
          <div>
            <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
              Advance chain time
            </p>
            <p className="mt-1 text-xs leading-relaxed text-ink-faint">
              Loans run 180 days and each keeper penalty adds 30 — a full lifecycle needs
              roughly 300 days of chain time.
            </p>
            <div className="mt-2.5 flex flex-wrap gap-2">
              {[1, 30, 90, 185, 200].map((days) => (
                <Button
                  key={days}
                  size="sm"
                  variant="secondary"
                  loading={travel.isPending && travel.variables === days}
                  disabled={travel.isPending}
                  onClick={() => travel.mutate(days)}
                >
                  +{days}d
                </Button>
              ))}
            </div>
          </div>

          {/* ── Keeper ─────────────────────────────────────────────────── */}
          <div className="rounded-xl border border-hairline bg-surface-2/40 p-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-sm font-medium text-ink">Liquidation keeper</p>
                <p className="mt-0.5 text-xs text-ink-faint">
                  {candidates.length === 0
                    ? "No overdue loans. Advance time past a loan's due date first."
                    : `${candidates.length} overdue loan(s) ready for the keeper.`}
                </p>
              </div>
              <Button
                size="sm"
                variant={candidates.length > 0 ? "primary" : "secondary"}
                disabled={!address || candidates.length === 0 || runKeeper.isPending}
                loading={runKeeper.isPending}
                onClick={() => runKeeper.mutate()}
              >
                Run keeper
              </Button>
            </div>

            {candidates.length > 0 ? (
              <ul className="mt-3 space-y-1.5 border-t border-hairline pt-3">
                {candidates.map((candidate) => (
                  <li
                    key={`${candidate.chainId}-${candidate.loanId}`}
                    className="tabular flex items-center justify-between gap-3 text-xs"
                  >
                    <span className="text-ink-muted">
                      Loan #{candidate.loanId} · chain {candidate.chainId}
                    </span>
                    <span className="text-ink-faint">
                      {candidate.overdueDays}d overdue · penalty {candidate.penaltyCount}/2 ·{" "}
                      {formatToken(candidate.outstanding, 6, 2)} SC
                    </span>
                  </li>
                ))}
              </ul>
            ) : null}

            <p className="mt-3 text-[11px] leading-relaxed text-ink-faint">
              The contract escalates before seizing collateral: two penalties of 5% each,
              extending the due date by 30 days, and only then liquidation.
            </p>
          </div>

          {/* ── CCIP messages ──────────────────────────────────────────── */}
          <div>
            <div className="flex items-center justify-between">
              <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
                Cross-chain messages
              </p>
              <span className="flex items-center gap-2 text-[11px] text-ink-faint">
                <Dot
                  tone={status.data.relayer.reachable ? "safe" : "danger"}
                  pulse={inFlight > 0}
                />
                {status.data.relayer.reachable
                  ? `relayer up · ${status.data.relayer.delivered} delivered`
                  : "relayer offline"}
              </span>
            </div>

            {messages.length === 0 ? (
              <p className="mt-2 text-xs text-ink-faint">
                Nothing sent yet. Deposit collateral on Arbitrum and it will appear here on its
                way to Ethereum.
              </p>
            ) : (
              <ul className="mt-2 max-h-56 space-y-1.5 overflow-y-auto pr-1">
                {messages.slice(0, 12).map((message) => (
                  <MessageRow key={message.messageId} message={message} />
                ))}
              </ul>
            )}
          </div>
        </div>
      ) : null}
    </Card>
  );
}

function ChainClock({ chain }: { chain: DemoChainStatus }) {
  const skewDays = Math.floor(chain.skewSeconds / 86_400);

  return (
    <div className="rounded-xl border border-hairline bg-surface-2/40 p-3.5">
      <div className="flex items-center justify-between gap-2">
        <span className="flex items-center gap-2 text-sm font-medium text-ink">
          <Dot tone={chain.reachable ? "safe" : "danger"} />
          {chain.name}
        </span>
        <Badge tone={chain.role === "hub" ? "accent" : "info"}>{chain.role}</Badge>
      </div>
      <dl className="tabular mt-2.5 space-y-1 text-xs">
        <div className="flex justify-between">
          <dt className="text-ink-faint">Block</dt>
          <dd className="text-ink-muted">{chain.blockNumber.toLocaleString()}</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-ink-faint">Chain clock</dt>
          <dd className={cx(skewDays > 0 ? "text-amber" : "text-ink-muted")}>
            {skewDays > 0 ? `+${skewDays}d ahead` : "real time"}
          </dd>
        </div>
      </dl>
    </div>
  );
}

function MessageRow({ message }: { message: RelayerMessage }) {
  const tone = {
    pending: "warn",
    delivered: "safe",
    reverted: "danger",
    failed: "danger",
    undeliverable: "danger",
  }[message.status] as "warn" | "safe" | "danger";

  return (
    <li className="flex items-center gap-2.5 rounded-lg border border-hairline/70 bg-surface-2/30 px-2.5 py-2 text-xs">
      <Dot tone={tone} pulse={message.status === "pending"} />
      <span className="tabular font-medium uppercase tracking-wide text-ink-muted">
        {message.from} → {message.to}
      </span>
      <span className="tabular truncate text-ink-faint">{message.messageId.slice(0, 10)}</span>
      <span className="ml-auto shrink-0 text-ink-faint">
        {message.status === "pending"
          ? "in flight"
          : message.status === "delivered"
            ? timeAgo(Math.floor(new Date(message.deliveredAt ?? message.sentAt).getTime() / 1000))
            : message.status}
      </span>
    </li>
  );
}
