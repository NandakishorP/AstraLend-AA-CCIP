"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { Logo } from "@/components/site/logo";
import { Backdrop } from "@/components/site/backdrop";
import { ChainSwitcher } from "./chain-switcher";
import { WalletButton } from "./wallet-button";
import { StatusPill } from "./status-pill";
import { cx } from "@/components/ui/primitives";

const NAV = [
  { href: "/app", label: "Dashboard", icon: IconGrid, exact: true },
  { href: "/app/markets", label: "Markets", icon: IconLayers },
  { href: "/app/borrow", label: "Borrow", icon: IconArrowDown },
  { href: "/app/portfolio", label: "Portfolio", icon: IconWallet },
  { href: "/app/activity", label: "Activity", icon: IconPulse },
];

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();

  return (
    <>
      <Backdrop intensity="subtle" />

      <div className="relative flex min-h-dvh flex-col">
        <header className="sticky top-0 z-40 border-b border-hairline/70 bg-void/75 backdrop-blur-xl">
          <div className="mx-auto flex h-16 max-w-7xl items-center gap-4 px-4 sm:px-6">
            <Logo href="/" />
            <StatusPill />
            <div className="ml-auto flex items-center gap-2.5">
              <ChainSwitcher />
              <WalletButton />
            </div>
          </div>

          {/* Primary nav: a tab rail on desktop, a scrollable strip on mobile. */}
          <nav className="mx-auto max-w-7xl px-4 sm:px-6">
            <ul className="-mb-px flex gap-1 overflow-x-auto">
              {NAV.map((item) => {
                const active = item.exact ? pathname === item.href : pathname.startsWith(item.href);
                const Icon = item.icon;
                return (
                  <li key={item.href}>
                    <Link
                      href={item.href}
                      className={cx(
                        "flex h-11 items-center gap-2 whitespace-nowrap border-b-2 px-3 text-sm transition",
                        active
                          ? "border-astra-400 text-ink"
                          : "border-transparent text-ink-faint hover:text-ink-muted"
                      )}
                    >
                      <Icon className={cx("size-4", active && "text-astra-400")} />
                      {item.label}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </nav>
        </header>

        <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-8 sm:px-6">{children}</main>

        <footer className="border-t border-hairline/60 py-5">
          <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3 px-4 text-xs text-ink-faint sm:px-6">
            <p>AstraLend runs on public testnets. Assets have no real value.</p>
            <Link href="/" className="transition hover:text-ink-muted">
              ← Back to overview
            </Link>
          </div>
        </footer>
      </div>
    </>
  );
}

/** Page header used by every app route, so titles and actions line up. */
export function PageHeader({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="font-display text-2xl font-semibold tracking-tight text-ink">{title}</h1>
        {description ? <p className="mt-1.5 max-w-2xl text-sm text-ink-muted">{description}</p> : null}
      </div>
      {action}
    </div>
  );
}

// ─── Icons ────────────────────────────────────────────────────────────────────

type IconProps = { className?: string };

function IconGrid({ className }: IconProps) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.5">
      <rect x="2" y="2" width="5" height="5" rx="1.2" />
      <rect x="9" y="2" width="5" height="5" rx="1.2" />
      <rect x="2" y="9" width="5" height="5" rx="1.2" />
      <rect x="9" y="9" width="5" height="5" rx="1.2" />
    </svg>
  );
}

function IconLayers({ className }: IconProps) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M8 2l6 3-6 3-6-3 6-3z" strokeLinejoin="round" />
      <path d="M2 8l6 3 6-3M2 11.5l6 3 6-3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function IconArrowDown({ className }: IconProps) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M8 2.5v11M4 9.5l4 4 4-4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function IconWallet({ className }: IconProps) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.5">
      <rect x="2" y="3.5" width="12" height="9" rx="2" />
      <path d="M11 8h1.5" strokeLinecap="round" />
    </svg>
  );
}

function IconPulse({ className }: IconProps) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M1.5 8h3l2-4.5L9.5 12l2-4h3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
