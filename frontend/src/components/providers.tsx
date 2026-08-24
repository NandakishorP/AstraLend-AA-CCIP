"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createContext, useContext, useMemo, useState, type ReactNode } from "react";
import { WagmiProvider, useAccount } from "wagmi";
import { chainKeyFromId, wagmiConfig } from "@/lib/chains";
import type { ChainKey } from "@/lib/types";
import { ToastProvider } from "./ui/toast";

/**
 * The chain the UI is *reading* from.
 *
 * This is deliberately separate from the wallet's connected chain. A user can
 * inspect Ethereum markets while their wallet sits on Arbitrum; the action
 * modals detect the mismatch and prompt a switch only when they need to sign.
 * Once a wallet connects to a chain the protocol supports, the view follows it.
 */
const ChainKeyContext = createContext<{
  chainKey: ChainKey;
  setChainKey: (key: ChainKey) => void;
}>({ chainKey: "eth", setChainKey: () => {} });

export function useChainKey(): ChainKey {
  return useContext(ChainKeyContext).chainKey;
}

export function useChainKeyControl() {
  return useContext(ChainKeyContext);
}

function ChainKeyProvider({ children }: { children: ReactNode }) {
  const { chainId, isConnected } = useAccount();
  const walletChain = isConnected ? chainKeyFromId(chainId) : undefined;

  // The view chain is derived, with an explicit user choice layered on top. The
  // choice is remembered alongside the wallet chain it was made against, so a
  // later wallet-side network switch takes over again instead of being ignored
  // forever. Derived-with-memory rather than an effect: no cascading render.
  const [choice, setChoice] = useState<{ key: ChainKey; whileWalletOn: ChainKey | undefined } | null>(
    null
  );

  const choiceIsStale = choice !== null && choice.whileWalletOn !== walletChain;
  const chainKey = choiceIsStale ? (walletChain ?? "eth") : (choice?.key ?? walletChain ?? "eth");

  const value = useMemo(
    () => ({
      chainKey,
      setChainKey: (key: ChainKey) => setChoice({ key, whileWalletOn: walletChain }),
    }),
    [chainKey, walletChain]
  );

  return <ChainKeyContext.Provider value={value}>{children}</ChainKeyContext.Provider>;
}

export function Providers({ children }: { children: ReactNode }) {
  // One client per mount, kept in state so React's strict-mode double render
  // does not discard the cache between passes.
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            retry: 1,
            refetchOnWindowFocus: false,
            // Chain reads are always "stale" in principle; the poll intervals
            // set per hook decide how aggressively each one refreshes.
            staleTime: 5_000,
          },
        },
      })
  );

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <ChainKeyProvider>
          <ToastProvider>{children}</ToastProvider>
        </ChainKeyProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
