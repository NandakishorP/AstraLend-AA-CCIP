"use client";

import { useState } from "react";
import { PageHeader } from "@/components/app/app-shell";
import { ActionDialog, type ActionRequest } from "@/components/app/action-dialog";
import { MarketTable } from "@/components/app/market-table";
import { RateCurve } from "@/components/app/rate-curve";
import { useChainKey } from "@/components/providers";
import { useMarkets, usePortfolio } from "@/lib/hooks";
import { CHAINS } from "@/lib/chains";
import { formatPercent, formatUsd } from "@/lib/format";
import { ApiError } from "@/lib/api";
import { Card, CardHeader, ErrorState, Skeleton, Stat } from "@/components/ui/primitives";

export default function MarketsPage() {
  const chain = useChainKey();
  const markets = useMarkets();
  const portfolio = usePortfolio();
  const [action, setAction] = useState<ActionRequest | null>(null);

  return (
    <>
      <PageHeader
        title="Markets"
        description={`Supply and collateral markets on ${CHAINS[chain].name}. Rates come from the on-chain interest rate model and refresh every few seconds.`}
      />

      {markets.isError ? (
        <Card>
          <ErrorState
            message={markets.error instanceof ApiError ? markets.error.message : "Could not load markets."}
            onRetry={() => void markets.refetch()}
          />
        </Card>
      ) : (
        <div className="space-y-6">
          <div className="grid gap-px overflow-hidden rounded-card border border-hairline bg-hairline sm:grid-cols-3">
            {[
              {
                label: "Total value locked",
                value: markets.data ? formatUsd(markets.data.totalValueLockedUsd) : undefined,
                hint: "Supplied liquidity plus posted collateral",
              },
              {
                label: "Total borrowed",
                value: markets.data ? formatUsd(markets.data.totalBorrowedUsd) : undefined,
                hint: "Outstanding principal and accrued interest",
              },
              {
                label: "LP token value",
                value: markets.data ? formatUsd(markets.data.lpTokenValueUsd) : undefined,
                hint: "USD backing per LP token",
              },
            ].map((tile) => (
              <div key={tile.label} className="bg-surface/80 px-5 py-4">
                {tile.value === undefined ? (
                  <>
                    <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
                      {tile.label}
                    </p>
                    <Skeleton className="mt-2 h-7 w-28" />
                  </>
                ) : (
                  <Stat label={tile.label} value={tile.value} hint={tile.hint} />
                )}
              </div>
            ))}
          </div>

          <Card>
            <CardHeader
              title="All markets"
              subtitle={
                markets.data
                  ? `${markets.data.markets.length} assets · average supply APR ${formatPercent(markets.data.averageSupplyApr)}`
                  : undefined
              }
            />
            <MarketTable
              overview={markets.data}
              portfolio={portfolio.data}
              loading={markets.isLoading}
              onAction={setAction}
            />
          </Card>

          {markets.data ? (
            <div className="grid gap-6 lg:grid-cols-2">
              <Card>
                <CardHeader
                  title="Interest rate model"
                  subtitle="Borrow APR against utilization, with each live market plotted on the curve."
                />
                <div className="p-5">
                  <RateCurve overview={markets.data} />
                </div>
              </Card>

              <Card>
                <CardHeader title="Protocol contracts" subtitle={CHAINS[chain].name} />
                <dl className="divide-y divide-hairline text-sm">
                  <ContractRow
                    label="Stablecoin"
                    symbol={markets.data.parameters.stableCoin.symbol}
                    address={markets.data.parameters.stableCoin.address}
                    chain={chain}
                  />
                  <ContractRow
                    label="LP token"
                    symbol={markets.data.parameters.lpToken.symbol}
                    address={markets.data.parameters.lpToken.address}
                    chain={chain}
                  />
                  {markets.data.markets.map((market) => (
                    <ContractRow
                      key={market.tokenId}
                      label={`Market ${market.tokenId}`}
                      symbol={market.symbol}
                      address={market.address}
                      chain={chain}
                    />
                  ))}
                </dl>
              </Card>
            </div>
          ) : null}
        </div>
      )}

      <ActionDialog
        request={action}
        overview={markets.data}
        portfolio={portfolio.data}
        onClose={() => setAction(null)}
      />
    </>
  );
}

function ContractRow({
  label,
  symbol,
  address,
  chain,
}: {
  label: string;
  symbol: string;
  address: string;
  chain: "eth" | "arb";
}) {
  return (
    <div className="flex items-center justify-between gap-4 px-5 py-3">
      <div>
        <dt className="text-ink">{label}</dt>
        <dd className="text-xs text-ink-faint">{symbol}</dd>
      </div>
      <a
        href={`${CHAINS[chain].explorer}/address/${address}`}
        target="_blank"
        rel="noreferrer"
        className="tabular truncate text-xs text-astra-200 hover:underline"
      >
        {address.slice(0, 10)}…{address.slice(-6)} ↗
      </a>
    </div>
  );
}
