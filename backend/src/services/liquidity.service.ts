import { type ChainKey } from "../config/env.js";
import { getLendingPoolWrite } from "../blockchain/contracts.js";
import { sendTransaction, type TxResult } from "../blockchain/wallet.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { ensureVaultApproval, type ApprovalResult } from "./approval.service.js";

export interface DepositLiquidityResult {
  approval: ApprovalResult;
  tx: TxResult;
}

/**
 * Deposits liquidity into the lending pool.
 *
 * Flow:
 *   1. Approve Vault to spend `amount` of `tokenAddress` (if allowance is low)
 *   2. Call LendingPool.depositLiquidity(tokenId, amount)
 *   3. LP tokens are minted proportionally to the current pool ratio
 *
 * On Ethereum: updates GSM + mirrors to Arbitrum.
 * On Arbitrum: sends CCIP message to Ethereum (provide ccipFee).
 *
 * @param tokenAddress - ERC20 token address to deposit
 * @param tokenId      - Protocol token ID (0 = WETH, 1 = WBTC, ...)
 * @param amount       - Amount in token's smallest unit
 * @param ccipFee      - Native-token CCIP fee in wei (required on non-ETH chains)
 * @param chain        - Target chain
 */
export async function depositLiquidity(
  tokenAddress: string,
  tokenId: bigint,
  amount: bigint,
  ccipFee: bigint,
  chain: ChainKey
): Promise<DepositLiquidityResult> {
  try {
    const approval = await ensureVaultApproval(tokenAddress, amount, chain);
    const pool = getLendingPoolWrite(chain);
    const tx = await sendTransaction(chain, pool, "depositLiquidity", [tokenId, amount], {
      value: ccipFee,
    });
    return { approval, tx };
  } catch (err) {
    wrapBlockchainError(err);
  }
}

export interface WithdrawLiquidityResult {
  tx: TxResult;
}

/**
 * Withdraws previously deposited liquidity from the lending pool.
 *
 * LP tokens are burned proportionally. The caller must have sufficient
 * LP token balance and the pool must have sufficient liquidity.
 *
 * On Arbitrum: sends CCIP message to Ethereum (provide ccipFee).
 *
 * @param tokenId  - Protocol token ID
 * @param amount   - Amount to withdraw in token's smallest unit
 * @param ccipFee  - Native-token CCIP fee in wei (required on non-ETH chains)
 * @param chain    - Target chain
 */
export async function withdrawLiquidity(
  tokenId: bigint,
  amount: bigint,
  ccipFee: bigint,
  chain: ChainKey
): Promise<WithdrawLiquidityResult> {
  try {
    const pool = getLendingPoolWrite(chain);
    const tx = await sendTransaction(chain, pool, "withdrawDeposit", [tokenId, amount], {
      value: ccipFee,
    });
    return { tx };
  } catch (err) {
    wrapBlockchainError(err);
  }
}
