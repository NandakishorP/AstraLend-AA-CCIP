import Link from "next/link";
import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from "react";

export function cx(...values: Array<string | false | null | undefined>): string {
  return values.filter(Boolean).join(" ");
}

// ─── Card ─────────────────────────────────────────────────────────────────────

export function Card({
  children,
  className,
  glow = false,
}: {
  children: ReactNode;
  className?: string;
  /** Adds the aurora edge-light used on hero and summary cards. */
  glow?: boolean;
}) {
  return (
    <div
      className={cx(
        "relative rounded-card glass overflow-hidden",
        glow &&
          "before:pointer-events-none before:absolute before:inset-x-10 before:-top-px before:h-px before:bg-gradient-to-r before:from-transparent before:via-astra-400/70 before:to-transparent",
        className
      )}
    >
      {children}
    </div>
  );
}

export function CardHeader({
  title,
  subtitle,
  action,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="flex items-start justify-between gap-4 border-b border-hairline px-5 py-4">
      <div className="min-w-0">
        <h2 className="font-display text-sm font-semibold tracking-wide text-ink">{title}</h2>
        {subtitle ? <p className="mt-0.5 text-xs text-ink-faint">{subtitle}</p> : null}
      </div>
      {action}
    </div>
  );
}

// ─── Button ───────────────────────────────────────────────────────────────────

type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";
type ButtonSize = "sm" | "md" | "lg";

const BUTTON_BASE =
  "inline-flex items-center justify-center gap-2 rounded-xl font-medium transition-all duration-150 " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-astra-400/70 focus-visible:ring-offset-2 " +
  "focus-visible:ring-offset-void disabled:cursor-not-allowed disabled:opacity-45";

const BUTTON_VARIANTS: Record<ButtonVariant, string> = {
  primary:
    "bg-gradient-to-b from-astra-500 to-astra-600 text-white shadow-[0_1px_0_0_rgba(255,255,255,0.16)_inset,0_8px_24px_-8px_rgba(124,58,237,0.9)] hover:from-astra-400 hover:to-astra-500 active:translate-y-px",
  secondary:
    "border border-hairline bg-surface-2/70 text-ink hover:border-astra-400/50 hover:bg-surface-2 active:translate-y-px",
  ghost: "text-ink-muted hover:bg-surface-2/70 hover:text-ink",
  danger:
    "border border-rose/40 bg-rose/10 text-rose hover:border-rose/70 hover:bg-rose/15 active:translate-y-px",
};

const BUTTON_SIZES: Record<ButtonSize, string> = {
  sm: "h-8 px-3 text-xs",
  md: "h-10 px-4 text-sm",
  lg: "h-12 px-6 text-sm",
};

export function Button({
  variant = "primary",
  size = "md",
  className,
  loading = false,
  children,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
}) {
  return (
    <button
      className={cx(BUTTON_BASE, BUTTON_VARIANTS[variant], BUTTON_SIZES[size], className)}
      disabled={rest.disabled || loading}
      {...rest}
    >
      {loading ? <Spinner /> : null}
      {children}
    </button>
  );
}

export function LinkButton({
  href,
  variant = "primary",
  size = "md",
  className,
  children,
  ...rest
}: AnchorHTMLAttributes<HTMLAnchorElement> & {
  href: string;
  variant?: ButtonVariant;
  size?: ButtonSize;
}) {
  const classes = cx(BUTTON_BASE, BUTTON_VARIANTS[variant], BUTTON_SIZES[size], className);
  if (href.startsWith("http")) {
    return (
      <a href={href} className={classes} target="_blank" rel="noreferrer" {...rest}>
        {children}
      </a>
    );
  }
  return (
    <Link href={href} className={classes} {...rest}>
      {children}
    </Link>
  );
}

export function Spinner({ className }: { className?: string }) {
  return (
    <svg
      className={cx("size-4 animate-spin", className)}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden
    >
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.25" strokeWidth="3" />
      <path
        d="M21 12a9 9 0 0 0-9-9"
        stroke="currentColor"
        strokeWidth="3"
        strokeLinecap="round"
      />
    </svg>
  );
}

// ─── Badge ────────────────────────────────────────────────────────────────────

type Tone = "neutral" | "safe" | "warn" | "danger" | "accent" | "info";

const TONE_CLASSES: Record<Tone, string> = {
  neutral: "border-hairline bg-surface-2/80 text-ink-muted",
  safe: "border-mint/30 bg-mint/10 text-mint",
  warn: "border-amber/30 bg-amber/10 text-amber",
  danger: "border-rose/30 bg-rose/10 text-rose",
  accent: "border-astra-400/35 bg-astra-500/12 text-astra-200",
  info: "border-glow/30 bg-glow/10 text-glow",
};

export function Badge({
  tone = "neutral",
  children,
  className,
}: {
  tone?: Tone;
  children: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={cx(
        "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[11px] font-medium tracking-wide",
        TONE_CLASSES[tone],
        className
      )}
    >
      {children}
    </span>
  );
}

