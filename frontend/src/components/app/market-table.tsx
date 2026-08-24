"use client";

import { formatPercent, formatToken, formatUsd } from "@/lib/format";
import {
  Badge,
  Button,
  EmptyState,
  Meter,
  Skeleton,
  TokenGlyph,
  cx,
} from "@/components/ui/primitives";
import type { Market, MarketOverview, UserPortfolio } from "@/lib/types";
import type { ActionRequest } from "./action-dialog";

/**
 * The markets table.
 *
 * On narrow viewports the same data renders as stacked cards rather than a
 * horizontally scrolling table — a rate table that has to be swiped sideways is
 * a table nobody reads.
 */
export function MarketTable({
  overview,
  portfolio,
  loading,
  onAction,
}: {
  overview: MarketOverview | undefined;
  portfolio: UserPortfolio | undefined;
  loading: boolean;
  onAction: (request: ActionRequest) => void;
}) {
  if (loading) {
    return (
      <div className="space-y-px p-4">
        {[0, 1].map((row) => (
          <Skeleton key={row} className="h-16 w-full" />
        ))}
      </div>
    );
  }

  const markets = overview?.markets ?? [];
  if (markets.length === 0) {
    return <EmptyState title="No markets" body="This deployment has no registered assets yet." />;
  }

  return (
    <>
      {/* Desktop */}
      <table className="hidden w-full text-left text-sm lg:table">
        <thead>
          <tr className="border-b border-hairline text-[11px] uppercase tracking-[0.12em] text-ink-faint">
            <th className="px-5 py-3 font-medium">Asset</th>
            <th className="px-5 py-3 text-right font-medium">Supplied</th>
            <th className="px-5 py-3 text-right font-medium">Collateral</th>
            <th className="px-5 py-3 text-right font-medium">Supply APR</th>
            <th className="px-5 py-3 text-right font-medium">Borrow APR</th>
            <th className="w-40 px-5 py-3 font-medium">Utilization</th>
            <th className="px-5 py-3 text-right font-medium">Your position</th>
            <th className="px-5 py-3" />
          </tr>
        </thead>
        <tbody className="divide-y divide-hairline">
          {markets.map((market) => {
            const position = portfolio?.positions.find((p) => p.tokenId === market.tokenId);
            return (
              <tr key={market.tokenId} className="group transition-colors hover:bg-surface-2/40">
                <td className="px-5 py-4">
                  <AssetCell market={market} />
                </td>
                <td className="tabular px-5 py-4 text-right">
                  <p className="text-ink">{formatUsd(market.totalLiquidityUsd)}</p>
                  <p className="text-xs text-ink-faint">
                    {formatToken(market.totalLiquidity, market.decimals)} {market.symbol}
                  </p>
                </td>
                <td className="tabular px-5 py-4 text-right">
                  <p className="text-ink">{formatUsd(market.totalCollateralUsd)}</p>
                  <p className="text-xs text-ink-faint">
                    {formatToken(market.totalCollateral, market.decimals)} {market.symbol}
                  </p>
                </td>
                <td className="tabular px-5 py-4 text-right font-medium text-mint">
                  {formatPercent(market.supplyApr)}
                </td>
                <td className="tabular px-5 py-4 text-right font-medium text-astra-200">
                  {formatPercent(market.borrowApr)}
                </td>
                <td className="px-5 py-4">
                  <UtilizationCell market={market} />
                </td>
                <td className="tabular px-5 py-4 text-right">
                  {position ? (
                    <PositionSummary position={position} symbol={market.symbol} decimals={market.decimals} />
                  ) : (
                    <span className="text-ink-faint">—</span>
                  )}
                </td>
                <td className="px-5 py-4">
                  <div className="flex justify-end gap-1.5 opacity-80 transition group-hover:opacity-100">
                    <Button size="sm" variant="secondary" onClick={() => onAction({ kind: "supply", tokenId: market.tokenId })}>
                      Supply
                    </Button>
                    <Button size="sm" onClick={() => onAction({ kind: "deposit-collateral", tokenId: market.tokenId })}>
                      Collateral
                    </Button>
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>

      {/* Mobile / tablet */}
      <ul className="divide-y divide-hairline lg:hidden">
        {markets.map((market) => {
          const position = portfolio?.positions.find((p) => p.tokenId === market.tokenId);
          return (
            <li key={market.tokenId} className="p-4">
              <div className="flex items-start justify-between gap-3">
                <AssetCell market={market} />
                <div className="text-right">
                  <p className="tabular text-sm text-ink">{formatUsd(market.totalLiquidityUsd)}</p>
                  <p className="text-[11px] text-ink-faint">supplied</p>
                </div>
              </div>

              <dl className="tabular mt-4 grid grid-cols-3 gap-3 text-xs">
                <div>
                  <dt className="text-ink-faint">Supply APR</dt>
                  <dd className="mt-0.5 font-medium text-mint">{formatPercent(market.supplyApr)}</dd>
                </div>
                <div>
                  <dt className="text-ink-faint">Borrow APR</dt>
                  <dd className="mt-0.5 font-medium text-astra-200">{formatPercent(market.borrowApr)}</dd>
                </div>
                <div>
                  <dt className="text-ink-faint">Utilization</dt>
                  <dd className="mt-0.5 font-medium text-ink-muted">
                    {formatPercent(market.utilizationPercent, 1)}
                  </dd>
                </div>
              </dl>

              {position &&
              (BigInt(position.liquidityDeposited) > 0n || BigInt(position.collateralDeposited) > 0n) ? (
                <div className="mt-3 rounded-lg border border-hairline bg-surface-2/40 p-2.5">
                  <PositionSummary position={position} symbol={market.symbol} decimals={market.decimals} />
                </div>
              ) : null}

              <div className="mt-3 flex gap-2">
                <Button
                  size="sm"
                  variant="secondary"
                  className="flex-1"
                  onClick={() => onAction({ kind: "supply", tokenId: market.tokenId })}
                >
                  Supply
                </Button>
                <Button
                  size="sm"
                  className="flex-1"
                  onClick={() => onAction({ kind: "deposit-collateral", tokenId: market.tokenId })}
                >
                  Collateral
                </Button>
              </div>
            </li>
          );
        })}
      </ul>
    </>
  );
}

function AssetCell({ market }: { market: Market }) {
  return (
    <div className="flex items-center gap-3">
      <TokenGlyph symbol={market.symbol} />
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <p className="font-medium text-ink">{market.symbol}</p>
          {!market.registered ? <Badge tone="warn">Unavailable</Badge> : null}
        </div>
        <p className="tabular text-xs text-ink-faint">{formatUsd(market.priceUsd)}</p>
      </div>
    </div>
  );
}

function UtilizationCell({ market }: { market: Market }) {
  const high = market.utilizationPercent >= 70;
  return (
    <div>
      <Meter value={market.utilizationPercent} tone={high ? "warn" : "accent"} markerAt={70} markerLabel="Kink at 70%" />
      <p className={cx("tabular mt-1.5 text-xs", high ? "text-amber" : "text-ink-faint")}>
        {formatPercent(market.utilizationPercent, 1)}
      </p>
    </div>
  );
}

function PositionSummary({
  position,
  symbol,
  decimals,
}: {
  position: UserPortfolio["positions"][number];
  symbol: string;
  decimals: number;
}) {
  const supplied = BigInt(position.liquidityDeposited);
  const collateral = BigInt(position.collateralDeposited);

  if (supplied === 0n && collateral === 0n) {
    return <span className="text-ink-faint">—</span>;
  }

  return (
    <div className="space-y-0.5 text-xs">
      {supplied > 0n ? (
        <p className="text-ink-muted">
          <span className="text-ink-faint">Supplied </span>
          {formatToken(supplied, decimals)} {symbol}
        </p>
      ) : null}
      {collateral > 0n ? (
        <p className="text-ink-muted">
          <span className="text-ink-faint">Collateral </span>
          {formatToken(collateral, decimals)} {symbol}
        </p>
      ) : null}
    </div>
  );
}
