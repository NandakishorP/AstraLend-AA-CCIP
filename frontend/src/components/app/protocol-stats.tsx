"use client";

import { useIndexerStatus, useProtocolStats } from "@/lib/hooks";
import { shortAddress } from "@/lib/format";
import { Badge, Card, CardHeader, Dot, Skeleton, Stat, cx } from "@/components/ui/primitives";

/**
 * Aggregate protocol usage, plus indexer health.
 *
 * None of these numbers exist on-chain. "How many addresses have ever used this"
 * requires having watched every block — a contract cannot answer it, and neither
 * could this app before the indexer.
 */
export function ProtocolStatsCard() {
  const { data: stats, isLoading } = useProtocolStats();
  const { data: indexer } = useIndexerStatus();

  const chains = indexer?.chains ?? [];
  const behind = chains.reduce((max, chain) => Math.max(max, chain.blocksBehind ?? 0), 0);
  const anyError = chains.some((chain) => chain.lastError);
  const synced = !anyError && behind === 0 && chains.length > 0;

  return (
    <Card>
      <CardHeader
        title="Protocol activity"
        subtitle="Derived from the full indexed event history"
        action={
          chains.length > 0 ? (
            <Badge tone={anyError ? "danger" : synced ? "safe" : "warn"}>
              <Dot tone={anyError ? "danger" : synced ? "safe" : "warn"} pulse={synced} />
              {anyError ? "indexer error" : synced ? "indexed" : `${behind} blocks behind`}
            </Badge>
          ) : null
        }
      />

      {isLoading || !stats ? (
        <div className="p-5">
          <Skeleton className="h-24 w-full" />
        </div>
      ) : (
        <>
          <div className="grid grid-cols-3 gap-4 p-5">
            <Stat label="Addresses" value={stats.uniqueParticipants.toLocaleString()} size="sm" />
            <Stat label="Events" value={stats.totalEvents.toLocaleString()} size="sm" />
            <Stat
              label="Msg latency"
              value={
                stats.crossChain.avgLatencyMs > 0
                  ? `${(stats.crossChain.avgLatencyMs / 1000).toFixed(1)}s`
                  : "—"
              }
              hint="average delivery"
              size="sm"
            />
          </div>

          {/* The protocol's own aggregate-borrow counter is never incremented on
              borrow, so this is summed from indexed borrow and repay events
              across both chains instead. */}
          <div className="grid grid-cols-3 gap-4 border-t border-hairline px-5 py-4">
            <Stat
              label="Outstanding"
              value={`${(Number(stats.outstandingDebt) / 1e6).toLocaleString("en-US", { maximumFractionDigits: 0 })}`}
              hint="debt, from events"
              tone="warn"
              size="sm"
            />
            <Stat
              label="Borrowed"
              value={`${(Number(stats.totalBorrowedEver) / 1e6).toLocaleString("en-US", { maximumFractionDigits: 0 })}`}
              hint="all time"
              size="sm"
            />
            <Stat
              label="Repaid"
              value={`${(Number(stats.totalRepaid) / 1e6).toLocaleString("en-US", { maximumFractionDigits: 0 })}`}
              hint="all time"
              size="sm"
            />
          </div>

          {stats.eventsByKind.length > 0 ? (
            <div className="border-t border-hairline px-5 py-4">
              <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
                By action
              </p>
              <ul className="mt-3 space-y-2">
                {stats.eventsByKind.slice(0, 6).map((row) => {
                  const share = stats.totalEvents === 0 ? 0 : (row.count / stats.totalEvents) * 100;
                  return (
                    <li key={row.kind} className="flex items-center gap-3">
                      <span className="w-36 shrink-0 truncate text-xs text-ink-muted">
                        {row.kind.replace(/-/g, " ")}
                      </span>
                      <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-2">
                        <span
                          className="block h-full rounded-full bg-gradient-to-r from-astra-500 to-glow transition-[width] duration-500"
                          style={{ width: `${Math.max(4, share)}%` }}
                        />
                      </span>
                      <span className="tabular w-8 shrink-0 text-right text-xs text-ink-faint">
                        {row.count}
                      </span>
                    </li>
                  );
                })}
              </ul>
            </div>
          ) : null}

          {stats.topParticipants.length > 0 ? (
            <div className="border-t border-hairline px-5 py-4">
              <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
                Most active
              </p>
              <ul className="mt-3 space-y-1.5">
                {stats.topParticipants.map((participant) => (
                  <li key={participant.address} className="flex items-center justify-between text-xs">
                    <span className="tabular text-ink-muted">{shortAddress(participant.address, 6)}</span>
                    <span className="text-ink-faint">{participant.eventCount} actions</span>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}

          {chains.length > 0 ? (
            <div className="border-t border-hairline px-5 py-3">
              <ul className="space-y-1">
                {chains.map((chain) => (
                  <li
                    key={chain.chain}
                    className={cx(
                      "tabular flex items-center justify-between text-[11px]",
                      chain.lastError ? "text-rose" : "text-ink-faint"
                    )}
                  >
                    <span>{chain.chain} indexer</span>
                    <span>
                      block {chain.lastBlock.toLocaleString()} / {chain.headBlock?.toLocaleString() ?? "—"}
                      {chain.reorgsHandled > 0 ? ` · ${chain.reorgsHandled} reorgs` : ""}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </>
      )}
    </Card>
  );
}
