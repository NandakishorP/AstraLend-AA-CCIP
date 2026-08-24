"use client";

import Link from "next/link";
import { useState } from "react";
import { useAccount } from "wagmi";
import { PageHeader } from "@/components/app/app-shell";
import { ActionDialog, type ActionRequest } from "@/components/app/action-dialog";
import { ConnectGate } from "@/components/app/connect-gate";
import { DemoPanel } from "@/components/app/demo-panel";
import { FaucetCard } from "@/components/app/faucet-card";
import { HealthGauge } from "@/components/app/health-gauge";
import { LoanRow } from "@/components/app/loan-row";
import { MarketTable } from "@/components/app/market-table";
import { TvlChart } from "@/components/app/tvl-chart";
import { CrossChainMonitor } from "@/components/app/cross-chain-monitor";
import { ProtocolStatsCard } from "@/components/app/protocol-stats";
import { useChainKey } from "@/components/providers";
import { useMarkets, usePortfolio } from "@/lib/hooks";
import { CHAINS } from "@/lib/chains";
import { formatEth, formatPercent, formatUsd } from "@/lib/format";
import {
  Badge,
  Button,
  Card,
  CardHeader,
  EmptyState,
  ErrorState,
  LinkButton,
  Skeleton,
  Stat,
} from "@/components/ui/primitives";
import { ApiError } from "@/lib/api";

