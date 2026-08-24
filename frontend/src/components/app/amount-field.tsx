"use client";

import { formatToken } from "@/lib/format";
import { TokenGlyph, cx } from "@/components/ui/primitives";

/**
 * Amount entry with a balance readout and quick-fill percentages.
 *
 * The field is a plain text input rather than `type="number"`: number inputs
 * silently mangle long decimal strings and hijack the scroll wheel, both of
 * which are actively harmful when the value is a token amount.
 */
export function AmountField({
  value,
  onChange,
  symbol,
  decimals,
  max,
  maxLabel = "Available",
  usdValue,
  error,
  disabled,
}: {
  value: string;
  onChange: (value: string) => void;
  symbol: string;
  decimals: number;
  /** Upper bound in the token's smallest unit; enables the quick-fill buttons. */
  max?: bigint;
  maxLabel?: string;
  usdValue?: string;
  error?: string | null;
  disabled?: boolean;
}) {
  function fill(fraction: number) {
    if (max === undefined) return;
    // Percentages are computed in integer math to avoid float drift, then
    // formatted back to a decimal string the input can round-trip.
    const scaled = (max * BigInt(Math.round(fraction * 10_000))) / 10_000n;
    const whole = scaled / 10n ** BigInt(decimals);
    const remainder = scaled % 10n ** BigInt(decimals);
    const fractional = remainder.toString().padStart(decimals, "0").replace(/0+$/, "");
    onChange(fractional ? `${whole}.${fractional}` : whole.toString());
  }

  return (
    <div>
      <div
        className={cx(
          "rounded-xl border bg-surface-2/50 p-4 transition-colors",
          error ? "border-rose/50" : "border-hairline focus-within:border-astra-400/60"
        )}
      >
        <div className="flex items-center gap-3">
          <input
            value={value}
            onChange={(event) => onChange(event.target.value)}
            inputMode="decimal"
            autoComplete="off"
            placeholder="0.0"
            disabled={disabled}
            aria-label={`Amount in ${symbol}`}
            className="tabular min-w-0 flex-1 bg-transparent font-display text-2xl font-semibold text-ink outline-none placeholder:text-ink-faint/60 disabled:opacity-50"
          />
          <span className="flex shrink-0 items-center gap-2 rounded-full border border-hairline bg-surface px-2.5 py-1.5">
            <TokenGlyph symbol={symbol} size={20} />
            <span className="text-sm font-medium text-ink">{symbol}</span>
          </span>
        </div>

        <div className="mt-3 flex items-center justify-between gap-3 text-xs">
          <span className="tabular text-ink-faint">{usdValue ?? " "}</span>
          {max !== undefined ? (
            <span className="tabular text-ink-faint">
              {maxLabel}: {formatToken(max, decimals)} {symbol}
            </span>
          ) : null}
        </div>
      </div>

      {max !== undefined ? (
        <div className="mt-2 flex gap-1.5">
          {[0.25, 0.5, 0.75, 1].map((fraction) => (
            <button
              key={fraction}
              type="button"
              disabled={disabled || max === 0n}
              onClick={() => fill(fraction)}
              className="flex-1 rounded-lg border border-hairline bg-surface-2/40 py-1.5 text-[11px] font-medium text-ink-muted transition hover:border-astra-400/40 hover:text-ink disabled:opacity-40"
            >
              {fraction === 1 ? "MAX" : `${fraction * 100}%`}
            </button>
          ))}
        </div>
      ) : null}

      {error ? <p className="mt-2 text-xs text-rose">{error}</p> : null}
    </div>
  );
}
