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
import { formatPercent, formatToken, formatUsd } from "@/lib/format";
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

/**
 * The borrow flow.
 *
 * Ordered the way the decision actually gets made: how much can I borrow, what
 * is backing it, then the button. Collateral management sits on the same page
 * because "borrow more" and "add collateral" are the same intent from the
 * user's side.
 */
export default function BorrowPage() {
  const chain = useChainKey();
  const markets = useMarkets();
  const portfolio = usePortfolio();
  const [action, setAction] = useState<ActionRequest | null>(null);

  const summary = portfolio.data?.summary;
  const canBorrow = summary ? BigInt(summary.availableToBorrowUsd) > 0n : false;
  const collateralMarkets = markets.data?.markets.filter((m) => m.registered) ?? [];

  return (
    <>
      <PageHeader
        title="Borrow"
        description={`Draw a stablecoin loan against collateral posted on ${CHAINS[chain].name} or mirrored from another chain.`}
      />

      <ConnectGate
        title="Connect to borrow"
        body="Borrowing power is computed from the collateral your address has posted across every supported chain."
      >
        <div className="grid gap-6 lg:grid-cols-[1fr_1fr]">
          {/* ── Borrowing power ─────────────────────────────────────────── */}
          <Card glow>
            <CardHeader
              title="Borrowing power"
              subtitle={
                markets.data
                  ? `Up to ${formatPercent(markets.data.parameters.ltvPercent, 0)} of collateral value, on a ${markets.data.parameters.loanDurationDays}-day term`
                  : undefined
              }
            />
            <div className="p-5">
              {portfolio.isLoading || !summary || !markets.data ? (
                <Skeleton className="h-40 w-full" />
              ) : (
                <>
                  <Stat
                    label="Available to borrow"
                    value={formatUsd(summary.availableToBorrowUsd)}
                    hint={`of ${formatUsd(summary.borrowPowerUsd)} total borrowing power`}
                    tone="accent"
                    size="lg"
                  />

                  <div className="mt-6 border-t border-hairline pt-5">
                    <HealthGauge
                      summary={summary}
                      liquidationLtv={markets.data.parameters.liquidationThresholdPercent}
                    />
                  </div>

                  <Button
                    className="mt-6 w-full"
                    size="lg"
                    disabled={!canBorrow}
                    onClick={() =>
                      setAction({ kind: "borrow", tokenId: collateralMarkets[0]?.tokenId ?? 0 })
                    }
                  >
                    {canBorrow ? "Borrow stablecoin" : "Post collateral first"}
                  </Button>

                  {!canBorrow ? (
                    <p className="mt-3 text-center text-xs text-ink-faint">
                      Deposit collateral below to unlock borrowing power.
                    </p>
                  ) : null}
                </>
              )}
            </div>
          </Card>

          {/* ── Collateral ──────────────────────────────────────────────── */}
          <Card>
            <CardHeader
              title="Your collateral"
              subtitle="Locked while a loan is open; released on full repayment."
            />
            {markets.isLoading ? (
              <div className="p-4">
                <Skeleton className="h-32 w-full" />
              </div>
            ) : (
              <ul className="divide-y divide-hairline">
                {collateralMarkets.map((market) => {
                  const position = portfolio.data?.positions.find((p) => p.tokenId === market.tokenId);
                  const deposited = BigInt(position?.collateralDeposited ?? "0");
                  const wallet = BigInt(position?.walletBalance ?? "0");

                  return (
                    <li key={market.tokenId} className="flex flex-wrap items-center gap-4 px-5 py-4">
                      <TokenGlyph symbol={market.symbol} size={36} />
                      <div className="min-w-0 flex-1">
                        <p className="font-medium text-ink">{market.symbol}</p>
                        <p className="tabular text-xs text-ink-faint">
                          {formatToken(deposited, market.decimals)} posted ·{" "}
                          {formatUsd(position?.collateralUsd ?? "0")}
                        </p>
                        <p className="tabular text-xs text-ink-faint">
                          Wallet {formatToken(wallet, market.decimals)} {market.symbol}
                        </p>
                      </div>
                      <div className="flex gap-1.5">
                        <Button
                          size="sm"
                          variant="secondary"
                          disabled={deposited === 0n}
                          onClick={() =>
                            setAction({ kind: "withdraw-collateral", tokenId: market.tokenId })
                          }
                        >
                          Withdraw
                        </Button>
                        <Button
                          size="sm"
                          disabled={wallet === 0n}
                          onClick={() =>
                            setAction({ kind: "deposit-collateral", tokenId: market.tokenId })
                          }
                        >
                          Deposit
                        </Button>
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </Card>
        </div>

        {/* ── Open loans ─────────────────────────────────────────────────── */}
        <Card className="mt-6">
          <CardHeader
            title="Open loans"
            subtitle="Repay in part or in full — interest is always settled before principal."
            action={
              portfolio.data?.activeLoans.length ? (
                <Badge>{portfolio.data.activeLoans.length} open</Badge>
              ) : null
            }
          />
          {portfolio.data?.activeLoans.length ? (
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
              body="Once you borrow, each loan appears here with its live payoff amount and health factor."
            />
          )}
        </Card>
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
