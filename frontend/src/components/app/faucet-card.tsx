"use client";

import { useMutation } from "@tanstack/react-query";
import { useAccount } from "wagmi";
import { api, ApiError } from "@/lib/api";
import { useChainKey } from "@/components/providers";
import { useFaucetStatus, useRefreshAfterTx } from "@/lib/hooks";
import { useToast } from "@/components/ui/toast";
import { Button, Card, CardHeader, TokenGlyph } from "@/components/ui/primitives";

/**
 * Testnet faucet.
 *
 * Renders only when the deployment can actually mint — the backend reports which
 * assets are mintable by static-calling `mint`, so a mainnet-style deployment
 * simply never shows this card instead of offering a button that reverts.
 */
export function FaucetCard() {
  const chain = useChainKey();
  const { address } = useAccount();
  const { data: status } = useFaucetStatus();
  const toast = useToast();
  const refresh = useRefreshAfterTx();

  const drip = useMutation({
    mutationFn: (target: string) => api.drip(target, address as string, "25", chain),
    onSuccess: (result) => {
      toast.push({
        tone: "success",
        title: `Received test ${result.symbol}`,
        body: "Tokens are in your wallet — supply them or post them as collateral.",
      });
      refresh();
    },
    onError: (error) => {
      toast.push({
        tone: "error",
        title: "Faucet request failed",
        body: error instanceof ApiError ? error.message : "Unknown error.",
      });
    },
  });

  const mintable = status?.assets.filter((asset) => asset.mintable) ?? [];
  if (!address || !status?.available || mintable.length === 0) return null;

  return (
    <Card>
      <CardHeader
        title="Testnet faucet"
        subtitle="Mint mock assets so you can walk the full deposit → borrow → repay flow."
      />
      <div className="flex flex-wrap gap-2 p-4">
        {mintable.map((asset) => (
          <Button
            key={asset.target}
            variant="secondary"
            size="sm"
            loading={drip.isPending && drip.variables === asset.target}
            disabled={drip.isPending}
            onClick={() => drip.mutate(asset.target)}
          >
            <TokenGlyph symbol={asset.symbol} size={18} />
            Get 25 {asset.symbol}
          </Button>
        ))}
      </div>
    </Card>
  );
}
