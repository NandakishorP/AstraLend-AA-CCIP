"use client";

import { useAccount, useSwitchChain } from "wagmi";
import { CHAIN_LIST, CHAINS } from "@/lib/chains";
import { useChainKeyControl } from "@/components/providers";
import { cx } from "@/components/ui/primitives";

/**
 * Switches the chain the app reads from.
 *
 * When a wallet is connected the switch is pushed to the wallet too, so the
 * view and the signer stay aligned; if the user declines, the view still moves
 * and the action modals will re-prompt at signing time.
 */
export function ChainSwitcher() {
  const { chainKey, setChainKey } = useChainKeyControl();
  const { isConnected } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  return (
    <div
      className="flex items-center gap-0.5 rounded-xl border border-hairline bg-surface-2/60 p-1"
      role="tablist"
      aria-label="Active chain"
    >
      {CHAIN_LIST.map((chain) => {
        const active = chain.key === chainKey;
        return (
          <button
            key={chain.key}
            role="tab"
            aria-selected={active}
            disabled={isPending}
            onClick={() => {
              setChainKey(chain.key);
              if (isConnected) switchChain({ chainId: chain.id as 424242 | 421614 });
            }}
            className={cx(
              "flex h-8 items-center gap-2 rounded-lg px-3 text-xs font-medium transition disabled:opacity-60",
              active ? "bg-surface text-ink shadow-sm" : "text-ink-faint hover:text-ink-muted"
            )}
          >
            <span
              className="size-1.5 rounded-full"
              style={{ background: active ? CHAINS[chain.key].accent : "currentColor" }}
            />
            {chain.shortName}
          </button>
        );
      })}
    </div>
  );
}
