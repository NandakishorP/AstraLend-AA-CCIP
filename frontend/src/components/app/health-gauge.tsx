"use client";

import { formatPercent, formatUsd, healthTone } from "@/lib/format";
import { Badge, Meter } from "@/components/ui/primitives";
import type { AccountSummary } from "@/lib/types";

/**
 * Account-level risk readout.
 *
 * The dial is capped at a health factor of 3: past that the position is
 * comfortably safe and the exact value stops carrying information, while the
 * region between 1.0 and 1.5 is where a borrower actually needs resolution.
 */
export function HealthGauge({
  summary,
  liquidationLtv,
}: {
  summary: AccountSummary;
  liquidationLtv: number;
}) {
  const health = summary.healthFactor;
  const { tone, label } = healthTone(health);
  const capped = health === null ? 0 : Math.min(health, 3);
  const sweep = health === null ? 0 : capped / 3;

  const stroke = {
    neutral: "#656d92",
    safe: "#34d399",
    warn: "#fbbf24",
    danger: "#fb7185",
  }[tone];

  const RADIUS = 52;
  const CIRCUMFERENCE = Math.PI * RADIUS; // Half circle.

  return (
    <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-center sm:gap-6">
      <div className="relative shrink-0">
        <svg viewBox="0 0 128 74" className="w-36" aria-hidden>
          <path
            d="M12 66 A52 52 0 0 1 116 66"
            fill="none"
            stroke="#1d2338"
            strokeWidth="10"
            strokeLinecap="round"
          />
          <path
            d="M12 66 A52 52 0 0 1 116 66"
            fill="none"
            stroke={stroke}
            strokeWidth="10"
            strokeLinecap="round"
            strokeDasharray={CIRCUMFERENCE}
            strokeDashoffset={CIRCUMFERENCE * (1 - sweep)}
            className="transition-[stroke-dashoffset] duration-700"
            style={{ filter: `drop-shadow(0 0 8px ${stroke}66)` }}
          />
          {/* Tick at a health factor of 1.0 — the liquidation boundary. */}
          <line
            x1="64"
            y1="14"
            x2="64"
            y2="14"
            stroke="transparent"
          />
        </svg>
        <div className="absolute inset-x-0 bottom-0 text-center">
          <p className="tabular font-display text-3xl font-semibold leading-none text-ink">
            {health === null ? "∞" : health.toFixed(2)}
          </p>
          <p className="mt-1 text-[10px] uppercase tracking-[0.16em] text-ink-faint">Health</p>
        </div>
      </div>

      <div className="w-full min-w-0 flex-1">
        <div className="flex items-center justify-between gap-3">
          <Badge tone={tone === "neutral" ? "neutral" : tone === "safe" ? "safe" : tone === "warn" ? "warn" : "danger"}>
            {label}
          </Badge>
          <span className="tabular text-xs text-ink-faint">
            LTV {formatPercent(summary.currentLtvPercent, 1)} / {formatPercent(liquidationLtv, 0)}
          </span>
        </div>

        <div className="mt-3">
          <Meter
            value={summary.currentLtvPercent}
            max={100}
            markerAt={liquidationLtv}
            markerLabel={`Liquidation at ${liquidationLtv}%`}
            tone={
              summary.currentLtvPercent >= liquidationLtv
                ? "danger"
                : summary.currentLtvPercent > liquidationLtv * 0.85
                  ? "warn"
                  : "accent"
            }
          />
        </div>

        <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 text-xs">
          <div className="flex justify-between gap-2">
            <dt className="text-ink-faint">Collateral</dt>
            <dd className="tabular text-ink-muted">{formatUsd(summary.collateralUsd)}</dd>
          </div>
          <div className="flex justify-between gap-2">
            <dt className="text-ink-faint">Debt</dt>
            <dd className="tabular text-ink-muted">{formatUsd(summary.debtUsd)}</dd>
          </div>
          <div className="flex justify-between gap-2">
            <dt className="text-ink-faint">Borrow power</dt>
            <dd className="tabular text-ink-muted">{formatUsd(summary.borrowPowerUsd)}</dd>
          </div>
          <div className="flex justify-between gap-2">
            <dt className="text-ink-faint">Still available</dt>
            <dd className="tabular text-astra-200">{formatUsd(summary.availableToBorrowUsd)}</dd>
          </div>
        </dl>
      </div>
    </div>
  );
}
