"use client";

import { useCallback, useState } from "react";
import { useAccount, useConfig } from "wagmi";
import { sendTransaction, switchChain, waitForTransactionReceipt } from "wagmi/actions";
import { ApiError } from "./api";
import { CHAINS, explorerTx } from "./chains";
import { useRefreshAfterTx } from "./hooks";
import { useToast } from "@/components/ui/toast";
import type { BuildResult, ChainKey } from "./types";

export interface TxRunState {
  /** Index of the transaction currently awaiting signature or confirmation. */
  step: number;
  total: number;
  phase: "idle" | "building" | "signing" | "confirming" | "done" | "error";
  error: string | null;
  hashes: string[];
}

const IDLE: TxRunState = { step: 0, total: 0, phase: "idle", error: null, hashes: [] };

/**
 * Runs a backend-built transaction sequence through the connected wallet.
 *
 * A protocol action is one or two transactions — an optional ERC-20 approval
 * followed by the action itself — and they must land in order. The backend
 * builds them unsigned; this hook signs and submits them one at a time, waiting
 * for each receipt before moving on, so the second transaction is never
 * simulated against an allowance that has not been mined yet.
 *
 * Failures are surfaced verbatim from either the wallet (user rejection) or the
 * backend, which has already decoded Solidity custom errors into plain English.
 */
export function useTxRunner() {
  const config = useConfig();
  const { address, chainId } = useAccount();
  const toast = useToast();
  const refresh = useRefreshAfterTx();
  const [state, setState] = useState<TxRunState>(IDLE);

  const reset = useCallback(() => setState(IDLE), []);

  const run = useCallback(
    async (
      chain: ChainKey,
      label: string,
      build: () => Promise<BuildResult>
    ): Promise<boolean> => {
      if (!address) {
        toast.push({ tone: "error", title: "Connect a wallet first" });
        return false;
      }

      const target = CHAINS[chain];
      setState({ ...IDLE, phase: "building" });

      // The wallet must be on the same chain the transaction was built for,
      // otherwise it would be submitted to the wrong network.
      if (chainId !== target.id) {
        try {
          await switchChain(config, { chainId: target.id as 424242 | 421614 });
        } catch {
          setState({ ...IDLE, phase: "error", error: `Switch your wallet to ${target.name}.` });
          toast.push({
            tone: "error",
            title: "Wrong network",
            body: `This action runs on ${target.name}. Approve the network switch in your wallet and try again.`,
          });
          return false;
        }
      }

      let plan: BuildResult;
      try {
        plan = await build();
      } catch (error) {
        const message = error instanceof ApiError ? error.message : "Could not build the transaction.";
        setState({ ...IDLE, phase: "error", error: message });
        toast.push({ tone: "error", title: `${label} failed`, body: message });
        return false;
      }

      const total = plan.transactions.length;
      const hashes: string[] = [];
      const toastId = toast.push({
        tone: "pending",
        title: label,
        body: plan.summary,
      });

      for (const [index, tx] of plan.transactions.entries()) {
        setState({ step: index, total, phase: "signing", error: null, hashes });
        toast.update(toastId, {
          body: total > 1 ? `Step ${index + 1} of ${total} — ${tx.description}` : tx.description,
        });

        let hash: `0x${string}`;
        try {
          hash = await sendTransaction(config, {
            to: tx.to as `0x${string}`,
            data: tx.data as `0x${string}`,
            value: BigInt(tx.value),
            gas: BigInt(tx.gasLimit),
          });
        } catch (error) {
          const message = walletErrorMessage(error);
          setState({ step: index, total, phase: "error", error: message, hashes });
          toast.update(toastId, { tone: "error", title: `${label} cancelled`, body: message });
          return false;
        }

        hashes.push(hash);
        setState({ step: index, total, phase: "confirming", error: null, hashes });
        toast.update(toastId, {
          body: `Waiting for confirmation — ${tx.description}`,
          link: { href: explorerTx(chain, hash), label: "View transaction" },
        });

        try {
          // Bounded wait. A receipt that never arrives used to leave the
          // dialog stuck on "Confirming" with no way out, even though the
          // transaction had already landed — so give up after a while and tell
          // the user to check, rather than spinning forever.
          const receipt = await waitForTransactionReceipt(config, {
            hash,
            chainId: target.id as 424242 | 421614,
            timeout: 60_000,
          });
          if (receipt.status === "reverted") {
            const message = "The transaction was mined but reverted on-chain.";
            setState({ step: index, total, phase: "error", error: message, hashes });
            toast.update(toastId, { tone: "error", title: `${label} reverted`, body: message });
            return false;
          }
        } catch (error) {
          const message = walletErrorMessage(error);
          setState({ step: index, total, phase: "error", error: message, hashes });
          toast.update(toastId, { tone: "error", title: `${label} failed`, body: message });
          return false;
        }
      }

      setState({ step: total, total, phase: "done", error: null, hashes });
      toast.update(toastId, {
        tone: "success",
        title: `${label} confirmed`,
        body:
          chain === "eth"
            ? plan.summary
            : `${plan.summary}. Cross-chain state settles on Ethereum once CCIP delivers the message.`,
      });
      refresh();
      return true;
    },
    [address, chainId, config, refresh, toast]
  );

  return { run, state, reset };
}

/**
 * Turns a wallet/provider error into something worth showing a user.
 *
 * Patterns are matched against the first line only. viem appends the full
 * request body to its messages — which contains the words "nonce", "gas" and
 * "value" on every single error — so matching the whole string would
 * misclassify almost everything.
 */
function walletErrorMessage(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  const headline = raw.split("\n").find((line) => line.trim().length > 0)?.trim() ?? "";

  if (/user rejected|denied transaction|user denied/i.test(headline)) {
    return "You rejected the request in your wallet.";
  }
  if (/insufficient funds/i.test(headline)) {
    return "Not enough native balance to cover gas and any CCIP fee.";
  }
  if (/nonce too (low|high)|invalid nonce|nonce has already been used/i.test(raw)) {
    return "Nonce conflict — reset your wallet's account activity and retry.";
  }
  if (/reverted|execution failed/i.test(headline)) {
    // Surface the revert reason viem extracted, when it found one.
    const reason = raw.match(/reason:\s*(.+)/i)?.[1]?.trim();
    return reason
      ? `The contract rejected this transaction: ${reason}`
      : "The contract rejected this transaction.";
  }
  return headline || "The transaction failed.";
}
