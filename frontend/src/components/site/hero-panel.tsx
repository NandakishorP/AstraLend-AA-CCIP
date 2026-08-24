"use client";

import { useMarkets } from "@/lib/hooks";
import { formatPercent, formatUsd } from "@/lib/format";
import { Skeleton, TokenGlyph } from "@/components/ui/primitives";

/**
 * The hero's right-hand panel.
 *
 * Shows the protocol's actual markets rather than a mocked-up screenshot — the
 * page already reads the API for its stats bar, so the same data can carry the
 * visual weight without inventing numbers a visitor might take literally.
 */
export function HeroPanel() {
  const { data, isLoading } = useMarkets("eth");

  return (
    <div className="relative">
      {/* Glow behind the panel, tinted to the accent ramp. */}
      <div
        className="pointer-events-none absolute -inset-8 opacity-70 blur-3xl"
        style={{
          background:
            "radial-gradient(60% 60% at 60% 30%, rgba(124,58,237,0.35), rgba(34,211,238,0.12) 55%, transparent 75%)",
        }}
        aria-hidden
      />

      <div className="relative overflow-hidden rounded-2xl border border-hairline bg-surface/85 backdrop-blur-xl">
        {/* Chrome */}
        <div className="flex items-center gap-2 border-b border-hairline px-4 py-3">
          <span className="flex gap-1.5" aria-hidden>
            <span className="size-2 rounded-full bg-rose/50" />
            <span className="size-2 rounded-full bg-amber/50" />
            <span className="size-2 rounded-full bg-mint/50" />
          </span>
          <span className="ml-1 text-xs text-ink-faint">astralend.app / markets</span>
        </div>

        <div className="space-y-4 p-4">
          <div className="flex items-end justify-between">
            <div>
              <p className="text-[10px] uppercase tracking-[0.16em] text-ink-faint">
                Total value locked
              </p>
              {isLoading || !data ? (
                <Skeleton className="mt-1.5 h-8 w-32" />
              ) : (
                <p className="tabular mt-1 font-display text-3xl font-semibold text-ink">
                  {formatUsd(data.totalValueLockedUsd)}
                </p>
              )}
            </div>
            <span className="rounded-full border border-mint/25 bg-mint/10 px-2.5 py-1 text-[11px] text-mint">
              Live
            </span>
          </div>

          <div className="space-y-2">
            {isLoading || !data
              ? [0, 1].map((row) => <Skeleton key={row} className="h-14 w-full" />)
              : data.markets.map((market) => (
                  <div
                    key={market.tokenId}
                    className="flex items-center gap-3 rounded-xl border border-hairline/70 bg-surface-2/40 p-3"
                  >
                    <TokenGlyph symbol={market.symbol} size={30} />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium text-ink">{market.symbol}</p>
                      <p className="tabular text-[11px] text-ink-faint">
                        {formatUsd(market.priceUsd)} · {formatPercent(market.utilizationPercent, 0)} utilized
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="tabular text-sm font-medium text-mint">
                        {formatPercent(market.supplyApr)}
                      </p>
                      <p className="text-[11px] text-ink-faint">supply APR</p>
                    </div>
                    <div className="w-px self-stretch bg-hairline" />
                    <div className="text-right">
                      <p className="tabular text-sm font-medium text-astra-200">
                        {formatPercent(market.borrowApr)}
                      </p>
                      <p className="text-[11px] text-ink-faint">borrow APR</p>
                    </div>
                  </div>
                ))}
          </div>

          {/* Cross-chain strip */}
          <div className="flex items-center gap-3 rounded-xl border border-hairline/70 bg-surface-2/30 px-3.5 py-3">
            <span className="size-2 shrink-0 animate-pulse rounded-full bg-glow" aria-hidden />
            <p className="text-xs leading-relaxed text-ink-muted">
              Positions stay in sync across{" "}
              <span className="text-ink">Ethereum</span> and{" "}
              <span className="text-ink">Arbitrum</span> over CCIP.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
