import { ethers } from "ethers";
import { env, type ChainKey } from "../config/env.js";
import { GAS_BUFFER_PERCENT, MAX_TX_RETRIES, RETRY_BASE_DELAY_MS, TX_TIMEOUT_MS } from "../config/constants.js";
import { getProvider } from "./providers.js";
import { decodeContractError } from "./decoder.js";
import { BlockchainError } from "../errors.js";

// ─── Nonce Manager ────────────────────────────────────────────────────────────
//
// Serialises ALL transaction submissions through a single promise queue per chain.
// This prevents nonce collisions whether the race is between two route handlers
// or between an ERC-20 approval and the main contract call that follows it.
//
// Key invariant: every tx — approvals AND contract calls — must go through
// NonceManager.submit(). Never call signer.sendTransaction() directly.

class NonceManager {
  private nonce: number | null = null;
  private queue: Promise<unknown> = Promise.resolve();

  constructor(private readonly wallet: ethers.Wallet) {}

  /**
   * Enqueues `txBuilder` onto the serial promise queue.
   * Guarantees that nonces are assigned in submission order with no gaps.
   */
  submit<T>(txBuilder: (nonce: number) => Promise<T>): Promise<T> {
    const next = this.queue.then(async (): Promise<T> => {
      if (this.nonce === null) {
        // Re-sync from chain after error or on first call
        this.nonce = await this.wallet.getNonce("pending");
      }
      const nonce = this.nonce;
      try {
        const result = await txBuilder(nonce);
        this.nonce = nonce + 1; // Optimistic advance
        return result;
      } catch (err) {
        this.nonce = null; // Force re-sync on next call
        throw err;
      }
    });

    // Keep the queue rolling even when individual txs fail
    this.queue = next.then(() => {}, () => {});
    return next;
  }

  invalidate(): void {
    this.nonce = null;
  }
}

// ─── Wallet / signer pool ─────────────────────────────────────────────────────

const signerCache = new Map<ChainKey, ethers.Wallet>();
const nonceManagerCache = new Map<ChainKey, NonceManager>();

export function getSigner(chain: ChainKey): ethers.Wallet {
  const cached = signerCache.get(chain);
  if (cached) return cached;
  const provider = getProvider(chain);
  const signer = new ethers.Wallet(env.PRIVATE_KEY, provider);
  signerCache.set(chain, signer);
  nonceManagerCache.set(chain, new NonceManager(signer));
  return signer;
}

function getNonceManager(chain: ChainKey): NonceManager {
  getSigner(chain); // Ensures both wallet and nonce manager are initialised
  return nonceManagerCache.get(chain) as NonceManager;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function estimateGas(
  contract: ethers.Contract,
  method: string,
  args: unknown[],
  overrides: ethers.Overrides
): Promise<bigint> {
  const fn = contract[method] as ethers.BaseContractMethod | undefined;
  if (!fn) throw new BlockchainError(`Contract has no method: ${method}`);
  const estimated: bigint = await fn.estimateGas(...args, overrides);
  return (estimated * (100n + GAS_BUFFER_PERCENT)) / 100n;
}

function isRetryableError(err: unknown): boolean {
  const msg = (err as Error)?.message?.toLowerCase() ?? "";
  return (
    msg.includes("network error") ||
    msg.includes("timeout") ||
    msg.includes("rate limit") ||
    msg.includes("econnreset") ||
    msg.includes("econnrefused") ||
    msg.includes("502") ||
    msg.includes("503") ||
    msg.includes("504")
  );
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitWithTimeout(
  tx: ethers.TransactionResponse
): Promise<ethers.TransactionReceipt> {
  const receipt = await tx.wait(1, TX_TIMEOUT_MS);
  if (!receipt) {
    throw new BlockchainError(
      `Transaction ${tx.hash} was not mined within ${TX_TIMEOUT_MS / 1000}s`,
      { txHash: tx.hash }
    );
  }
  return receipt;
}

// ─── Public API ───────────────────────────────────────────────────────────────

export interface TxResult {
  txHash: string;
  blockNumber: number;
  gasUsed: string;
}

/**
 * Sends a contract call through the NonceManager queue.
 * Includes gas estimation (+ buffer), retry on transient errors,
 * and Solidity custom error decoding on revert.
 */
export async function sendTransaction(
  chain: ChainKey,
  contract: ethers.Contract,
  method: string,
  args: unknown[],
  overrides: ethers.Overrides & { value?: bigint } = {}
): Promise<TxResult> {
  const nonceManager = getNonceManager(chain);
  let lastErr: unknown;

  for (let attempt = 1; attempt <= MAX_TX_RETRIES; attempt++) {
    try {
      const gasLimit = await estimateGas(contract, method, args, overrides);
      const fn = contract[method] as ethers.BaseContractMethod;

      const receipt = await nonceManager.submit(async (nonce) => {
        const tx = await fn(...args, { ...overrides, nonce, gasLimit }) as ethers.TransactionResponse;
        return waitWithTimeout(tx);
      });

      return {
        txHash: receipt.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
      };
    } catch (err) {
      lastErr = err;
      decodeContractError(err); // Throws ContractError for known Solidity reverts
      if (!isRetryableError(err)) throw err;
      if (attempt < MAX_TX_RETRIES) await sleep(RETRY_BASE_DELAY_MS * 2 ** (attempt - 1));
    }
  }

  throw new BlockchainError(
    `Transaction failed after ${MAX_TX_RETRIES} attempts: ${(lastErr as Error)?.message}`,
    lastErr
  );
}

/**
 * Sends any raw transaction through the NonceManager.
 * Use this for transactions that cannot go through `sendTransaction`
 * (e.g., ERC-20 approvals where you need the contract method directly).
 *
 * This is what approval.service.ts uses — it guarantees that approval txs
 * are serialised on the same queue as contract txs, preventing nonce collisions.
 */
export async function sendRaw(
  chain: ChainKey,
  txBuilder: (nonce: number, signer: ethers.Wallet) => Promise<ethers.TransactionResponse>
): Promise<TxResult> {
  const nonceManager = getNonceManager(chain);
  const signer = getSigner(chain);
  let lastErr: unknown;

  for (let attempt = 1; attempt <= MAX_TX_RETRIES; attempt++) {
    try {
      const receipt = await nonceManager.submit(async (nonce) => {
        const tx = await txBuilder(nonce, signer);
        return waitWithTimeout(tx);
      });
      return {
        txHash: receipt.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
      };
    } catch (err) {
      lastErr = err;
      decodeContractError(err);
      if (!isRetryableError(err)) throw err;
      if (attempt < MAX_TX_RETRIES) await sleep(RETRY_BASE_DELAY_MS * 2 ** (attempt - 1));
    }
  }

  throw new BlockchainError(
    `Raw transaction failed after ${MAX_TX_RETRIES} attempts: ${(lastErr as Error)?.message}`,
    lastErr
  );
}
