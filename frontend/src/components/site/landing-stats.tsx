"use client";

import { useMarkets } from "@/lib/hooks";
import { formatPercent, formatUsd } from "@/lib/format";
import { Skeleton } from "@/components/ui/primitives";

/**
 * The live figures under the hero.
 *
 * These read the hub chain regardless of what the visitor's wallet is on — the
 * landing page is marketing surface, and Ethereum holds the global state.
 */
export function LandingStats() {
  const { data, isLoading, isError } = useMarkets("eth");

  const items = [
    { label: "Total value locked", value: data ? formatUsd(data.totalValueLockedUsd) : null },
    { label: "Total borrowed", value: data ? formatUsd(data.totalBorrowedUsd) : null },
    { label: "Collateral posted", value: data ? formatUsd(data.totalCollateralUsd) : null },
    { label: "Max LTV", value: data ? formatPercent(data.parameters.ltvPercent, 0) : null },
  ];

  return (
    <dl className="grid grid-cols-2 gap-px overflow-hidden rounded-card border border-hairline bg-hairline sm:grid-cols-4">
      {items.map((item) => (
        <div key={item.label} className="bg-surface/80 px-5 py-4 backdrop-blur">
          <dt className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
            {item.label}
          </dt>
          <dd className="tabular mt-1.5 font-display text-xl font-semibold text-ink">
            {isLoading ? (
              <Skeleton className="h-6 w-24" />
            ) : isError ? (
              <span className="text-base text-ink-faint">—</span>
            ) : (
              item.value
            )}
          </dd>
        </div>
      ))}
    </dl>
  );
}
