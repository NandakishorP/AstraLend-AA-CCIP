"use client";

import { PageHeader } from "@/components/app/app-shell";
import { ConnectGate } from "@/components/app/connect-gate";
import { useChainKey } from "@/components/providers";
import { useActivity } from "@/lib/hooks";
import { CHAINS, explorerTx } from "@/lib/chains";
import { formatToken, shortHash, timeAgo } from "@/lib/format";
import { ApiError } from "@/lib/api";
import {
  Badge,
  Card,
  CardHeader,
  EmptyState,
  ErrorState,
  Skeleton,
  cx,
} from "@/components/ui/primitives";
import type { ActivityEvent, ActivityKind } from "@/lib/types";

/** Icon glyph and tone per event kind — the feed is scanned, not read. */
const KIND_STYLE: Record<ActivityKind, { tone: string; symbol: string }> = {
  supply: { tone: "text-mint border-mint/30 bg-mint/10", symbol: "↑" },
  withdraw: { tone: "text-ink-muted border-hairline bg-surface-2", symbol: "↓" },
  "collateral-deposit": { tone: "text-astra-200 border-astra-400/30 bg-astra-500/10", symbol: "◆" },
  "collateral-withdraw": { tone: "text-ink-muted border-hairline bg-surface-2", symbol: "◇" },
  "collateral-release": { tone: "text-mint border-mint/30 bg-mint/10", symbol: "◇" },
  borrow: { tone: "text-amber border-amber/30 bg-amber/10", symbol: "→" },
  repay: { tone: "text-mint border-mint/30 bg-mint/10", symbol: "←" },
  "lp-burn": { tone: "text-ink-muted border-hairline bg-surface-2", symbol: "×" },
  "ccip-out": { tone: "text-glow border-glow/30 bg-glow/10", symbol: "⇥" },
  "ccip-in": { tone: "text-glow border-glow/30 bg-glow/10", symbol: "⇤" },
  liquidation: { tone: "text-rose border-rose/30 bg-rose/10", symbol: "!" },
};

/**
 * Fallback for a kind the UI does not know about.
 *
 * The indexer's event vocabulary can grow ahead of this map — that is exactly
 * how `liquidation` crashed the whole page with "cannot read properties of
 * undefined". An unrecognised kind now renders in a neutral style instead of
 * taking the route down.
 */
const UNKNOWN_KIND = { tone: "text-ink-muted border-hairline bg-surface-2", symbol: "•" };

export default function ActivityPage() {
  const chain = useChainKey();
  const activity = useActivity(60);

  return (
    <>
      <PageHeader
        title="Activity"
        description={`Your protocol history on ${CHAINS[chain].name}, decoded directly from event logs — no indexer in the path.`}
      />

      <ConnectGate title="Connect to see your activity">
        <Card>
          <CardHeader
            title="Recent events"
            subtitle={
              activity.data
                ? `Blocks ${activity.data.fromBlock.toLocaleString()} – ${activity.data.toBlock.toLocaleString()}`
                : undefined
            }
            action={
              activity.data?.events.length ? <Badge>{activity.data.events.length} events</Badge> : null
            }
          />

          {activity.isLoading ? (
            <div className="space-y-px p-4">
              {[0, 1, 2, 3].map((row) => (
                <Skeleton key={row} className="h-14 w-full" />
              ))}
            </div>
          ) : activity.isError ? (
            <ErrorState
              message={
                activity.error instanceof ApiError
                  ? activity.error.message
                  : "Could not load your activity."
              }
              onRetry={() => void activity.refetch()}
            />
          ) : activity.data?.events.length ? (
            <ul className="divide-y divide-hairline">
              {activity.data.events.map((event) => (
                <ActivityRow
                  key={`${event.txHash}-${event.logIndex}`}
                  event={event}
                  href={explorerTx(chain, event.txHash)}
                />
              ))}
            </ul>
          ) : (
            <EmptyState
              title="Nothing yet"
              body="Supply liquidity, post collateral or take a loan and it will show up here within a block."
            />
          )}
        </Card>
      </ConnectGate>
    </>
  );
}

function ActivityRow({ event, href }: { event: ActivityEvent; href: string }) {
  const style = KIND_STYLE[event.kind] ?? UNKNOWN_KIND;
  const amount =
    event.amount && event.tokenDecimals !== null
      ? `${formatToken(event.amount, event.tokenDecimals)} ${event.tokenSymbol ?? ""}`
      : event.amount
        ? formatToken(event.amount, 18)
        : null;

  return (
    <li className="flex items-center gap-4 px-5 py-3.5 transition-colors hover:bg-surface-2/40">
      <span
        className={cx(
          "flex size-8 shrink-0 items-center justify-center rounded-lg border text-sm",
          style.tone
        )}
        aria-hidden
      >
        {style.symbol}
      </span>

      <div className="min-w-0 flex-1">
        <p className="text-sm text-ink">{event.label}</p>
        <p className="tabular text-xs text-ink-faint">
          {timeAgo(event.timestamp)} · block {event.blockNumber.toLocaleString()}
        </p>
      </div>

      {amount ? (
        <p className="tabular hidden text-sm text-ink-muted sm:block">{amount}</p>
      ) : null}

      <a
        href={href}
        target="_blank"
        rel="noreferrer"
        className="tabular shrink-0 text-xs text-astra-200 transition hover:underline"
      >
        {shortHash(event.txHash)} ↗
      </a>
    </li>
  );
}
