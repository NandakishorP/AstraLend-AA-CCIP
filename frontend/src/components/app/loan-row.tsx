"use client";

import { formatDueIn, formatToken, formatUsd, healthTone } from "@/lib/format";
import { Badge, Button, Meter, TokenGlyph, cx } from "@/components/ui/primitives";
import type { UserLoan } from "@/lib/types";

/**
 * One open loan.
 *
 * The row leads with what the borrower owes right now — principal plus accrued
 * interest — because that is the number they act on. Principal alone is a
 * historical detail and sits in the secondary line.
 */
export function LoanRow({
  loan,
  stableSymbol,
  stableDecimals,
  collateralDecimals,
  onRepay,
}: {
  loan: UserLoan;
  stableSymbol: string;
  stableDecimals: number;
  collateralDecimals: number;
  onRepay: () => void;
}) {
  const { tone, label } = healthTone(loan.healthFactor);
  // A cross-chain loan records its locked collateral through the mirroring
  // path, which can leave the figure as dust. The backend reports `null` rather
  // than a nonsense ratio in that case, and the row defers to the account-level
  // health shown above instead of inventing a per-loan number.
  const hasLoanLevelRisk = loan.healthFactor !== null;

  return (
    <li className="p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex min-w-0 items-start gap-3">
          <TokenGlyph symbol={loan.tokenSymbol} size={36} />
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <p className="font-medium text-ink">
                Loan #{loan.loanId} · {loan.tokenSymbol} collateral
              </p>
              {hasLoanLevelRisk ? (
                <Badge tone={tone === "safe" ? "safe" : tone === "warn" ? "warn" : "danger"}>
                  {label}
                </Badge>
              ) : null}
              {loan.isOverdue ? <Badge tone="danger">Overdue</Badge> : null}
              {loan.isLiquidated ? <Badge tone="danger">Liquidated</Badge> : null}
            </div>
            <p className="tabular mt-1 text-xs text-ink-faint">
              {hasLoanLevelRisk
                ? `${formatToken(loan.collateralUsed, collateralDecimals)} ${loan.tokenSymbol} locked · ${formatUsd(loan.collateralUsedUsd)} · `
                : "collateral held across chains · "}
              {formatDueIn(loan.daysUntilDue)}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-4">
          <div className="text-right">
            <p className="tabular font-display text-lg font-semibold text-ink">
              {formatToken(loan.currentDebt, stableDecimals, 2)} {stableSymbol}
            </p>
            <p className="tabular text-xs text-ink-faint">
              {formatToken(loan.principalAmount, stableDecimals, 2)} principal +{" "}
              <span className="text-amber">
                {formatToken(loan.accruedInterest, stableDecimals, 2)} interest
              </span>
            </p>
          </div>
          <Button size="sm" onClick={onRepay}>
            Repay
          </Button>
        </div>
      </div>

      <div className={cx("mt-4", !hasLoanLevelRisk && "hidden")}>
        <Meter
          value={loan.ltvPercent}
          max={100}
          markerAt={80}
          markerLabel="Liquidation at 80% LTV"
          tone={loan.ltvPercent >= 80 ? "danger" : loan.ltvPercent > 68 ? "warn" : "accent"}
        />
        <div className="tabular mt-1.5 flex justify-between text-[11px]">
          <span className={cx(loan.ltvPercent >= 80 ? "text-rose" : "text-ink-faint")}>
            LTV {loan.ltvPercent.toFixed(1)}%
          </span>
          <span className="text-ink-faint">
            Health {loan.healthFactor === null ? "—" : loan.healthFactor.toFixed(2)}
          </span>
        </div>
      </div>
    </li>
  );
}
