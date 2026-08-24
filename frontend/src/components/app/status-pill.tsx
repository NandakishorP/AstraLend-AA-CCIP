"use client";

import { useReadiness } from "@/lib/hooks";
import { useChainKey } from "@/components/providers";
import { Dot } from "@/components/ui/primitives";

/**
 * Backend/RPC health indicator.
 *
 * Every number in the app comes through the API, so when it degrades the user
 * should see why before they start wondering about stale balances.
 */
export function StatusPill() {
  const chain = useChainKey();
  const { data, isLoading, isError } = useReadiness();

  const chainHealth = data?.chains?.[chain];
  const healthy = !isError && data?.status === "ready" && chainHealth?.status === "ok";

  const label = isLoading
    ? "Checking…"
    : isError
      ? "API offline"
      : healthy
        ? `Block ${chainHealth?.blockNumber?.toLocaleString() ?? "—"}`
        : "Degraded";

  const tone = isLoading ? "neutral" : isError ? "danger" : healthy ? "safe" : "warn";

  const title = isError
    ? "The AstraLend API is unreachable. Start the backend, or check NEXT_PUBLIC_API_BASE_URL."
    : chainHealth?.message ??
      (healthy
        ? `Connected to ${chainHealth?.chainId} · ${chainHealth?.latencyMs}ms RPC latency`
        : "Some chains are unreachable.");

  return (
    <span
      title={title}
      className="hidden items-center gap-2 rounded-full border border-hairline bg-surface-2/50 px-3 py-1.5 text-[11px] text-ink-faint lg:inline-flex"
    >
      <Dot tone={tone} pulse={healthy} />
      <span className="tabular">{label}</span>
    </span>
  );
}
