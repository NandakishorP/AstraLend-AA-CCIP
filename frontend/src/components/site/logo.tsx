import Link from "next/link";
import { cx } from "@/components/ui/primitives";

/** The mark: an orbit ring with a body on its path. Inline SVG, no assets. */
export function LogoMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={cx("size-8", className)} fill="none" aria-hidden>
      <defs>
        <linearGradient id="astra-mark" x1="4" y1="28" x2="28" y2="4">
          <stop stopColor="#22d3ee" />
          <stop offset="0.55" stopColor="#8b5cf6" />
          <stop offset="1" stopColor="#cdbcff" />
        </linearGradient>
      </defs>
      <ellipse
        cx="16"
        cy="16"
        rx="13"
        ry="6.5"
        transform="rotate(-32 16 16)"
        stroke="url(#astra-mark)"
        strokeWidth="1.6"
        opacity="0.85"
      />
      <ellipse
        cx="16"
        cy="16"
        rx="13"
        ry="6.5"
        transform="rotate(32 16 16)"
        stroke="url(#astra-mark)"
        strokeWidth="1.6"
        opacity="0.35"
      />
      <circle cx="16" cy="16" r="4.2" fill="url(#astra-mark)" />
    </svg>
  );
}

export function Logo({ href = "/", compact = false }: { href?: string; compact?: boolean }) {
  return (
    <Link href={href} className="group flex items-center gap-2.5">
      <LogoMark className="transition-transform duration-500 group-hover:rotate-[18deg]" />
      {compact ? null : (
        <span className="font-display text-[17px] font-semibold tracking-tight text-ink">
          Astra<span className="text-astra-200">Lend</span>
        </span>
      )}
    </Link>
  );
}