export default function DashboardPage() {
  const chain = useChainKey();
  const { isConnected } = useAccount();
  const markets = useMarkets();
  const portfolio = usePortfolio();
  const [action, setAction] = useState<ActionRequest | null>(null);

  return (
    <>
      <PageHeader
        title="Dashboard"
        description={`Your position on ${CHAINS[chain].name}, alongside live protocol markets.`}
        action={
          <div className="flex gap-2">
            <LinkButton href="/app/borrow" variant="secondary" size="sm">
              Borrow
            </LinkButton>
            <LinkButton href="/app/markets" size="sm">
              All markets
            </LinkButton>
          </div>
        }
      />

      {markets.isError ? (
        <Card className="mb-6">
          <ErrorState
            message={
              markets.error instanceof ApiError
                ? markets.error.message
                : "Could not load protocol data."
            }
            onRetry={() => void markets.refetch()}
          />
        </Card>
      ) : null}

      {/* ── Protocol strip ──────────────────────────────────────────────── */}
      <div className="mb-6 grid gap-px overflow-hidden rounded-card border border-hairline bg-hairline sm:grid-cols-2 lg:grid-cols-4">
        <MetricTile
          label="Total value locked"
          value={markets.data ? formatUsd(markets.data.totalValueLockedUsd) : undefined}
          hint={markets.data ? `${markets.data.markets.length} markets on ${CHAINS[chain].shortName}` : undefined}
        />
        <MetricTile
          label="Total borrowed"
          value={markets.data ? formatUsd(markets.data.totalBorrowedUsd) : undefined}
          hint="Outstanding stablecoin debt"
        />
        <MetricTile
          label="Average supply APR"
          value={markets.data ? formatPercent(markets.data.averageSupplyApr) : undefined}
          hint="Liquidity-weighted across markets"
        />
        <MetricTile
          label="Collateral posted"
          value={markets.data ? formatUsd(markets.data.totalCollateralUsd) : undefined}
          hint={
            markets.data
              ? `${formatPercent(markets.data.parameters.ltvPercent, 0)} max LTV`
              : undefined
          }
        />
      </div>

      <ConnectGate>
        {/* `items-start` keeps each column's cards at their natural height —
            without it the shorter column stretches to match the taller one. */}
        <div className="grid items-start gap-6 lg:grid-cols-[1.35fr_1fr]">
          {/* ── Left column ───────────────────────────────────────────── */}
          <div className="space-y-6">
            <Card glow>
              <CardHeader
                title="Your position"
                subtitle={portfolio.data ? `Snapshot from ${new Date(portfolio.data.snapshotAt).toLocaleTimeString()}` : undefined}
                action={
                  portfolio.data ? (
                    <Badge tone={portfolio.data.summary.riskLevel === "none" ? "neutral" : "accent"}>
                      Net {formatUsd(portfolio.data.summary.netWorthUsd)}
                    </Badge>
                  ) : null
                }
              />
              <div className="p-5">
                {portfolio.isLoading ? (
                  <Skeleton className="h-32 w-full" />
                ) : portfolio.isError ? (
                  <ErrorState
                    message={
                      portfolio.error instanceof ApiError
                        ? portfolio.error.message
                        : "Could not load your portfolio."
                    }
                    onRetry={() => void portfolio.refetch()}
                  />
                ) : portfolio.data && markets.data ? (
                  <>
                    <div className="grid grid-cols-2 gap-5 sm:grid-cols-4">
                      <Stat label="Supplied" value={formatUsd(portfolio.data.summary.suppliedUsd)} size="sm" />
                      <Stat label="Collateral" value={formatUsd(portfolio.data.summary.collateralUsd)} size="sm" />
                      <Stat label="Debt" value={formatUsd(portfolio.data.summary.debtUsd)} size="sm" />
                      <Stat
                        label="Available"
                        value={formatUsd(portfolio.data.summary.availableToBorrowUsd)}
                        tone="accent"
                        size="sm"
                      />
                    </div>

                    <div className="mt-6 border-t border-hairline pt-5">
                      <HealthGauge
                        summary={portfolio.data.summary}
                        liquidationLtv={markets.data.parameters.liquidationThresholdPercent}
                      />
                    </div>
                  </>
                ) : null}
              </div>
            </Card>

            <Card>
              <CardHeader
                title="Active loans"
                subtitle="Interest accrues continuously; repay any amount at any time."
                action={
                  portfolio.data?.activeLoans.length ? (
                    <Badge>{portfolio.data.activeLoans.length} open</Badge>
                  ) : null
                }
              />
              {portfolio.isLoading ? (
                <div className="space-y-px p-4">
                  <Skeleton className="h-20 w-full" />
                </div>
              ) : portfolio.data?.activeLoans.length ? (
                <ul className="divide-y divide-hairline">
                  {portfolio.data.activeLoans.map((loan) => (
                    <LoanRow
                      key={`${loan.tokenId}-${loan.loanId}`}
                      loan={loan}
                      stableSymbol={portfolio.data.stableCoinSymbol}
                      stableDecimals={portfolio.data.stableCoinDecimals}
                      collateralDecimals={
                        markets.data?.markets.find((m) => m.tokenId === loan.tokenId)?.decimals ?? 18
                      }
                      onRepay={() => setAction({ kind: "repay", tokenId: loan.tokenId, loan })}
                    />
                  ))}
                </ul>
              ) : (
                <EmptyState
                  title="No open loans"
                  body="Post collateral and draw a stablecoin loan against it — up to 75% of its value."
                  action={
                    <LinkButton href="/app/borrow" size="sm" className="mt-1">
                      Borrow
                    </LinkButton>
                  }
                />
              )}
            </Card>
          </div>

          {/* ── Right column ──────────────────────────────────────────── */}
          <div className="space-y-6">
            <Card>
              <CardHeader title="Wallet" subtitle={`Balances on ${CHAINS[chain].name}`} />
              <div className="divide-y divide-hairline">
                {portfolio.isLoading ? (
                  <div className="p-4">
                    <Skeleton className="h-24 w-full" />
                  </div>
                ) : portfolio.data ? (
                  <>
                    <BalanceRow
                      label="Native gas"
                      value={formatEth(portfolio.data.nativeBalance)}
                      hint="Covers gas and CCIP fees"
                    />
                    <BalanceRow
                      label={portfolio.data.stableCoinSymbol}
                      value={`${(
                        Number(portfolio.data.stableCoinBalance) /
                        10 ** portfolio.data.stableCoinDecimals
                      ).toLocaleString("en-US", { maximumFractionDigits: 2 })}`}
                      hint="Borrowed and repaid in this asset"
                    />
                    <BalanceRow
                      label="LP tokens"
                      value={(Number(portfolio.data.lpTokenBalance) / 1e18).toLocaleString("en-US", {
                        maximumFractionDigits: 4,
                      })}
                      hint={`Worth ${formatUsd(portfolio.data.lpTokenValueUsd)}`}
                    />
                  </>
                ) : null}
              </div>
            </Card>

            <FaucetCard />

            <DemoPanel />

            <Card>
              <CardHeader title="Quick actions" />
              <div className="grid grid-cols-2 gap-2 p-4">
                {markets.data?.markets.slice(0, 1).map((market) => (
                  <Button
                    key="supply"
                    variant="secondary"
                    size="sm"
                    disabled={!isConnected}
                    onClick={() => setAction({ kind: "supply", tokenId: market.tokenId })}
                  >
                    Supply {market.symbol}
                  </Button>
                ))}
                {markets.data?.markets.slice(0, 1).map((market) => (
                  <Button
                    key="collateral"
                    variant="secondary"
                    size="sm"
                    disabled={!isConnected}
                    onClick={() => setAction({ kind: "deposit-collateral", tokenId: market.tokenId })}
                  >
                    Add collateral
                  </Button>
                ))}
                <LinkButton href="/app/borrow" variant="secondary" size="sm">
                  Borrow
                </LinkButton>
                <LinkButton href="/app/activity" variant="secondary" size="sm">
                  Activity
                </LinkButton>
              </div>
            </Card>

            {markets.data ? <ParametersCard parameters={markets.data.parameters} /> : null}
          </div>
        </div>
      </ConnectGate>

      {/* ── Indexed history ──────────────────────────────────────────────
          Everything below reads the backend's database rather than the chain:
          the chain can only report the present. */}
      <div className="mt-6 grid items-start gap-6 lg:grid-cols-[1.5fr_1fr]">
        <div className="space-y-6">
          <Card glow className="pt-4">
            <TvlChart />
          </Card>
          <CrossChainMonitor />
        </div>
        <ProtocolStatsCard />
      </div>

      {/* ── Markets ──────────────────────────────────────────────────── */}
      <Card className="mt-6">
        <CardHeader
          title="Markets"
          subtitle="Rates follow the on-chain kinked model — steepening past 70% utilization."
          action={
            <Link href="/app/markets" className="text-xs text-astra-200 hover:underline">
              View all →
            </Link>
          }
        />
        <MarketTable
          overview={markets.data}
          portfolio={portfolio.data}
          loading={markets.isLoading}
          onAction={setAction}
        />
      </Card>

      <ActionDialog
        request={action}
        overview={markets.data}
        portfolio={portfolio.data}
        onClose={() => setAction(null)}
      />
    </>
  );
}

