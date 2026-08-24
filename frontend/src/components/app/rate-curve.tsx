"use client";

import { useMemo, useState } from "react";
import { formatPercent } from "@/lib/format";
import type { MarketOverview } from "@/lib/types";

/**
 * The protocol's borrow-rate curve, with each live market plotted on it.
 *
 * One measure on one axis: borrow APR against utilization. The curve is the
 * model; the dots are where the markets currently sit. Identity comes from
 * direct labels rather than colour alone, so the two encodings never rely on
 * hue to be told apart.
 *
 * Colours are the validated dark-surface pair for this palette: OKLCH lightness
 * in band, chroma above floor, adjacent CVD ΔE 15.0, contrast above 3:1.
 */
const CURVE_COLOR = "#7c3aed";
const POINT_COLOR = "#0891b2";
const SURFACE = "#0d1020";

const WIDTH = 520;
const HEIGHT = 240;
const PADDING = { top: 16, right: 20, bottom: 32, left: 44 };

export function RateCurve({ overview }: { overview: MarketOverview }) {
  const { baseInterestRatePercent: base, maxInterestRatePercent: max, kinkPercent: kink } =
    overview.parameters;

  // The curve keeps climbing past the kink, so the ceiling is the rate at 100%
  // utilization — not the "max rate" constant, which is only the kink value.
  const yMax = useMemo(() => rateAt(100, base, max, kink), [base, max, kink]);

  const plotWidth = WIDTH - PADDING.left - PADDING.right;
  const plotHeight = HEIGHT - PADDING.top - PADDING.bottom;

  const x = (utilization: number) => PADDING.left + (utilization / 100) * plotWidth;
  const y = (rate: number) => PADDING.top + plotHeight - (rate / yMax) * plotHeight;

  const path = useMemo(() => {
    // The scale functions are re-created each render, so the curve is sampled
    // with local copies to keep this memo's dependencies honest.
    const sx = (utilization: number) => PADDING.left + (utilization / 100) * plotWidth;
    const sy = (rate: number) => PADDING.top + plotHeight - (rate / yMax) * plotHeight;

    const points: string[] = [];
    for (let u = 0; u <= 100; u += 1) {
      points.push(`${u === 0 ? "M" : "L"}${sx(u).toFixed(2)} ${sy(rateAt(u, base, max, kink)).toFixed(2)}`);
    }
    return points.join(" ");
  }, [base, max, kink, yMax, plotWidth, plotHeight]);

  const areaPath = `${path} L${x(100)} ${y(0)} L${x(0)} ${y(0)} Z`;

  const [hover, setHover] = useState<number | null>(null);
  const hoverRate = hover === null ? null : rateAt(hover, base, max, kink);

  const yTicks = [0, yMax / 4, yMax / 2, (yMax * 3) / 4, yMax];
  const xTicks = [0, 25, 50, 75, 100];

  return (
    <figure className="m-0">
      <svg
        viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
        className="w-full touch-none"
        role="img"
        aria-label={`Borrow APR against utilization. Base rate ${base}% at zero utilization, rising to ${max}% at the ${kink}% kink and ${yMax.toFixed(0)}% at full utilization.`}
        onPointerMove={(event) => {
          const rect = event.currentTarget.getBoundingClientRect();
          const ratio = (event.clientX - rect.left) / rect.width;
          const svgX = ratio * WIDTH;
          const utilization = ((svgX - PADDING.left) / plotWidth) * 100;
          setHover(Math.max(0, Math.min(100, utilization)));
        }}
        onPointerLeave={() => setHover(null)}
      >
        <defs>
          <linearGradient id="rate-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={CURVE_COLOR} stopOpacity="0.28" />
            <stop offset="100%" stopColor={CURVE_COLOR} stopOpacity="0" />
          </linearGradient>
        </defs>

        {/* Recessive grid */}
        {yTicks.map((tick) => (
          <g key={`y-${tick}`}>
            <line
              x1={PADDING.left}
              x2={WIDTH - PADDING.right}
              y1={y(tick)}
              y2={y(tick)}
              stroke="#1d2338"
              strokeWidth="1"
            />
            <text
              x={PADDING.left - 8}
              y={y(tick) + 3.5}
              textAnchor="end"
              className="fill-[#656d92] text-[10px]"
            >
              {tick.toFixed(0)}%
            </text>
          </g>
        ))}

        {xTicks.map((tick) => (
          <text
            key={`x-${tick}`}
            x={x(tick)}
            y={HEIGHT - 10}
            textAnchor="middle"
            className="fill-[#656d92] text-[10px]"
          >
            {tick}%
          </text>
        ))}

        {/* Kink marker */}
        <line
          x1={x(kink)}
          x2={x(kink)}
          y1={PADDING.top}
          y2={PADDING.top + plotHeight}
          stroke="#656d92"
          strokeWidth="1"
          strokeDasharray="3 4"
        />
        <text x={x(kink) + 5} y={PADDING.top + 11} className="fill-[#9aa3c7] text-[10px]">
          kink {kink}%
        </text>

        <path d={areaPath} fill="url(#rate-fill)" />
        <path d={path} fill="none" stroke={CURVE_COLOR} strokeWidth="2" strokeLinecap="round" />

        {/* Live markets, ringed in the surface colour so they read over the curve.
            Markets at the same utilization land on the same point, so labels are
            stacked by index rather than drawn on top of one another. */}
        {(() => {
          const placed: { cx: number; cy: number }[] = [];
          return overview.markets
            .filter((market) => market.registered)
            .map((market) => {
              const cx = x(market.utilizationPercent);
              const cy = y(market.borrowApr);
              const collisions = placed.filter(
                (point) => Math.abs(point.cx - cx) < 24 && Math.abs(point.cy - cy) < 20
              ).length;
              placed.push({ cx, cy });

              const labelLeft = cx > WIDTH - 90;
              return (
                <g key={market.tokenId}>
                  <circle cx={cx} cy={cy} r="6" fill={POINT_COLOR} stroke={SURFACE} strokeWidth="2" />
                  <text
                    x={labelLeft ? cx - 11 : cx + 11}
                    y={cy - 8 - collisions * 13}
                    textAnchor={labelLeft ? "end" : "start"}
                    className="fill-[#eef1ff] text-[10px] font-medium"
                  >
                    {market.symbol}
                  </text>
                </g>
              );
            });
        })()}

        {/* Hover crosshair */}
        {hover !== null && hoverRate !== null ? (
          <g pointerEvents="none">
            <line
              x1={x(hover)}
              x2={x(hover)}
              y1={PADDING.top}
              y2={PADDING.top + plotHeight}
              stroke="#9aa3c7"
              strokeWidth="1"
            />
            <circle cx={x(hover)} cy={y(hoverRate)} r="4" fill={CURVE_COLOR} stroke={SURFACE} strokeWidth="2" />
          </g>
        ) : null}
      </svg>

      <figcaption className="mt-3 flex flex-wrap items-center justify-between gap-3 text-xs text-ink-faint">
        <span className="flex items-center gap-4">
          <span className="flex items-center gap-1.5">
            <span className="h-0.5 w-4 rounded-full" style={{ background: CURVE_COLOR }} />
            Borrow APR
          </span>
          <span className="flex items-center gap-1.5">
            <span className="size-2 rounded-full" style={{ background: POINT_COLOR }} />
            Live market
          </span>
        </span>
        <span className="tabular">
          {hover === null
            ? `Base ${formatPercent(base, 0)} → ${formatPercent(yMax, 0)} at full utilization`
            : `${formatPercent(hover, 0)} utilization → ${formatPercent(hoverRate ?? 0, 1)} APR`}
        </span>
      </figcaption>
    </figure>
  );
}

/** Mirrors InterestRateModel._calculateInterestRate, in percentage units. */
function rateAt(utilization: number, base: number, max: number, kink: number): number {
  if (utilization < kink) {
    return base + ((max - base) * utilization) / kink;
  }
  return max + (max * (utilization - kink)) / (100 - kink);
}
