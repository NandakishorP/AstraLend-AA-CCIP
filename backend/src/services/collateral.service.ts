import { type ChainKey } from "../config/env.js";
import { getLendingPoolWrite } from "../blockchain/contracts.js";
import { sendTransaction, type TxResult } from "../blockchain/wallet.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { ensureVaultApproval, type ApprovalResult } from "./approval.service.js";

export interface DepositCollateralResult {
  approval: ApprovalResult;
  tx: TxResult;
}

/**
 * Deposits collateral into the lending pool.
 *
 * Flow:
 *   1. Approve Vault to spend `amount` of `tokenAddress` (if allowance is low)
 *   2. Call LendingPool.depositCollateral(tokenId, amount)
 *
 * On Ethereum: updates GlobalStateManager + mirrors to Arbitrum.
 * On Arbitrum: sends CCIP message to Ethereum — provide ccipFee.
 *
 * The deposited collateral can later be used to back a loan (up to 75% LTV).
 * Collateral is locked per active loan and released upon full repayment.
 *
 * @param tokenAddress - ERC20 collateral token address
 * @param tokenId      - Protocol token ID
 * @param amount       - Amount in token's smallest unit
 * @param ccipFee      - Native-token CCIP fee (required on non-ETH chains)
 * @param chain        - Target chain
 */
export async function depositCollateral(
  tokenAddress: string,
  tokenId: bigint,
  amount: bigint,
  ccipFee: bigint,
  chain: ChainKey
): Promise<DepositCollateralResult> {
  try {
    const approval = await ensureVaultApproval(tokenAddress, amount, chain);
    const pool = getLendingPoolWrite(chain);
    const tx = await sendTransaction(chain, pool, "depositCollateral", [tokenId, amount], {
      value: ccipFee,
    });
    return { approval, tx };
  } catch (err) {
    wrapBlockchainError(err);
  }
}

export interface WithdrawCollateralResult {
  tx: TxResult;
}

/**
 * Withdraws unlocked collateral back to the signer's wallet.
 *
 * Only collateral that is NOT currently backing an active loan can be withdrawn.
 * Attempting to withdraw locked collateral will be rejected by the contract.
 *
 * On Arbitrum: sends CCIP message to Ethereum — provide ccipFee.
 *
 * @param tokenId  - Protocol token ID
 * @param amount   - Amount to withdraw in token's smallest unit
 * @param ccipFee  - Native-token CCIP fee (required on non-ETH chains)
 * @param chain    - Target chain
 */
export async function withdrawCollateral(
  tokenId: bigint,
  amount: bigint,
  ccipFee: bigint,
  chain: ChainKey
): Promise<WithdrawCollateralResult> {
  try {
    const pool = getLendingPoolWrite(chain);
    const tx = await sendTransaction(chain, pool, "withdrawCollateral", [tokenId, amount], {
      value: ccipFee,
    });
    return { tx };
  } catch (err) {
    wrapBlockchainError(err);
  }
}
