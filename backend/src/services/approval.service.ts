import { ethers } from "ethers";
import { type ChainKey, requireAddress } from "../config/env.js";
import { getERC20Write, getERC20Read } from "../blockchain/contracts.js";
import { getSigner, sendRaw } from "../blockchain/wallet.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";

export interface ApprovalResult {
  wasNeeded: boolean;
  txHash: string | null;
  blockNumber: number | null;
  gasUsed: string | null;
}

/**
 * Ensures the Vault is approved to spend at least `requiredAmount` of `tokenAddress`
 * on behalf of the configured signer wallet.
 *
 * If the allowance already covers the amount, no transaction is sent.
 * Otherwise approves MaxUint256 to avoid repeated approvals.
 *
 * IMPORTANT: the approval transaction is submitted through `sendRaw`, which routes
 * it through the same NonceManager queue as all contract calls. This prevents
 * nonce collisions when the approval and the subsequent deposit/repay land in
 * the same block under concurrent load.
 */
export async function ensureVaultApproval(
  tokenAddress: string,
  requiredAmount: bigint,
  chain: ChainKey
): Promise<ApprovalResult> {
  try {
    const vaultAddress = requireAddress(chain, "vault");
    const tokenRead = getERC20Read(tokenAddress, chain);
    const signer = getSigner(chain);

    const allowance: bigint = await tokenRead.allowance(signer.address, vaultAddress);
    if (allowance >= requiredAmount) {
      return { wasNeeded: false, txHash: null, blockNumber: null, gasUsed: null };
    }

    // Route through NonceManager so this tx is serialised with the main tx that follows
    const result = await sendRaw(chain, async (nonce, _signer) => {
      const tokenWrite = getERC20Write(tokenAddress, chain);
      // Estimate gas + 20% buffer
      const gasEstimate: bigint = await tokenWrite.approve.estimateGas(
        vaultAddress,
        ethers.MaxUint256
      );
      const gasLimit = (gasEstimate * 120n) / 100n;
      return tokenWrite.approve(vaultAddress, ethers.MaxUint256, {
        nonce,
        gasLimit,
      }) as Promise<ethers.TransactionResponse>;
    });

    return {
      wasNeeded: true,
      txHash: result.txHash,
      blockNumber: result.blockNumber,
      gasUsed: result.gasUsed,
    };
  } catch (err) {
    wrapBlockchainError(err);
  }
}

/**
 * Read-only: returns the current Vault allowance for the signer on a given token.
 */
export async function checkAllowance(
  tokenAddress: string,
  chain: ChainKey
): Promise<bigint> {
  try {
    const vaultAddress = requireAddress(chain, "vault");
    const token = getERC20Read(tokenAddress, chain);
    const signer = getSigner(chain);
    return await token.allowance(signer.address, vaultAddress);
  } catch (err) {
    wrapBlockchainError(err);
  }
}
