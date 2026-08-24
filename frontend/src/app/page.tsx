import Link from "next/link";
import { Backdrop } from "@/components/site/backdrop";
import { HeroPanel } from "@/components/site/hero-panel";
import { LandingStats } from "@/components/site/landing-stats";
import { Logo } from "@/components/site/logo";
import { Badge, Card, LinkButton } from "@/components/ui/primitives";

export default function LandingPage() {
  return (
    <>
      <Backdrop />
      <div className="relative">
        <SiteHeader />
        <main>
          <Hero />
          <ChainSection />
          <HowItWorks />
          <Parameters />
          <FinalCta />
        </main>
        <SiteFooter />
      </div>
    </>
  );
}

// ─── Header ───────────────────────────────────────────────────────────────────

function SiteHeader() {
  return (
    <header className="sticky top-0 z-50 border-b border-hairline/60 bg-void/70 backdrop-blur-xl">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-5">
        <Logo />
        <nav className="hidden items-center gap-1 md:flex">
          {[
            ["How it works", "#how"],
            ["Cross-chain", "#chains"],
            ["Parameters", "#parameters"],
          ].map(([label, href]) => (
            <a
              key={href}
              href={href}
              className="rounded-lg px-3 py-2 text-sm text-ink-muted transition hover:bg-surface-2/60 hover:text-ink"
            >
              {label}
            </a>
          ))}
        </nav>
        <div className="flex items-center gap-2">
          <LinkButton href="/app/markets" variant="ghost" size="sm" className="hidden sm:inline-flex">
            Markets
          </LinkButton>
          <LinkButton href="/app" size="sm">
            Launch app
          </LinkButton>
        </div>
      </div>
    </header>
  );
}

// ─── Hero ─────────────────────────────────────────────────────────────────────

function Hero() {
  return (
    <section className="mx-auto max-w-6xl px-5 pb-20 pt-16 sm:pt-24">
      <div className="grid items-center gap-12 lg:grid-cols-[1.05fr_0.95fr]">
        <div>
          <div className="animate-rise">
            <Badge tone="accent">
              <span className="size-1.5 rounded-full bg-astra-400" />
              Powered by Chainlink CCIP
            </Badge>
          </div>

          {/* Sized so each sentence holds its own line beside the panel — the
              line break is the point of the headline. */}
          <h1 className="animate-rise mt-6 font-display text-[2.5rem] font-semibold leading-[1.06] tracking-[-0.03em] text-ink [animation-delay:60ms] sm:text-[3.25rem] lg:text-[2.8rem] xl:text-[3.1rem]">
            Collateral on one chain.
            <br />
            <span className="text-gradient">Liquidity on every chain.</span>
          </h1>

          <p className="animate-rise mt-6 max-w-xl text-lg leading-relaxed text-ink-muted [animation-delay:120ms]">
            AstraLend keeps a single global position for every borrower. Post collateral on
            Arbitrum, draw a stablecoin loan against it from Ethereum, and repay from wherever you
            happen to be. State stays in sync over Chainlink CCIP — no wrapped receipts, no bridge
            round-trips.
          </p>

          <div className="animate-rise mt-9 flex flex-wrap items-center gap-3 [animation-delay:180ms]">
            <LinkButton href="/app" size="lg">
              Launch app
              <svg viewBox="0 0 16 16" className="size-4" fill="none" stroke="currentColor" strokeWidth="1.8">
                <path d="M3 8h10M9 4l4 4-4 4" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </LinkButton>
            <LinkButton href="/app/markets" variant="secondary" size="lg">
              Explore markets
            </LinkButton>
          </div>
        </div>

        <div className="animate-rise [animation-delay:220ms]">
          <HeroPanel />
        </div>
      </div>

      <div className="animate-rise mt-16 [animation-delay:280ms]">
        <LandingStats />
      </div>
    </section>
  );
}

// ─── Cross-chain explainer ────────────────────────────────────────────────────

