"use client";

import { useCrossChainFeed } from "@/lib/hooks";
import { CHAINS } from "@/lib/chains";
import { timeAgo } from "@/lib/format";
import { Badge, Card, CardHeader, Dot, EmptyState, Skeleton, cx } from "@/components/ui/primitives";
import type { CcipMessage } from "@/lib/types";

/**
 * Live cross-chain message monitor.
 *
 * The single most useful view during a demo: it makes the asynchronous half of
 * the protocol visible. A message appears the moment it is sent and flips to
 * delivered when it lands on the far chain, so the audience can watch state
 * cross between chains rather than take it on trust.
 *
 * Backed by the database rather than the relayer's memory, so a message that was
 * in flight across a restart is still shown — and still shown as pending.
 */
export function CrossChainMonitor({ limit = 8 }: { limit?: number }) {
  const { data, isLoading } = useCrossChainFeed(limit);

  const stats = data?.stats;
  const messages = data?.messages ?? [];

  return (
    <Card>
      <CardHeader
        title="Cross-chain messages"
        subtitle="Sends are indexed from the router; deliveries are reported by the relayer."
        action={
          stats ? (
            <div className="flex items-center gap-1.5">
              {stats.pending > 0 ? (
                <Badge tone="warn">
                  <Dot tone="warn" pulse />
                  {stats.pending} in flight
                </Badge>
              ) : (
                <Badge tone="safe">all delivered</Badge>
              )}
            </div>
          ) : null
        }
      />

      {stats ? (
        <dl className="grid grid-cols-4 divide-x divide-hairline border-b border-hairline text-center">
          <Tile label="Total" value={stats.total} />
          <Tile label="Delivered" value={stats.delivered} tone="safe" />
          <Tile label="Pending" value={stats.pending} tone={stats.pending > 0 ? "warn" : undefined} />
          <Tile label="Failed" value={stats.failed} tone={stats.failed > 0 ? "danger" : undefined} />
        </dl>
      ) : null}

      {isLoading ? (
        <div className="space-y-px p-4">
          {[0, 1, 2].map((row) => (
            <Skeleton key={row} className="h-12 w-full" />
          ))}
        </div>
      ) : messages.length === 0 ? (
        <EmptyState
          title="No cross-chain traffic yet"
          body="Post collateral or repay from the satellite chain and the message shows up here as it travels."
        />
      ) : (
        <ul className="divide-y divide-hairline">
          {messages.map((message) => (
            <MessageRow key={message.messageId} message={message} />
          ))}
        </ul>
      )}
    </Card>
  );
}

function Tile({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone?: "safe" | "warn" | "danger";
}) {
  const color = {
    safe: "text-mint",
    warn: "text-amber",
    danger: "text-rose",
  }[tone ?? "safe"];

  return (
    <div className="px-3 py-3">
      <dt className="text-[10px] uppercase tracking-[0.14em] text-ink-faint">{label}</dt>
      <dd className={cx("tabular mt-1 font-display text-lg font-semibold", tone ? color : "text-ink")}>
        {value}
      </dd>
    </div>
  );
}

function MessageRow({ message }: { message: CcipMessage }) {
  const source = message.sourceChain ? CHAINS[message.sourceChain]?.shortName : "?";
  const destination = message.destChain ? CHAINS[message.destChain]?.shortName : "?";

  const tone =
    message.status === "delivered" ? "safe" : message.status === "failed" ? "danger" : "warn";

  return (
    <li className="flex items-center gap-3 px-5 py-3">
      <Dot tone={tone} pulse={message.status === "pending"} />

      <div className="min-w-0 flex-1">
        <p className="flex items-center gap-2 text-sm text-ink">
          <span>{source}</span>
          <svg viewBox="0 0 16 16" className="size-3 text-ink-faint" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M3 8h10M9 4l4 4-4 4" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span>{destination}</span>
          {message.action ? (
            <span className="text-xs text-ink-faint">{message.action.replace(/_/g, " ").toLowerCase()}</span>
          ) : null}
        </p>
        <p className="tabular text-xs text-ink-faint">
          {message.messageId.slice(0, 10)}… · sent {timeAgo(message.sentAt)}
        </p>
      </div>

      <Badge tone={tone}>{message.status}</Badge>
    </li>
  );
}
