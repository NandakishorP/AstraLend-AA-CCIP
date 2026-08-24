import { ethers } from "ethers";
import { createRequire } from "module";
import { type ChainKey, CHAIN_CONFIGS, requireAddress } from "../config/env.js";
import { getLendingPoolRead, getERC20Read } from "../blockchain/contracts.js";
import { getProvider } from "../blockchain/providers.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { GAS_BUFFER_PERCENT } from "../config/constants.js";
import { getResolvedToken, getStableCoinMeta } from "./token.service.js";

const require = createRequire(import.meta.url);
const { abi: LendingPoolABI } = require("../abis/LendingPoolContract.json") as { abi: ethers.InterfaceAbi };
const ERC20ABI = require("../abis/ERC20.json") as ethers.InterfaceAbi;

const poolInterface = new ethers.Interface(LendingPoolABI);
const erc20Interface = new ethers.Interface(ERC20ABI);

// ─── Types ─────────────────────────────────────────────────────────────────────

export interface UnsignedTx {
  to: string;
  data: string;
  value: string;          // hex wei
  gasLimit: string;       // hex
  chainId: number;
  description: string;
  type: string;
}

export interface BuildResult {
  /**
   * Ordered list of transactions for the frontend to submit sequentially.
   * Typically [approve?, mainAction] — at most two transactions.
   */
  transactions: UnsignedTx[];
  chainId: number;
  /**
   * Human-readable summary of what the sequence will do.
   */
  summary: string;
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Gas limits used when `eth_estimateGas` cannot run.
 *
 * Estimation legitimately fails in the common case: the main action is bundled
 * behind an approval that has not been mined yet, so simulating it reverts on the
 * missing allowance. A single flat fallback would under-fund CCIP operations, so
 * each action carries its own ceiling, measured against the deployed contracts.
 */
const FALLBACK_GAS: Record<string, bigint> = {
  approval: 120_000n,
  depositLiquidity: 700_000n,
  withdrawDeposit: 700_000n,
  depositCollateral: 700_000n,
  withdrawCollateral: 700_000n,
  borrowLoan: 1_100_000n,
  repayLoan: 1_100_000n,
  mint: 150_000n,
};

/** Cross-chain paths run a CCIP send on top of the local work — budget for it. */
const CCIP_GAS_MULTIPLIER = 2n;

async function estimateGasHex(
  provider: ethers.JsonRpcProvider,
  tx: { to: string; data: string; value?: bigint; from?: string },
  action: string
): Promise<string> {
  try {
    const estimate = await provider.estimateGas(tx);
    const buffered = (estimate * (100n + GAS_BUFFER_PERCENT)) / 100n;
    return ethers.toBeHex(buffered);
  } catch {
    const base = FALLBACK_GAS[action] ?? 500_000n;
    const isCrossChain = (tx.value ?? 0n) > 0n;
    return ethers.toBeHex(isCrossChain ? base * CCIP_GAS_MULTIPLIER : base);
  }
}

/** Formats an amount for a transaction description using the token's real decimals. */
function describeAmount(amount: bigint, decimals: number, symbol: string): string {
  const formatted = Number(ethers.formatUnits(amount, decimals));
  return `${formatted.toLocaleString("en-US", { maximumFractionDigits: 6 })} ${symbol}`;
}

async function buildApprovalTx(
  tokenAddress: string,
  spender: string,
  userAddress: string,
  chain: ChainKey
): Promise<UnsignedTx | null> {
  const provider = getProvider(chain);
  const config = CHAIN_CONFIGS[chain];
  const token = getERC20Read(tokenAddress, chain);
  const allowance: bigint = await token.allowance(userAddress, spender);

  // If already approved for max, skip
  if (allowance >= ethers.MaxUint256 / 2n) return null;

  const data = erc20Interface.encodeFunctionData("approve", [spender, ethers.MaxUint256]);
  const gasLimit = await estimateGasHex(
    provider,
    { to: tokenAddress, data, from: userAddress },
    "approval"
  );

  return {
    to: tokenAddress,
    data,
    value: "0x0",
    gasLimit,
    chainId: config.chainId,
    type: "approval",
    description: `Approve token for the AstraLend Vault`,
  };
}

// ─── Liquidity ─────────────────────────────────────────────────────────────────

export async function buildDepositLiquidity(
  userAddress: string,
  tokenId: bigint,
  amount: bigint,
  ccipFeeWei: bigint,
  chain: ChainKey
): Promise<BuildResult> {
  try {
    const config = CHAIN_CONFIGS[chain];
    const lendingPoolAddress = requireAddress(chain, "lendingPool");
    const vaultAddress = requireAddress(chain, "vault");
    const provider = getProvider(chain);
    const tokenAddress: string = await getLendingPoolRead(chain).getTokenAddressFromTokenId(tokenId);

    const transactions: UnsignedTx[] = [];

    const approval = await buildApprovalTx(tokenAddress, vaultAddress, userAddress, chain);
    if (approval) transactions.push(approval);

    const token = await getResolvedToken(Number(tokenId), chain);
    const data = poolInterface.encodeFunctionData("depositLiquidity", [tokenId, amount]);
    const gasLimit = await estimateGasHex(
      provider,
      { to: lendingPoolAddress, data, value: ccipFeeWei, from: userAddress },
      "depositLiquidity"
    );
    transactions.push({
      to: lendingPoolAddress,
      data,
      value: ethers.toBeHex(ccipFeeWei),
      gasLimit,
      chainId: config.chainId,
      type: "depositLiquidity",
      description: `Supply ${describeAmount(amount, token.decimals, token.symbol)} as liquidity`,
    });

    return { transactions, chainId: config.chainId, summary: "Deposit liquidity and receive LP tokens" };
  } catch (err) { wrapBlockchainError(err); }
}

export async function buildWithdrawLiquidity(
  userAddress: string,
  tokenId: bigint,
  amount: bigint,
  ccipFeeWei: bigint,
  chain: ChainKey
): Promise<BuildResult> {
  try {
    const config = CHAIN_CONFIGS[chain];
    const lendingPoolAddress = requireAddress(chain, "lendingPool");
    const provider = getProvider(chain);

    const token = await getResolvedToken(Number(tokenId), chain);
    const data = poolInterface.encodeFunctionData("withdrawDeposit", [tokenId, amount]);
    const gasLimit = await estimateGasHex(
      provider,
      { to: lendingPoolAddress, data, value: ccipFeeWei, from: userAddress },
      "withdrawDeposit"
    );

    return {
      transactions: [{
        to: lendingPoolAddress, data,
        value: ethers.toBeHex(ccipFeeWei),
        gasLimit, chainId: config.chainId,
        type: "withdrawDeposit",
        description: `Withdraw ${describeAmount(amount, token.decimals, token.symbol)} of liquidity`,
      }],
      chainId: config.chainId,
      summary: "Withdraw liquidity",
    };
  } catch (err) { wrapBlockchainError(err); }
}

// ─── Collateral ────────────────────────────────────────────────────────────────

export async function buildDepositCollateral(
  userAddress: string,
  tokenId: bigint,
  amount: bigint,
  ccipFeeWei: bigint,
  chain: ChainKey
): Promise<BuildResult> {
  try {
    const config = CHAIN_CONFIGS[chain];
    const lendingPoolAddress = requireAddress(chain, "lendingPool");
    const vaultAddress = requireAddress(chain, "vault");
    const provider = getProvider(chain);
    const tokenAddress: string = await getLendingPoolRead(chain).getTokenAddressFromTokenId(tokenId);

    const transactions: UnsignedTx[] = [];

    const approval = await buildApprovalTx(tokenAddress, vaultAddress, userAddress, chain);
    if (approval) transactions.push(approval);

    const token = await getResolvedToken(Number(tokenId), chain);
    const data = poolInterface.encodeFunctionData("depositCollateral", [tokenId, amount]);
    const gasLimit = await estimateGasHex(
      provider,
      { to: lendingPoolAddress, data, value: ccipFeeWei, from: userAddress },
      "depositCollateral"
    );
    transactions.push({
      to: lendingPoolAddress, data,
      value: ethers.toBeHex(ccipFeeWei),
      gasLimit, chainId: config.chainId,
      type: "depositCollateral",
      description: `Deposit ${describeAmount(amount, token.decimals, token.symbol)} as collateral`,
    });

    return { transactions, chainId: config.chainId, summary: "Deposit collateral to back loans" };
  } catch (err) { wrapBlockchainError(err); }
}

export async function buildWithdrawCollateral(
  userAddress: string,
  tokenId: bigint,
  amount: bigint,
  ccipFeeWei: bigint,
  chain: ChainKey
): Promise<BuildResult> {
  try {
    const config = CHAIN_CONFIGS[chain];
    const lendingPoolAddress = requireAddress(chain, "lendingPool");
    const provider = getProvider(chain);

    const token = await getResolvedToken(Number(tokenId), chain);
    const data = poolInterface.encodeFunctionData("withdrawCollateral", [tokenId, amount]);
    const gasLimit = await estimateGasHex(
      provider,
      { to: lendingPoolAddress, data, value: ccipFeeWei, from: userAddress },
      "withdrawCollateral"
    );

    return {
      transactions: [{
        to: lendingPoolAddress, data,
        value: ethers.toBeHex(ccipFeeWei),
        gasLimit, chainId: config.chainId,
        type: "withdrawCollateral",
        description: `Withdraw ${describeAmount(amount, token.decimals, token.symbol)} of collateral`,
      }],
      chainId: config.chainId,
      summary: "Withdraw unlocked collateral",
    };
  } catch (err) { wrapBlockchainError(err); }
}

// ─── Loan ──────────────────────────────────────────────────────────────────────

export async function buildBorrowLoan(
  userAddress: string,
  collateralChainId: bigint,
  tokenId: bigint,
  amount: bigint,
  ccipFeeWei: bigint,
  chain: ChainKey
): Promise<BuildResult> {
  try {
    const config = CHAIN_CONFIGS[chain];
    const lendingPoolAddress = requireAddress(chain, "lendingPool");
    const provider = getProvider(chain);

    const stableCoin = await getStableCoinMeta(chain);
    const data = poolInterface.encodeFunctionData("borrowLoan", [collateralChainId, tokenId, amount]);
    const gasLimit = await estimateGasHex(
      provider,
      { to: lendingPoolAddress, data, value: ccipFeeWei, from: userAddress },
      "borrowLoan"
    );

    return {
      transactions: [{
        to: lendingPoolAddress, data,
        value: ethers.toBeHex(ccipFeeWei),
        gasLimit, chainId: config.chainId,
        type: "borrowLoan",
        description: `Borrow ${describeAmount(amount, stableCoin.decimals, stableCoin.symbol)}`,
      }],
      chainId: config.chainId,
      summary: "Borrow stablecoin against collateral (75% LTV)",
    };
  } catch (err) { wrapBlockchainError(err); }
}

export async function buildRepayLoan(
  userAddress: string,
  loanChainId: bigint,
  tokenId: bigint,
  amount: bigint,
  loanId: bigint,
  ccipFeeWei: bigint,
  chain: ChainKey
): Promise<BuildResult> {
  try {
    const config = CHAIN_CONFIGS[chain];
    const lendingPoolAddress = requireAddress(chain, "lendingPool");
    const stableCoinAddress = requireAddress(chain, "stableCoin");
    const vaultAddress = requireAddress(chain, "vault");
    const provider = getProvider(chain);

    const transactions: UnsignedTx[] = [];

    // Repayment: user → Vault via claimLoan — approve stablecoin for Vault
    const approval = await buildApprovalTx(stableCoinAddress, vaultAddress, userAddress, chain);
    if (approval) transactions.push(approval);

    const stableCoin = await getStableCoinMeta(chain);
    const data = poolInterface.encodeFunctionData("repayLoan", [loanChainId, tokenId, amount, loanId]);
    const gasLimit = await estimateGasHex(
      provider,
      { to: lendingPoolAddress, data, value: ccipFeeWei, from: userAddress },
      "repayLoan"
    );
    transactions.push({
      to: lendingPoolAddress, data,
      value: ethers.toBeHex(ccipFeeWei),
      gasLimit, chainId: config.chainId,
      type: "repayLoan",
      description: `Repay ${describeAmount(amount, stableCoin.decimals, stableCoin.symbol)} on loan #${loanId}`,
    });

    return {
      transactions,
      chainId: config.chainId,
      summary: "Repay loan — collateral released on full repayment",
    };
  } catch (err) { wrapBlockchainError(err); }
}
