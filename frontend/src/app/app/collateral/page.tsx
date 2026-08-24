"use client";

import { PageHeader } from "@/components/app/app-shell";
import { ConnectGate } from "@/components/app/connect-gate";
import { useRwaHolding, useRwaLien, useRwaNav, useRwaStatus } from "@/lib/hooks";
import { formatUsdNumber } from "@/lib/format";
import {
  Badge,
  Card,
  CardHeader,
  EmptyState,
  ErrorState,
  Meter,
  Skeleton,
  Stat,
  cx,
} from "@/components/ui/primitives";

/**
 * Encumbered real-world collateral.
 *
 * The page exists to make one thing visible: the tokens never move. A borrower
 * posting collateral here sees their balance stay exactly where it was, with a
 * charge recorded against part of it. That is the difference between this and
 * every other lending venue, and it is only legible if balance and encumbrance
 * are shown side by side.
 */
export default function CollateralPage() {
  const status = useRwaStatus();
  const available = status.data?.available ?? false;

  const nav = useRwaNav(available);
  const holding = useRwaHolding(available);
  const lien = useRwaLien(available);

  return (
    <>
      <PageHeader
        title="Real-world collateral"
        description="Pledge a tokenised Treasury bill without transferring it. The instrument stays in your wallet; only a charge is recorded."
      />

      {status.isLoading ? (
        <Skeleton className="h-40 w-full" />
      ) : !available ? (
        <Card>
          <EmptyState
            title="RWA module not deployed"
            body="This deployment has no real-world asset module wired. Deploy src/rwa and set the RWA_* addresses in the backend environment."
          />
        </Card>
      ) : (
        <ConnectGate title="Connect to see your holding">
          <div className="space-y-4">
            {/* ─── The instrument ─────────────────────────────────────────── */}
            <Card>
              <CardHeader
                title={nav.data?.description ?? "Instrument"}
                subtitle="Valued by accretion toward par, not by an attested price"
                action={
                  nav.data ? (
                    <Badge tone={nav.data.isMatured ? "warn" : "safe"}>
                      {nav.data.isMatured
                        ? "Matured"
                        : `${nav.data.daysToMaturity}d to maturity`}
                    </Badge>
                  ) : null
                }
              />

              {nav.isLoading ? (
                <div className="p-4">
                  <Skeleton className="h-24 w-full" />
                </div>
              ) : nav.isError ? (
                <ErrorState
                  message="Could not read the instrument's value."
                  onRetry={() => void nav.refetch()}
                />
              ) : nav.data ? (
                <div className="space-y-4 p-5">
                  <div className="grid gap-4 sm:grid-cols-3">
                    <Stat label="NAV per token" value={`$${nav.data.navPerToken}`} />
                    <Stat label="Issue price" value={`$${nav.data.issuePrice}`} />
                    <Stat label="Face value at maturity" value={`$${nav.data.faceValue}`} />
                  </div>

                  <div>
                    <div className="mb-1.5 flex items-baseline justify-between">
                      <span className="text-xs text-ink-faint">Accretion to par</span>
                      <span className="tabular text-xs text-ink-muted">
                        {(nav.data.accretionProgress * 100).toFixed(1)}%
                      </span>
                    </div>
                    <Meter value={nav.data.accretionProgress * 100} />
                  </div>

                  {/* Worth stating plainly — it is a property no attested feed has. */}
                  <p className="text-xs text-ink-faint">
                    A bill has no market price to report. Its value is a
                    deterministic function of time, recomputed on every read, so
                    it can never go stale.
                  </p>
                </div>
              ) : null}
            </Card>

            {/* ─── The holding ────────────────────────────────────────────── */}
            <Card>
              <CardHeader
                title="Your holding"
                subtitle="Pledging does not move these tokens"
                action={
                  holding.data ? (
                    <Badge tone={holding.data.eligible ? "safe" : "danger"}>
                      {holding.data.eligible ? "Eligible holder" : "Not eligible"}
                    </Badge>
                  ) : null
                }
              />

              {holding.isLoading ? (
                <div className="p-4">
                  <Skeleton className="h-28 w-full" />
                </div>
              ) : holding.isError ? (
                <ErrorState
                  message="Could not read your holding."
                  onRetry={() => void holding.refetch()}
                />
              ) : holding.data ? (
                <div className="space-y-4 p-5">
                  <div className="grid gap-4 sm:grid-cols-3">
                    <Stat
                      label={`Balance (${holding.data.symbol})`}
                      value={holding.data.balance}
                      hint={formatUsdNumber(Number(holding.data.balanceUsd))}
                    />
                    <Stat
                      label="Encumbered"
                      value={holding.data.encumbered}
                      hint={formatUsdNumber(Number(holding.data.encumberedUsd))}
                      tone="warn"
                    />
                    <Stat
                      label="Free to transfer"
                      value={holding.data.free}
                      hint={formatUsdNumber(Number(holding.data.freeUsd))}
                      tone="safe"
                    />
                  </div>

                  <EncumbranceBar
                    encumbered={Number(holding.data.encumbered)}
                    total={Number(holding.data.balance)}
                  />
                </div>
              ) : null}
            </Card>

            {/* ─── The register ───────────────────────────────────────────── */}
            <Card>
              <CardHeader
                title="Register of charges"
                subtitle="The public record that makes the pledge good against third parties"
              />

              {lien.isLoading ? (
                <div className="p-4">
                  <Skeleton className="h-20 w-full" />
                </div>
              ) : lien.data ? (
                <dl className="divide-y divide-hairline">
                  <Row label="Status">
                    <Badge
                      tone={
                        lien.data.foreclosed
                          ? "danger"
                          : lien.data.active
                            ? "warn"
                            : "neutral"
                      }
                    >
                      {lien.data.foreclosed
                        ? "Foreclosed"
                        : lien.data.active
                          ? "Charge active"
                          : "Released"}
                    </Badge>
                  </Row>
                  <Row label="Amount charged">
                    <span className="tabular text-sm text-ink">{lien.data.amount}</span>
                  </Row>
                  <Row label="Perfected">
                    <span className="tabular text-sm text-ink-muted">
                      {new Date(lien.data.perfectedAt * 1000).toLocaleString()}
                    </span>
                  </Row>
                  <Row label="Lien ID">
                    <span className="tabular text-xs text-ink-faint">
                      {lien.data.lienId.slice(0, 18)}…
                    </span>
                  </Row>
                </dl>
              ) : (
                <EmptyState
                  title="No charge recorded"
                  body="Post this instrument as collateral and the charge will appear here, timestamped and publicly verifiable."
                />
              )}
            </Card>
          </div>
        </ConnectGate>
      )}
    </>
  );
}

/**
 * A single bar split into pledged and free.
 *
 * More useful than two separate numbers, because the thing worth seeing is that
 * both segments belong to one balance that never left the wallet.
 */
function EncumbranceBar({ encumbered, total }: { encumbered: number; total: number }) {
  if (total <= 0) return null;
  const pledgedPct = Math.min(100, (encumbered / total) * 100);

  return (
    <div>
      <div className="flex h-2.5 w-full overflow-hidden rounded-full bg-surface-2">
        <div
          className="bg-amber transition-all"
          style={{ width: `${pledgedPct}%` }}
          aria-label="Encumbered"
        />
        <div className="flex-1 bg-mint/60" aria-label="Free" />
      </div>
      <div className="mt-2 flex justify-between text-xs">
        <span className="text-amber">{pledgedPct.toFixed(1)}% pledged</span>
        <span className="text-ink-faint">
          held in your wallet throughout — nothing was transferred
        </span>
      </div>
    </div>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className={cx("flex items-center justify-between px-5 py-3.5")}>
      <dt className="text-sm text-ink-muted">{label}</dt>
      <dd>{children}</dd>
    </div>
  );
}