export function Dot({ tone = "neutral", pulse = false }: { tone?: Tone; pulse?: boolean }) {
  const color: Record<Tone, string> = {
    neutral: "bg-ink-faint",
    safe: "bg-mint",
    warn: "bg-amber",
    danger: "bg-rose",
    accent: "bg-astra-400",
    info: "bg-glow",
  };
  return (
    <span className="relative flex size-2">
      {pulse ? (
        <span
          className={cx("absolute inline-flex size-full animate-ping rounded-full opacity-60", color[tone])}
        />
      ) : null}
      <span className={cx("relative inline-flex size-2 rounded-full", color[tone])} />
    </span>
  );
}

// ─── Loading + empty states ───────────────────────────────────────────────────

export function Skeleton({ className }: { className?: string }) {
  return (
    <div className={cx("animate-shimmer rounded-lg bg-surface-2", className)} aria-hidden />
  );
}

export function EmptyState({
  title,
  body,
  action,
  icon,
}: {
  title: string;
  body?: string;
  action?: ReactNode;
  icon?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-14 text-center">
      {icon ? <div className="text-ink-faint">{icon}</div> : null}
      <p className="font-display text-sm font-semibold text-ink">{title}</p>
      {body ? <p className="max-w-sm text-sm text-ink-faint">{body}</p> : null}
      {action}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="flex flex-col items-center gap-3 px-6 py-12 text-center">
      <div className="flex size-10 items-center justify-center rounded-full border border-rose/30 bg-rose/10 text-rose">
        !
      </div>
      <p className="max-w-md text-sm text-ink-muted">{message}</p>
      {onRetry ? (
        <Button variant="secondary" size="sm" onClick={onRetry}>
          Try again
        </Button>
      ) : null}
    </div>
  );
}

// ─── Misc ─────────────────────────────────────────────────────────────────────

export function Stat({
  label,
  value,
  hint,
  tone,
  size = "md",
}: {
  label: ReactNode;
  value: ReactNode;
  hint?: ReactNode;
  tone?: "default" | "safe" | "warn" | "danger" | "accent";
  size?: "sm" | "md" | "lg";
}) {
  const valueTone = {
    default: "text-ink",
    safe: "text-mint",
    warn: "text-amber",
    danger: "text-rose",
    accent: "text-astra-200",
  }[tone ?? "default"];

  const valueSize = {
    sm: "text-lg",
    md: "text-2xl",
    lg: "text-4xl",
  }[size];

  return (
    <div className="min-w-0">
      <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">{label}</p>
      <p className={cx("tabular mt-1.5 font-display font-semibold", valueSize, valueTone)}>{value}</p>
      {hint ? <p className="mt-1 truncate text-xs text-ink-faint">{hint}</p> : null}
    </div>
  );
}

/** Thin progress meter used for utilization and LTV. */
export function Meter({
  value,
  max = 100,
  tone = "accent",
  markerAt,
  markerLabel,
}: {
  value: number;
  max?: number;
  tone?: "accent" | "safe" | "warn" | "danger";
  /** Optional threshold tick, e.g. the liquidation point. */
  markerAt?: number;
  markerLabel?: string;
}) {
  const pct = Math.max(0, Math.min(100, (value / max) * 100));
  const fill = {
    accent: "from-astra-500 to-glow",
    safe: "from-mint to-glow",
    warn: "from-amber to-astra-500",
    danger: "from-rose to-amber",
  }[tone];

  return (
    <div className="relative h-1.5 w-full overflow-hidden rounded-full bg-surface-2">
      <div
        className={cx("h-full rounded-full bg-gradient-to-r transition-[width] duration-500", fill)}
        style={{ width: `${pct}%` }}
      />
      {markerAt !== undefined ? (
        <span
          className="absolute top-1/2 h-3 w-px -translate-y-1/2 bg-ink-faint/70"
          style={{ left: `${Math.min(100, (markerAt / max) * 100)}%` }}
          title={markerLabel}
        />
      ) : null}
    </div>
  );
}

/** Round token glyph — deterministic colour from the symbol, no image assets. */
export function TokenGlyph({ symbol, size = 32 }: { symbol: string; size?: number }) {
  const hue = [...symbol].reduce((sum, char) => sum + char.charCodeAt(0), 0) % 360;
  return (
    <span
      className="inline-flex shrink-0 items-center justify-center rounded-full font-display font-semibold"
      style={{
        width: size,
        height: size,
        // Four characters is the widest common ticker; scale text to fit it.
        fontSize: size * (symbol.length > 3 ? 0.27 : 0.34),
        background: `radial-gradient(120% 120% at 30% 20%, hsl(${hue} 90% 66% / 0.35), hsl(${(hue + 40) % 360} 90% 40% / 0.22))`,
        border: `1px solid hsl(${hue} 80% 70% / 0.35)`,
        color: `hsl(${hue} 90% 84%)`,
      }}
    >
      {symbol.slice(0, 4).toUpperCase()}
    </span>
  );
}
