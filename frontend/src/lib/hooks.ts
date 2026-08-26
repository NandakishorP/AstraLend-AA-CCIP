"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback } from "react";
import { useAccount } from "wagmi";
import { api } from "./api";
import { useChainKey } from "@/components/providers";
import type { ChainKey, Range } from "./types";

/**
 * Poll intervals.
 *
 * Market data is cheap and visibly stale within a block, so it refreshes often.
 * Activity scans logs across a wide block range, so it refreshes lazily and
 * relies on invalidation after a transaction lands instead.
 */
const MARKET_POLL_MS = 12_000;
const PORTFOLIO_POLL_MS = 15_000;

export function useMarkets(chainOverride?: ChainKey) {
  const active = useChainKey();
  const chain = chainOverride ?? active;

  return useQuery({
    queryKey: ["markets", chain],
    queryFn: () => api.markets(chain),
    refetchInterval: MARKET_POLL_MS,
    staleTime: MARKET_POLL_MS / 2,
  });
}

export function usePortfolio() {
  const chain = useChainKey();
  const { address } = useAccount();

  return useQuery({
    queryKey: ["portfolio", chain, address],
    queryFn: () => api.portfolio(address as string, chain),
    enabled: Boolean(address),
    refetchInterval: PORTFOLIO_POLL_MS,
  });
}

export function useActivity(limit = 40) {
  const chain = useChainKey();
  const { address } = useAccount();

  return useQuery({
    queryKey: ["activity", chain, address, limit],
    queryFn: () => api.activity(address as string, chain, limit),
    enabled: Boolean(address),
    staleTime: 30_000,
  });
}

export function useFaucetStatus() {
  const chain = useChainKey();

  return useQuery({
    queryKey: ["faucet", chain],
    queryFn: () => api.faucetStatus(chain),
    staleTime: 5 * 60_000,
    retry: false,
  });
}

export function useReadiness() {
  return useQuery({
    queryKey: ["readiness"],
    queryFn: () => api.readiness(),
    refetchInterval: 60_000,
    retry: false,
  });
}

/**
 * Invalidates every read that a completed transaction could have changed.
 *
 * Called once a receipt is mined. Cross-chain operations settle asynchronously,
 * so the polling intervals — not this call — are what eventually surface the
 * mirrored state on the hub chain.
 */
export function useRefreshAfterTx() {
  const queryClient = useQueryClient();

  return useCallback(() => {
    void queryClient.invalidateQueries({ queryKey: ["markets"] });
    void queryClient.invalidateQueries({ queryKey: ["portfolio"] });
    void queryClient.invalidateQueries({ queryKey: ["activity"] });
  }, [queryClient]);
}

// ─── Indexed analytics ────────────────────────────────────────────────────────
// These read the backend's database rather than the chain. They are cheap, so
// they refresh often enough to feel live as actions land.

export function useProtocolHistory(range: Range = "24h") {
  const chain = useChainKey();

  return useQuery({
    queryKey: ["protocol-history", chain, range],
    queryFn: () => api.protocolHistory(chain, range),
    refetchInterval: MARKET_POLL_MS,
  });
}

export function useMarketHistory(tokenId: number | null, range: Range = "24h") {
  const chain = useChainKey();

  return useQuery({
    queryKey: ["market-history", chain, tokenId, range],
    queryFn: () => api.marketHistory(chain, tokenId as number, range),
    enabled: tokenId !== null,
    refetchInterval: MARKET_POLL_MS,
  });
}

export function useProtocolStats() {
  const chain = useChainKey();

  return useQuery({
    queryKey: ["protocol-stats", chain],
    queryFn: () => api.protocolStats(chain),
    refetchInterval: 20_000,
  });
}

export function useCrossChainFeed(limit = 15) {
  return useQuery({
    queryKey: ["cross-chain-feed", limit],
    queryFn: () => api.crossChainFeed(limit),
    // Cross-chain messages are the thing a viewer watches most closely during a
    // demo, so this polls faster than anything else in the app.
    refetchInterval: 4000,
  });
}

export function useIndexerStatus() {
  return useQuery({
    queryKey: ["indexer-status"],
    queryFn: () => api.indexerStatus(),
    refetchInterval: 10_000,
    retry: false,
  });
}

// ─── Real-world asset collateral ──────────────────────────────────────────────

/**
 * Whether this deployment has the RWA module wired.
 *
 * Retries are off and failure is not an error state the UI shows — a deployment
 * without the module is a normal configuration, not a fault.
 */
export function useRwaStatus() {
  return useQuery({
    queryKey: ["rwa-status"],
    queryFn: () => api.rwaStatus(),
    retry: false,
    staleTime: 60_000,
  });
}

/**
 * NAV and accretion progress.
 *
 * Polled slowly on purpose. A bill's value moves by arithmetic over 91 days,
 * so there is nothing to catch by asking often.
 */
export function useRwaNav(enabled = true) {
  return useQuery({
    queryKey: ["rwa-nav"],
    queryFn: () => api.rwaNav(),
    enabled,
    refetchInterval: 30_000,
    retry: false,
  });
}

export function useRwaHolding(enabled = true) {
  const { address } = useAccount();
  return useQuery({
    queryKey: ["rwa-holding", address],
    queryFn: () => api.rwaHolding(address as string),
    enabled: enabled && Boolean(address),
    refetchInterval: 12_000,
    retry: false,
  });
}

export function useRwaLien(enabled = true) {
  const { address } = useAccount();
  return useQuery({
    queryKey: ["rwa-lien", address],
    queryFn: () => api.rwaLien(address as string),
    enabled: enabled && Boolean(address),
    refetchInterval: 12_000,
    retry: false,
  });
}

/**
 * Agent rights on the security.
 *
 * Worth its own hook because it is the one precondition that makes the whole
 * RWA path work, and a deployment missing it looks fine until someone pledges.
 */
export function useRwaAgency(enabled = true) {
  return useQuery({
    queryKey: ["rwa-agency"],
    queryFn: () => api.rwaAgency(),
    enabled,
    retry: false,
    staleTime: 60_000,
  });
}