function ChainSection() {
  return (
    <section id="chains" className="mx-auto max-w-6xl scroll-mt-20 px-5 py-20">
      <SectionHeading
        eyebrow="Architecture"
        title="One position, mirrored across chains"
        body="Ethereum is the hub: it holds the global state manager that owns every balance, loan and index. Satellite chains keep a local mirror and forward each action to the hub over CCIP, so a deposit made on Arbitrum counts toward borrowing power everywhere."
      />

      <div className="mt-12 grid gap-4 lg:grid-cols-[1.1fr_0.9fr]">
        <Card glow className="p-6 sm:p-8">
          <ChainDiagram />
        </Card>

        <div className="grid gap-4">
          {[
            {
              title: "Hub chain — Ethereum",
              body: "The Global State Manager is the single source of truth for collateral, loans, LP supply and the borrower interest index.",
              tone: "accent" as const,
              label: "Authoritative state",
            },
            {
              title: "Satellite chain — Arbitrum",
              body: "Local mirrors serve instant reads. Every write is forwarded to the hub as a CCIP message, paid for in native gas at submission time.",
              tone: "info" as const,
              label: "Mirrored state",
            },
            {
              title: "Settlement",
              body: "Cross-chain actions are asynchronous. The UI shows the pending state immediately and reconciles once CCIP delivers the message to the hub.",
              tone: "neutral" as const,
              label: "Eventually consistent",
            },
          ].map((item) => (
            <Card key={item.title} className="p-5">
              <Badge tone={item.tone}>{item.label}</Badge>
              <h3 className="mt-3 font-display text-base font-semibold text-ink">{item.title}</h3>
              <p className="mt-1.5 text-sm leading-relaxed text-ink-muted">{item.body}</p>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}

function ChainDiagram() {
  return (
    <div className="relative">
      <div className="flex items-center justify-between gap-4">
        <ChainNode name="Arbitrum Sepolia" role="Satellite" accent="#22d3ee" />
        <div className="relative flex-1">
          <div className="h-px w-full bg-gradient-to-r from-glow/60 via-astra-400/70 to-astra-500/60" />
          <div className="absolute inset-x-0 -top-3 flex justify-center">
            <span className="rounded-full border border-hairline bg-surface px-2.5 py-1 text-[10px] font-medium uppercase tracking-[0.16em] text-ink-faint">
              CCIP
            </span>
          </div>
          <div className="absolute inset-x-0 top-4 flex justify-center">
            <span className="text-[10px] text-ink-faint">message + fee</span>
          </div>
        </div>
        <ChainNode name="Ethereum Sepolia" role="Hub" accent="#8b5cf6" />
      </div>

      <div className="mt-10 grid gap-2.5">
        {[
          ["1", "Deposit collateral on either chain", "Tokens are custodied by that chain's vault."],
          ["2", "State reaches the hub", "The Global State Manager records the position."],
          ["3", "Borrow against the global total", "Up to 75% LTV of all collateral, on any chain."],
          ["4", "Repay and unlock", "Interest settles first; collateral releases in full."],
        ].map(([step, title, body]) => (
          <div key={step} className="flex gap-3.5 rounded-xl border border-hairline/70 bg-surface-2/40 p-3.5">
            <span className="flex size-6 shrink-0 items-center justify-center rounded-full border border-astra-400/40 bg-astra-500/15 text-[11px] font-semibold text-astra-200">
              {step}
            </span>
            <div>
              <p className="text-sm font-medium text-ink">{title}</p>
              <p className="mt-0.5 text-xs text-ink-faint">{body}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function ChainNode({ name, role, accent }: { name: string; role: string; accent: string }) {
  return (
    <div className="flex w-32 shrink-0 flex-col items-center gap-2 text-center">
      <span
        className="flex size-14 items-center justify-center rounded-2xl border"
        style={{
          borderColor: `${accent}55`,
          background: `radial-gradient(120% 120% at 30% 20%, ${accent}33, ${accent}0d)`,
          boxShadow: `0 0 32px -12px ${accent}`,
        }}
      >
        <span className="size-2.5 rounded-full" style={{ background: accent }} />
      </span>
      <div>
        <p className="text-xs font-medium text-ink">{name}</p>
        <p className="text-[10px] uppercase tracking-[0.14em] text-ink-faint">{role}</p>
      </div>
    </div>
  );
}

// ─── How it works ─────────────────────────────────────────────────────────────

function HowItWorks() {
  const steps = [
    {
      title: "Supply liquidity",
      body: "Deposit a supported asset into the pool and receive LP tokens representing your share. Your yield is the borrow rate scaled by pool utilization.",
      points: ["LP tokens minted pro-rata", "Withdraw any unborrowed share", "Rates follow the kinked curve"],
    },
    {
      title: "Post collateral",
      body: "Lock assets against future loans. Collateral is valued from Chainlink price feeds and counts toward your borrowing power across every chain.",
      points: ["Chainlink-priced valuation", "Locked only while a loan is open", "Released on full repayment"],
    },
    {
      title: "Borrow and repay",
      body: "Draw a stablecoin loan up to 75% of your collateral value on a 180-day term. Interest accrues through a borrower index; repayments settle interest before principal.",
      points: ["75% max LTV", "80% liquidation threshold", "Partial repayment supported"],
    },
  ];

  return (
    <section id="how" className="scroll-mt-20 border-y border-hairline/60 bg-abyss/40 py-20">
      <div className="mx-auto max-w-6xl px-5">
        <SectionHeading
          eyebrow="How it works"
          title="Three moves, one position"
          body="The protocol keeps supply, collateral and debt as separate ledgers so lenders are never exposed to a single borrower's liquidation risk."
        />

        <div className="mt-12 grid gap-4 md:grid-cols-3">
          {steps.map((step, index) => (
            <Card key={step.title} className="group p-6 transition-colors hover:border-astra-400/35">
              <span className="font-display text-4xl font-semibold text-hairline transition-colors group-hover:text-astra-500/60">
                0{index + 1}
              </span>
              <h3 className="mt-4 font-display text-lg font-semibold text-ink">{step.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-muted">{step.body}</p>
              <ul className="mt-5 space-y-2 border-t border-hairline pt-4">
                {step.points.map((point) => (
                  <li key={point} className="flex items-start gap-2 text-xs text-ink-faint">
                    <svg viewBox="0 0 16 16" className="mt-0.5 size-3.5 shrink-0 text-astra-400" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M3 8.5l3.5 3.5L13 5" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                    {point}
                  </li>
                ))}
              </ul>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}

// ─── Parameters ───────────────────────────────────────────────────────────────

function Parameters() {
  const rows: [string, string, string][] = [
    ["Maximum LTV", "75%", "Borrowing power as a share of collateral value"],
    ["Liquidation threshold", "80%", "Debt-to-collateral point where a position can be liquidated"],
    ["Liquidation penalty", "5%", "Taken from collateral when a position is liquidated"],
    ["Loan term", "180 days", "Fixed term; interest accrues continuously until repaid"],
    ["Base borrow rate", "5% APR", "Rate at zero utilization"],
    ["Rate ceiling", "100% APR", "Reached at the 70% utilization kink, then steepens"],
  ];

  return (
    <section id="parameters" className="mx-auto max-w-6xl scroll-mt-20 px-5 py-20">
      <SectionHeading
        eyebrow="Risk parameters"
        title="Everything enforced on-chain"
        body="These constants live in the lending pool and its interest rate model. The app reads them live rather than hard-coding them, so what you see is what the contracts enforce."
      />

      <Card className="mt-10 overflow-hidden">
        <table className="w-full text-left text-sm">
          <tbody className="divide-y divide-hairline">
            {rows.map(([label, value, note]) => (
              <tr key={label} className="transition-colors hover:bg-surface-2/40">
                <th scope="row" className="w-48 px-5 py-4 font-medium text-ink">
                  {label}
                </th>
                <td className="tabular w-28 px-5 py-4 font-display font-semibold text-astra-200">
                  {value}
                </td>
                <td className="px-5 py-4 text-ink-faint">{note}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </section>
  );
}

// ─── CTA + footer ─────────────────────────────────────────────────────────────

function FinalCta() {
  return (
    <section className="mx-auto max-w-6xl px-5 pb-24">
      <Card glow className="relative overflow-hidden px-6 py-14 text-center sm:px-12">
        <div
          className="pointer-events-none absolute inset-x-0 -bottom-32 h-64 opacity-70 blur-3xl"
          style={{
            background:
              "radial-gradient(ellipse at 50% 0%, rgba(124,58,237,0.45), rgba(124,58,237,0) 70%)",
          }}
          aria-hidden
        />
        <h2 className="relative font-display text-3xl font-semibold tracking-tight text-ink sm:text-4xl">
          Put your collateral to work
        </h2>
        <p className="relative mx-auto mt-3 max-w-xl text-ink-muted">
          Connect a wallet on Ethereum Sepolia or Arbitrum Sepolia. Testnet assets are one click
          away from the dashboard.
        </p>
        <div className="relative mt-8 flex justify-center gap-3">
          <LinkButton href="/app" size="lg">
            Open the dashboard
          </LinkButton>
          <LinkButton href="/app/borrow" variant="secondary" size="lg">
            Borrow now
          </LinkButton>
        </div>
      </Card>
    </section>
  );
}

function SiteFooter() {
  return (
    <footer className="border-t border-hairline/60 py-10">
      <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-6 px-5 sm:flex-row sm:items-center">
        <div>
          <Logo />
          <p className="mt-3 max-w-sm text-xs leading-relaxed text-ink-faint">
            A cross-chain lending protocol running on Ethereum Sepolia and Arbitrum Sepolia.
            Testnet software — assets have no value.
          </p>
        </div>
        <nav className="flex flex-wrap gap-x-6 gap-y-2 text-sm text-ink-muted">
          <Link href="/app" className="transition hover:text-ink">
            Dashboard
          </Link>
          <Link href="/app/markets" className="transition hover:text-ink">
            Markets
          </Link>
          <Link href="/app/borrow" className="transition hover:text-ink">
            Borrow
          </Link>
          <Link href="/app/portfolio" className="transition hover:text-ink">
            Portfolio
          </Link>
        </nav>
      </div>
    </footer>
  );
}

function SectionHeading({
  eyebrow,
  title,
  body,
}: {
  eyebrow: string;
  title: string;
  body: string;
}) {
  return (
    <div className="max-w-2xl">
      <p className="text-[11px] font-semibold uppercase tracking-[0.2em] text-astra-400">
        {eyebrow}
      </p>
      <h2 className="mt-3 font-display text-3xl font-semibold tracking-tight text-ink sm:text-4xl">
        {title}
      </h2>
      <p className="mt-4 leading-relaxed text-ink-muted">{body}</p>
    </div>
  );
}
