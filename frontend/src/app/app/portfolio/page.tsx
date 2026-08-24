"use client";

import { useState } from "react";
import { PageHeader } from "@/components/app/app-shell";
import { ActionDialog, type ActionRequest } from "@/components/app/action-dialog";
import { ConnectGate } from "@/components/app/connect-gate";
import { HealthGauge } from "@/components/app/health-gauge";
import { LoanRow } from "@/components/app/loan-row";
import { useChainKey } from "@/components/providers";
import { useMarkets, usePortfolio } from "@/lib/hooks";
import { CHAINS } from "@/lib/chains";
import { formatDueIn, formatPercent, formatToken, formatUsd } from "@/lib/format";
import {
  Badge,
  Button,
  Card,
  CardHeader,
  EmptyState,
  Skeleton,
  Stat,
  TokenGlyph,
} from "@/components/ui/primitives";

export default function PortfolioPage() {
  const chain = useChainKey();
  const markets = useMarkets();
  const portfolio = usePortfolio();
  const [action, setAction] = useState<ActionRequest | null>(null);

  const summary = portfolio.data?.summary;

  return (
    <>
      <PageHeader
        title="Portfolio"
        description={`Every position this address holds on ${CHAINS[chain].name}, valued from Chainlink price feeds.`}
      />

      <ConnectGate title="Connect to see your portfolio">
        {portfolio.isLoading || !portfolio.data || !markets.data ? (
          <div className="space-y-6">
            <Skeleton className="h-40 w-full" />
            <Skeleton className="h-64 w-full" />
          </div>
        ) : (
          <div className="space-y-6">
            {/* ── Summary ─────────────────────────────────────────────── */}
            <div className="grid gap-6 lg:grid-cols-[1fr_1.2fr]">
              <Card glow className="p-5">
                <Stat
                  label="Net worth"
                  value={formatUsd(summary!.netWorthUsd)}
                  hint="Supplied plus collateral, less outstanding debt"
                  size="lg"
                />
                <div className="mt-6 grid grid-cols-3 gap-4 border-t border-hairline pt-5">
                  <Stat label="Supplied" value={formatUsd(summary!.suppliedUsd)} size="sm" />
                  <Stat label="Collateral" value={formatUsd(summary!.collateralUsd)} size="sm" />
                  <Stat label="Debt" value={formatUsd(summary!.debtUsd)} size="sm" tone={BigInt(summary!.debtUsd) > 0n ? "warn" : "default"} />
                </div>
              </Card>

              <Card className="flex items-center p-5">
                <HealthGauge
                  summary={summary!}
                  liquidationLtv={markets.data.parameters.liquidationThresholdPercent}
                />
              </Card>
            </div>

            {/* ── Positions ───────────────────────────────────────────── */}
            <Card>
              <CardHeader
                title="Asset positions"
                subtitle="Supplied liquidity earns yield; collateral backs loans. They are tracked separately."
              />
              <ul className="divide-y divide-hairline">
                {portfolio.data.positions.map((position) => {
                  const market = markets.data!.markets.find((m) => m.tokenId === position.tokenId);
                  const supplied = BigInt(position.liquidityDeposited);
                  const collateral = BigInt(position.collateralDeposited);
                  const wallet = BigInt(position.walletBalance);

                  return (
                    <li key={position.tokenId} className="px-5 py-4">
                      <div className="flex flex-wrap items-center justify-between gap-4">
                        <div className="flex items-center gap-3">
                          <TokenGlyph symbol={position.symbol} size={38} />
                          <div>
                            <p className="font-medium text-ink">{position.symbol}</p>
                            <p className="tabular text-xs text-ink-faint">
                              {formatUsd(position.priceUsd)} ·{" "}
                              {market ? `${formatPercent(market.supplyApr)} supply APR` : ""}
                            </p>
                          </div>
                        </div>

                        <div className="flex flex-wrap gap-1.5">
                          <Button
                            size="sm"
                            variant="secondary"
                            disabled={wallet === 0n}
                            onClick={() => setAction({ kind: "supply", tokenId: position.tokenId })}
                          >
                            Supply
                          </Button>
                          <Button
                            size="sm"
                            variant="secondary"
                            disabled={supplied === 0n}
                            onClick={() =>
                              setAction({ kind: "withdraw-supply", tokenId: position.tokenId })
                            }
                          >
                            Withdraw
                          </Button>
                          <Button
                            size="sm"
                            variant="secondary"
                            disabled={wallet === 0n}
                            onClick={() =>
                              setAction({ kind: "deposit-collateral", tokenId: position.tokenId })
                            }
                          >
                            Add collateral
                          </Button>
                        </div>
                      </div>

                      <dl className="tabular mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
                        <PositionCell
                          label="Supplied"
                          primary={`${formatToken(supplied, position.decimals)} ${position.symbol}`}
                          secondary={formatUsd(position.liquidityUsd)}
                        />
                        <PositionCell
                          label="Collateral"
                          primary={`${formatToken(collateral, position.decimals)} ${position.symbol}`}
                          secondary={formatUsd(position.collateralUsd)}
                        />
                        <PositionCell
                          label="In wallet"
                          primary={`${formatToken(wallet, position.decimals)} ${position.symbol}`}
                          secondary={formatUsd(position.walletUsd)}
                        />
                        <PositionCell
                          label="Borrow APR"
                          primary={market ? formatPercent(market.borrowApr) : "—"}
                          secondary={market ? `${formatPercent(market.utilizationPercent, 1)} utilized` : ""}
                        />
                      </dl>
                    </li>
                  );
                })}
              </ul>
            </Card>

            {/* ── LP position ─────────────────────────────────────────── */}
            <div className="grid gap-6 lg:grid-cols-2">
              <Card>
                <CardHeader title="LP position" subtitle="Your claim on the pool" />
                <div className="grid grid-cols-2 gap-5 p-5">
                  <Stat
                    label="LP tokens"
                    value={formatToken(portfolio.data.lpTokenBalance, 18)}
                    hint={markets.data.parameters.lpToken.symbol}
                    size="sm"
                  />
                  <Stat
                    label="Value"
                    value={formatUsd(portfolio.data.lpTokenValueUsd)}
                    hint={`${formatUsd(markets.data.lpTokenValueUsd)} per token`}
                    size="sm"
                  />
                </div>
              </Card>

              <Card>
                <CardHeader title="Stablecoin" subtitle="Borrowed and repaid in this asset" />
                <div className="grid grid-cols-2 gap-5 p-5">
                  <Stat
                    label="Wallet balance"
                    value={`${formatToken(portfolio.data.stableCoinBalance, portfolio.data.stableCoinDecimals, 2)} ${portfolio.data.stableCoinSymbol}`}
                    size="sm"
                  />
                  <Stat
                    label="Outstanding debt"
                    value={formatUsd(summary!.debtUsd)}
                    tone={BigInt(summary!.debtUsd) > 0n ? "warn" : "default"}
                    size="sm"
                  />
                </div>
              </Card>
            </div>

            {/* ── Loans ───────────────────────────────────────────────── */}
            <Card>
              <CardHeader
                title="Loans"
                action={
                  portfolio.data.closedLoans.length ? (
                    <Badge>{portfolio.data.closedLoans.length} settled</Badge>
                  ) : null
                }
              />
              {portfolio.data.activeLoans.length ? (
                <ul className="divide-y divide-hairline">
                  {portfolio.data.activeLoans.map((loan) => (
                    <LoanRow
                      key={`${loan.tokenId}-${loan.loanId}`}
                      loan={loan}
                      stableSymbol={portfolio.data.stableCoinSymbol}
                      stableDecimals={portfolio.data.stableCoinDecimals}
                      collateralDecimals={
                        markets.data!.markets.find((m) => m.tokenId === loan.tokenId)?.decimals ?? 18
                      }
                      onRepay={() => setAction({ kind: "repay", tokenId: loan.tokenId, loan })}
                    />
                  ))}
                </ul>
              ) : (
                <EmptyState title="No open loans" body="Borrow against your collateral to open one." />
              )}

              {portfolio.data.closedLoans.length ? (
                <div className="border-t border-hairline">
                  <p className="px-5 pb-2 pt-4 text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
                    Settled
                  </p>
                  <ul className="divide-y divide-hairline">
                    {portfolio.data.closedLoans.map((loan) => (
                      <li
                        key={`${loan.tokenId}-${loan.loanId}`}
                        className="flex items-center justify-between gap-4 px-5 py-3"
                      >
                        <div className="flex items-center gap-3">
                          <TokenGlyph symbol={loan.tokenSymbol} size={26} />
                          <div>
                            <p className="text-sm text-ink-muted">Loan #{loan.loanId}</p>
                            <p className="tabular text-xs text-ink-faint">
                              {formatToken(loan.principalAmount, portfolio.data.stableCoinDecimals, 2)}{" "}
                              {portfolio.data.stableCoinSymbol} borrowed · {formatDueIn(loan.daysUntilDue)}
                            </p>
                          </div>
                        </div>
                        <Badge tone={loan.isLiquidated ? "danger" : "safe"}>
                          {loan.isLiquidated ? "Liquidated" : "Repaid"}
                        </Badge>
                      </li>
                    ))}
                  </ul>
                </div>
              ) : null}
            </Card>
          </div>
        )}
      </ConnectGate>

      <ActionDialog
        request={action}
        overview={markets.data}
        portfolio={portfolio.data}
        onClose={() => setAction(null)}
      />
    </>
  );
}

function PositionCell({
  label,
  primary,
  secondary,
}: {
  label: string;
  primary: string;
  secondary: string;
}) {
  return (
    <div>
      <dt className="text-[11px] uppercase tracking-[0.12em] text-ink-faint">{label}</dt>
      <dd className="mt-1 text-sm text-ink">{primary}</dd>
      <dd className="text-xs text-ink-faint">{secondary}</dd>
    </div>
  );
}
