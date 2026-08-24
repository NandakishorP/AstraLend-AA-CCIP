"use client";

import { useSyncExternalStore, type ReactNode } from "react";
import { useAccount } from "wagmi";
import { Card } from "@/components/ui/primitives";
import { WalletButton } from "./wallet-button";
import { LogoMark } from "@/components/site/logo";

/**
 * Renders `children` only once a wallet is connected.
 *
 * Wagmi resolves the connection asynchronously after hydration, so the gate
 * holds a neutral placeholder on the first client render. Flashing "connect
 * your wallet" at an already-connected user is worse than a beat of nothing.
 */
/**
 * True only after hydration. Reads as `false` on the server and on the first
 * client pass, which is exactly what the gate needs, without an effect that
 * would trigger a second render pass on every mount.
 */
function useIsMounted(): boolean {
  return useSyncExternalStore(
    () => () => {},
    () => true,
    () => false
  );
}

export function ConnectGate({
  children,
  title = "Connect your wallet",
  body = "Your positions, loans and activity are read straight from the chain — nothing to sign up for.",
}: {
  children: ReactNode;
  title?: string;
  body?: string;
}) {
  const { isConnected, isConnecting, isReconnecting } = useAccount();
  const mounted = useIsMounted();

  if (!mounted || isConnecting || isReconnecting) {
    return <div className="h-64" aria-hidden />;
  }

  if (isConnected) return <>{children}</>;

  return (
    <Card glow className="mx-auto max-w-md px-6 py-12 text-center">
      <div className="mx-auto flex size-14 items-center justify-center rounded-2xl border border-astra-400/30 bg-astra-500/10">
        <LogoMark className="size-7" />
      </div>
      <h2 className="mt-5 font-display text-lg font-semibold text-ink">{title}</h2>
      <p className="mx-auto mt-2 max-w-xs text-sm leading-relaxed text-ink-muted">{body}</p>
      <div className="mt-6 flex justify-center">
        <WalletButton />
      </div>
    </Card>
  );
}
