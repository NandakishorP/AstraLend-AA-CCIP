"use client";

import { useMemo, useState } from "react";
import { useProtocolHistory } from "@/lib/hooks";
import { formatUsd, formatUsdNumber } from "@/lib/format";
import { Badge, EmptyState, Skeleton, cx } from "@/components/ui/primitives";
import type { Range, SeriesPoint } from "@/lib/types";

/**
 * Protocol value over time.
 *
 * This is the one view in the app that chain state cannot produce: contracts
 * only ever report the present. Every point here was written by the indexer's
 * snapshotter while the app was running, which is the whole reason the database
 * exists.
 *
 * Two series on one axis, both USD — TVL and outstanding borrows. Colours are
 * the validated dark-surface pair: OKLCH lightness in band, chroma above floor,
 * adjacent CVD ΔE 15.0, contrast above 3:1. Identity is carried by a legend, not
 * by colour alone.
 */
const TVL_COLOR = "#7c3aed";
const BORROWED_COLOR = "#0891b2";
const SURFACE = "#0d1020";

const WIDTH = 720;
const HEIGHT = 240;
const PADDING = { top: 16, right: 16, bottom: 28, left: 56 };

const RANGES: Range[] = ["1h", "6h", "24h", "7d", "all"];

export function TvlChart() {
  const [range, setRange] = useState<Range>("1h");
  const { data, isLoading } = useProtocolHistory(range);
  const [hover, setHover] = useState<number | null>(null);

  const points = data?.points ?? [];

  const series = useMemo(() => {
    return points.map((point) => ({
      timestamp: point.timestamp,
      tvl: Number(BigInt(String(point.values.tvlUsd ?? "0")) / 10n ** 12n) / 1e6,
      borrowed: Number(BigInt(String(point.values.borrowedUsd ?? "0")) / 10n ** 12n) / 1e6,
    }));
  }, [points]);

  const plotWidth = WIDTH - PADDING.left - PADDING.right;
  const plotHeight = HEIGHT - PADDING.top - PADDING.bottom;

  // A flat series still needs a non-zero span, or every point lands on one line.
  const maxValue = Math.max(...series.map((p) => p.tvl), 1);
  const yMax = maxValue * 1.15;

  const x = (index: number) =>
    PADDING.left + (series.length <= 1 ? plotWidth / 2 : (index / (series.length - 1)) * plotWidth);
  const y = (value: number) => PADDING.top + plotHeight - (value / yMax) * plotHeight;

  const linePath = (key: "tvl" | "borrowed") =>
    series.map((p, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(2)} ${y(p[key]).toFixed(2)}`).join(" ");

  const areaPath =
    series.length > 0
      ? `${linePath("tvl")} L${x(series.length - 1)} ${y(0)} L${x(0)} ${y(0)} Z`
      : "";

  const active = hover !== null ? series[hover] : series[series.length - 1];
  const change = data?.change.tvlPercent ?? null;

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-3 px-5 pb-4 pt-1">
        <div>
          <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
            Total value locked
          </p>
          <div className="mt-1 flex items-baseline gap-2.5">
            <p className="tabular font-display text-2xl font-semibold text-ink">
              {active ? formatUsdNumber(active.tvl) : "—"}
            </p>
            {change !== null && Number.isFinite(change) ? (
              <Badge tone={change >= 0 ? "safe" : "danger"}>
                {change >= 0 ? "+" : ""}
                {change.toFixed(2)}%
              </Badge>
            ) : null}
          </div>
          {hover !== null && active ? (
            <p className="tabular mt-0.5 text-xs text-ink-faint">
              {new Date(active.timestamp * 1000).toLocaleString()}
            </p>
          ) : null}
        </div>

        <div className="flex gap-0.5 rounded-lg border border-hairline bg-surface-2/60 p-0.5">
          {RANGES.map((option) => (
            <button
              key={option}
              onClick={() => setRange(option)}
              className={cx(
                "rounded-md px-2.5 py-1 text-[11px] font-medium transition",
                option === range ? "bg-surface text-ink" : "text-ink-faint hover:text-ink-muted"
              )}
            >
              {option}
            </button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <div className="px-5 pb-5">
          <Skeleton className="h-[240px] w-full" />
        </div>
      ) : series.length < 2 ? (
        <EmptyState
          title="Not enough history yet"
          body="The indexer writes a snapshot every 30 seconds. Give it a minute, or run an action — the chart fills in as the protocol is used."
        />
      ) : (
        <>
          <svg
            viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
            className="w-full touch-none"
            role="img"
            aria-label={`Total value locked over the last ${range}, currently ${active ? formatUsdNumber(active.tvl) : "unknown"}.`}
            onPointerMove={(event) => {
              const rect = event.currentTarget.getBoundingClientRect();
              const ratio = (event.clientX - rect.left) / rect.width;
              const svgX = ratio * WIDTH - PADDING.left;
              const index = Math.round((svgX / plotWidth) * (series.length - 1));
              setHover(Math.max(0, Math.min(series.length - 1, index)));
            }}
            onPointerLeave={() => setHover(null)}
          >
            <defs>
              <linearGradient id="tvl-fill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={TVL_COLOR} stopOpacity="0.30" />
                <stop offset="100%" stopColor={TVL_COLOR} stopOpacity="0" />
              </linearGradient>
            </defs>

            {[0, 0.25, 0.5, 0.75, 1].map((fraction) => {
              const value = yMax * fraction;
              return (
                <g key={fraction}>
                  <line
                    x1={PADDING.left}
                    x2={WIDTH - PADDING.right}
                    y1={y(value)}
                    y2={y(value)}
                    stroke="#1d2338"
                    strokeWidth="1"
                  />
                  <text
                    x={PADDING.left - 8}
                    y={y(value) + 3.5}
                    textAnchor="end"
                    className="fill-[#656d92] text-[10px]"
                  >
                    {formatUsdNumber(value, { compact: true })}
                  </text>
                </g>
              );
            })}

            <path d={areaPath} fill="url(#tvl-fill)" />
            <path d={linePath("tvl")} fill="none" stroke={TVL_COLOR} strokeWidth="2" strokeLinecap="round" />
            <path
              d={linePath("borrowed")}
              fill="none"
              stroke={BORROWED_COLOR}
              strokeWidth="2"
              strokeLinecap="round"
              strokeDasharray="4 4"
            />

            {hover !== null ? (
              <g pointerEvents="none">
                <line
                  x1={x(hover)}
                  x2={x(hover)}
                  y1={PADDING.top}
                  y2={PADDING.top + plotHeight}
                  stroke="#9aa3c7"
                  strokeWidth="1"
                />
                <circle cx={x(hover)} cy={y(series[hover]!.tvl)} r="4" fill={TVL_COLOR} stroke={SURFACE} strokeWidth="2" />
                <circle
                  cx={x(hover)}
                  cy={y(series[hover]!.borrowed)}
                  r="4"
                  fill={BORROWED_COLOR}
                  stroke={SURFACE}
                  strokeWidth="2"
                />
              </g>
            ) : null}
          </svg>

          <div className="flex flex-wrap items-center justify-between gap-3 px-5 pb-4 text-xs text-ink-faint">
            <span className="flex items-center gap-4">
              <span className="flex items-center gap-1.5">
                <span className="h-0.5 w-4 rounded-full" style={{ background: TVL_COLOR }} />
                Value locked
              </span>
              <span className="flex items-center gap-1.5">
                <span
                  className="h-0.5 w-4 rounded-full"
                  style={{
                    backgroundImage: `repeating-linear-gradient(to right, ${BORROWED_COLOR} 0 4px, transparent 4px 8px)`,
                  }}
                />
                Borrowed {active ? formatUsdNumber(active.borrowed) : ""}
              </span>
            </span>
            <span className="tabular">{points.length} snapshots</span>
          </div>
        </>
      )}
    </div>
  );
}

/** Small helper so the dashboard can show the latest indexed TVL inline. */
export function latestTvl(points: SeriesPoint[]): string | null {
  const last = points[points.length - 1];
  return last ? formatUsd(String(last.values.tvlUsd ?? "0")) : null;
}
