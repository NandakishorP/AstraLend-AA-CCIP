import { type ChainKey, requireAddress } from "../config/env.js";
import { getLendingPoolWrite, getLendingPoolRead } from "../blockchain/contracts.js";
import { getSigner } from "../blockchain/wallet.js";
import { sendTransaction, type TxResult } from "../blockchain/wallet.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { ensureVaultApproval, type ApprovalResult } from "./approval.service.js";

export interface BorrowLoanResult {
  tx: TxResult;
}

/**
 * Borrows stablecoin against deposited collateral.
 *
 * The protocol enforces a 75% Loan-to-Value (LTV) ratio:
 *   maxBorrowable = collateralValueUSD * 0.75
 *
 * The loan is due in 180 days. Interest accrues via a kink-based borrower index
 * (base rate 5%, max 100% at full utilization). The amount is denominated in
 * stablecoin smallest units (6 decimals, USDT-like).
 *
 * On Ethereum: updates GSM + locks collateral + transfers stablecoin to caller.
 * On Arbitrum: sends CCIP message to Ethereum — provide ccipFee.
 *
 * @param collateralChainId - Chain ID where collateral was deposited
 * @param tokenId           - Protocol token ID of the collateral backing this loan
 * @param amount            - Amount to borrow in stablecoin smallest unit (6 dec)
 * @param ccipFee           - Native-token CCIP fee (required on non-ETH chains)
 * @param chain             - Chain to submit the transaction on
 */
export async function borrowLoan(
  collateralChainId: bigint,
  tokenId: bigint,
  amount: bigint,
  ccipFee: bigint,
  chain: ChainKey
): Promise<BorrowLoanResult> {
  try {
    const pool = getLendingPoolWrite(chain);
    const tx = await sendTransaction(
      chain,
      pool,
      "borrowLoan",
      [collateralChainId, tokenId, amount],
      { value: ccipFee }
    );
    return { tx };
  } catch (err) {
    wrapBlockchainError(err);
  }
}

export interface RepayLoanResult {
  approval: ApprovalResult;
  tx: TxResult;
}

/**
 * Repays an outstanding loan (partially or in full).
 *
 * Interest is always settled first, then the principal is reduced.
 * Overpayment is not allowed — use `getAmountToRepay` to get the exact total.
 *
 * When fully repaid:
 *   - The loan is marked as closed
 *   - Locked collateral is released back to the user
 *
 * Flow:
 *   1. Approve Vault to spend `amount` of stablecoin (repayment goes Caller → Vault)
 *   2. Call LendingPool.repayLoan(loanChainId, tokenId, amount, loanId)
 *
 * On Arbitrum: sends CCIP message to Ethereum — provide ccipFee.
 *
 * @param loanChainId - Chain ID where the loan was taken
 * @param tokenId     - Protocol token ID of the collateral
 * @param amount      - Amount to repay in stablecoin smallest unit (6 dec)
 * @param loanId      - Unique loan identifier (from borrowLoan event / getLoanDetails)
 * @param ccipFee     - Native-token CCIP fee (required on non-ETH chains)
 * @param chain       - Chain to submit the transaction on
 */
export async function repayLoan(
  loanChainId: bigint,
  tokenId: bigint,
  amount: bigint,
  loanId: bigint,
  ccipFee: bigint,
  chain: ChainKey
): Promise<RepayLoanResult> {
  try {
    const stableCoinAddress = requireAddress(chain, "stableCoin");
    // Vault's claimLoan calls transferFrom(user, vault, amount) — approve Vault
    const approval = await ensureVaultApproval(stableCoinAddress, amount, chain);

    const pool = getLendingPoolWrite(chain);
    const tx = await sendTransaction(
      chain,
      pool,
      "repayLoan",
      [loanChainId, tokenId, amount, loanId],
      { value: ccipFee }
    );
    return { approval, tx };
  } catch (err) {
    wrapBlockchainError(err);
  }
}

/**
 * Returns the total amount currently owed for a specific loan (principal + accrued interest).
 *
 * `getAmountToRepay` is declared `nonpayable` rather than `view` because it updates the
 * borrower index internally. We use `staticCall` to read the result without submitting a
 * transaction or paying gas.
 *
 * The contract resolves the loan against `msg.sender`, so the caller's address must be
 * supplied — for wallet-signed flows that is the connected user, not the backend signer.
 *
 * @param loanChainId - Chain ID where the loan was taken
 * @param tokenId     - Protocol token ID
 * @param loanId      - Unique loan identifier
 * @param chain       - Chain to query
 * @param userAddress - Borrower whose loan to price. Defaults to the backend signer.
 * @returns Total owed in stablecoin smallest unit (6 dec)
 */
export async function getAmountToRepay(
  loanChainId: bigint,
  tokenId: bigint,
  loanId: bigint,
  chain: ChainKey,
  userAddress?: string
): Promise<bigint> {
  try {
    const from = userAddress ?? getSigner(chain).address;
    const pool = getLendingPoolRead(chain);
    // Must pass `from` so the contract's msg.sender lookup resolves to the borrower
    return await pool.getAmountToRepay.staticCall(loanChainId, tokenId, loanId, { from });
  } catch (err) {
    wrapBlockchainError(err);
  }
}
