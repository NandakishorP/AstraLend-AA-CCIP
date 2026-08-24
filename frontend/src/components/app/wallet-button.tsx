"use client";

import { useEffect, useRef, useState } from "react";
import { useAccount, useBalance, useConnect, useDisconnect } from "wagmi";
import { CHAINS, chainKeyFromId, explorerAddress } from "@/lib/chains";
import { formatEth, shortAddress } from "@/lib/format";
import { Badge, Button, cx, Spinner } from "@/components/ui/primitives";

/**
 * Wallet connect / account control.
 *
 * Connector choice is a menu rather than a modal: with two injected connectors
 * there is nothing to explain, and a popover keeps the user on the page.
 */
export function WalletButton() {
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, isPending, variables } = useConnect();
  const { disconnect } = useDisconnect();
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const { data: balance } = useBalance({ address, query: { enabled: Boolean(address) } });

  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: MouseEvent) {
      if (!containerRef.current?.contains(event.target as Node)) setOpen(false);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  // Deduplicate connectors: MetaMask usually shows up as both a named connector
  // and the generic injected provider.
  const uniqueConnectors = connectors.filter(
    (connector, index, all) => all.findIndex((c) => c.name === connector.name) === index
  );

  const walletChain = chainKeyFromId(chainId);
  const unsupportedChain = isConnected && !walletChain;

  if (!isConnected) {
    return (
      <div ref={containerRef} className="relative">
        <Button onClick={() => setOpen((value) => !value)} loading={isPending}>
          {isPending ? "Connecting…" : "Connect wallet"}
        </Button>

        {open ? (
          <div className="absolute right-0 top-full z-50 mt-2 w-64 animate-rise overflow-hidden rounded-xl border border-hairline bg-surface/95 p-1.5 shadow-2xl backdrop-blur-xl">
            <p className="px-3 py-2 text-[11px] font-medium uppercase tracking-[0.14em] text-ink-faint">
              Choose a wallet
            </p>
            {uniqueConnectors.map((connector) => (
              <button
                key={connector.uid}
                onClick={() => {
                  connect({ connector });
                  setOpen(false);
                }}
                className="flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-left text-sm text-ink transition hover:bg-surface-2"
              >
                {connector.name}
                {isPending && variables?.connector === connector ? <Spinner /> : null}
              </button>
            ))}
            <p className="px-3 pb-2 pt-3 text-[11px] leading-relaxed text-ink-faint">
              No wallet installed? Any EIP-1193 browser wallet works — MetaMask, Rabby, Frame.
            </p>
          </div>
        ) : null}
      </div>
    );
  }

  return (
    <div ref={containerRef} className="relative">
      <button
        onClick={() => setOpen((value) => !value)}
        className={cx(
          "flex h-10 items-center gap-2.5 rounded-xl border border-hairline bg-surface-2/70 pl-2.5 pr-3 text-sm transition",
          "hover:border-astra-400/45 hover:bg-surface-2"
        )}
      >
        <AddressAvatar address={address as string} />
        <span className="tabular font-medium text-ink">{shortAddress(address)}</span>
        <svg viewBox="0 0 16 16" className="size-3.5 text-ink-faint" fill="none" stroke="currentColor" strokeWidth="1.8">
          <path d="M4 6.5L8 10.5l4-4" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open ? (
        <div className="absolute right-0 top-full z-50 mt-2 w-72 animate-rise overflow-hidden rounded-xl border border-hairline bg-surface/95 shadow-2xl backdrop-blur-xl">
          <div className="border-b border-hairline p-4">
            <div className="flex items-center gap-3">
              <AddressAvatar address={address as string} size={36} />
              <div className="min-w-0">
                <p className="tabular truncate text-sm font-medium text-ink">
                  {shortAddress(address, 6)}
                </p>
                <p className="tabular text-xs text-ink-faint">
                  {balance ? formatEth(balance.value) : "—"}
                </p>
              </div>
            </div>

            {unsupportedChain ? (
              <Badge tone="danger" className="mt-3">
                Unsupported network
              </Badge>
            ) : (
              <Badge tone="accent" className="mt-3">
                {walletChain ? CHAINS[walletChain].name : ""}
              </Badge>
            )}
          </div>

          <div className="p-1.5">
            <MenuAction
              label="Copy address"
              onClick={() => {
                void navigator.clipboard.writeText(address as string);
                setOpen(false);
              }}
            />
            {walletChain ? (
              <MenuLink
                label="View on explorer"
                href={explorerAddress(walletChain, address as string)}
              />
            ) : null}
            <MenuAction
              label="Disconnect"
              tone="danger"
              onClick={() => {
                disconnect();
                setOpen(false);
              }}
            />
          </div>
        </div>
      ) : null}
    </div>
  );
}

function MenuAction({
  label,
  onClick,
  tone = "default",
}: {
  label: string;
  onClick: () => void;
  tone?: "default" | "danger";
}) {
  return (
    <button
      onClick={onClick}
      className={cx(
        "w-full rounded-lg px-3 py-2 text-left text-sm transition",
        tone === "danger"
          ? "text-rose hover:bg-rose/10"
          : "text-ink-muted hover:bg-surface-2 hover:text-ink"
      )}
    >
      {label}
    </button>
  );
}

function MenuLink({ label, href }: { label: string; href: string }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className="block rounded-lg px-3 py-2 text-sm text-ink-muted transition hover:bg-surface-2 hover:text-ink"
    >
      {label} ↗
    </a>
  );
}

/** Deterministic gradient avatar derived from the address bytes. */
export function AddressAvatar({ address, size = 24 }: { address: string; size?: number }) {
  const seed = parseInt(address.slice(2, 8), 16);
  const hue = seed % 360;
  return (
    <span
      className="inline-block shrink-0 rounded-full"
      style={{
        width: size,
        height: size,
        background: `conic-gradient(from ${seed % 360}deg, hsl(${hue} 85% 62%), hsl(${(hue + 90) % 360} 85% 58%), hsl(${(hue + 200) % 360} 85% 62%), hsl(${hue} 85% 62%))`,
        boxShadow: "inset 0 0 0 1px rgb(255 255 255 / 0.12)",
      }}
    />
  );
}