// ─── Pieces ───────────────────────────────────────────────────────────────────

function MetricTile({
  label,
  value,
  hint,
}: {
  label: string;
  value: string | undefined;
  hint?: string;
}) {
  return (
    <div className="bg-surface/80 px-5 py-4 backdrop-blur">
      {value === undefined ? (
        <>
          <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">{label}</p>
          <Skeleton className="mt-2 h-7 w-28" />
        </>
      ) : (
        <Stat label={label} value={value} hint={hint} size="md" />
      )}
    </div>
  );
}

function BalanceRow({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <div className="flex items-center justify-between gap-4 px-5 py-3.5">
      <div>
        <p className="text-sm text-ink">{label}</p>
        <p className="text-xs text-ink-faint">{hint}</p>
      </div>
      <p className="tabular font-display text-sm font-semibold text-ink">{value}</p>
    </div>
  );
}

function ParametersCard({
  parameters,
}: {
  parameters: NonNullable<ReturnType<typeof useMarkets>["data"]>["parameters"];
}) {
  const rows: [string, string][] = [
    ["Max LTV", formatPercent(parameters.ltvPercent, 0)],
    ["Liquidation threshold", formatPercent(parameters.liquidationThresholdPercent, 0)],
    ["Liquidation penalty", formatPercent(parameters.liquidationPenaltyPercent, 0)],
    ["Loan term", `${parameters.loanDurationDays} days`],
    ["Rate kink", formatPercent(parameters.kinkPercent, 0)],
  ];

  return (
    <Card>
      <CardHeader title="Risk parameters" subtitle="Read live from the lending pool" />
      <dl className="divide-y divide-hairline text-sm">
        {rows.map(([label, value]) => (
          <div key={label} className="flex items-center justify-between px-5 py-2.5">
            <dt className="text-ink-faint">{label}</dt>
            <dd className="tabular font-medium text-ink-muted">{value}</dd>
          </div>
        ))}
      </dl>
    </Card>
  );
}
