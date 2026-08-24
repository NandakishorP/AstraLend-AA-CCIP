import { type ChainKey, CHAIN_CONFIGS } from "../config/env.js";
import { getLendingPoolRead } from "../blockchain/contracts.js";
import { getSigner } from "../blockchain/wallet.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";

export type FeeOperation =
  | "depositLiquidity"
  | "withdrawLiquidity"
  | "depositCollateral"
  | "withdrawCollateral"
  | "borrowLoan"
  | "repayLoan";

export interface FeeEstimate {
  operation: FeeOperation;
  chain: ChainKey;
  /** Native-token fee in wei as a decimal string (0 on Ethereum — no CCIP needed) */
  ccipFeeWei: string;
  /** Human-readable label, e.g. "0.002 ETH" */
  ccipFeeFormatted: string;
  /** True when this chain sends via CCIP (i.e. non-Ethereum) */
  requiresCcip: boolean;
  /** Recommended value to pass as msg.value on the contract call */
  recommendedValueWei: string;
}

/**
 * Estimates the CCIP fee required for a cross-chain operation on the given chain.
 *
 * On Ethereum Sepolia all write operations update state directly — no CCIP fee.
 * On Arbitrum Sepolia every write must send a CCIP message to Ethereum — fee required.
 *
 * The fee is fetched from the contract's own `getFee()` view function which queries
 * the live Chainlink CCIP router. The result is multiplied by 1.1 (10% safety buffer)
 * so users don't hit InsufficientFees reverts from minor fee fluctuations.
 *
 * @param operation  Which protocol action the user wants to perform
 * @param tokenId    Token ID involved in the operation
 * @param amount     Amount involved (in token smallest unit)
 * @param chain      Chain the user will submit from
 */
export async function estimateCcipFee(
  operation: FeeOperation,
  tokenId: bigint,
  amount: bigint,
  chain: ChainKey
): Promise<FeeEstimate> {
  try {
    const config = CHAIN_CONFIGS[chain];
    const ETH_CHAIN_ID = 11155111;

    // Ethereum doesn't need CCIP — all ops are local
    if (config.chainId === ETH_CHAIN_ID) {
      return {
        operation,
        chain,
        ccipFeeWei: "0",
        ccipFeeFormatted: "0 ETH",
        requiresCcip: false,
        recommendedValueWei: "0",
      };
    }

    // On non-Ethereum chains, query the contract's fee estimator
    const pool = getLendingPoolRead(chain);
    const signer = getSigner(chain);
    const lendingPoolAddress = config.lendingPool ?? "";

    // getFee(receiver, tokenId, amount, isLink, destinationChainSelector, message)
    // We use native-token mode (isLink=false) and Ethereum Sepolia as destination.
    // destinationChainSelector for ETH Sepolia = 16015286601757825753
    const ETH_SEPOLIA_SELECTOR = 16015286601757825753n;
    const rawFee: bigint = await pool.getFee(
      lendingPoolAddress,
      tokenId,
      amount,
      false, // native token fee mode
      ETH_SEPOLIA_SELECTOR,
      operation,
      { from: signer.address }
    );

    // Add 10% buffer so minor fee fluctuations don't cause InsufficientFees reverts
    const buffered = (rawFee * 110n) / 100n;
    const formatted = formatWei(buffered);

    return {
      operation,
      chain,
      ccipFeeWei: rawFee.toString(),
      ccipFeeFormatted: formatted,
      requiresCcip: true,
      recommendedValueWei: buffered.toString(),
    };
  } catch (err) {
    wrapBlockchainError(err);
  }
}

function formatWei(wei: bigint): string {
  // Format to 6 significant decimal places, e.g. "0.001234 ETH"
  const eth = Number(wei) / 1e18;
  return `${eth.toFixed(6)} ETH`;
}
