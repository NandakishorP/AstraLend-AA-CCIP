import { type ChainKey } from "../config/env.js";
import { getLendingPoolRead, getERC20Read } from "../blockchain/contracts.js";
import { getSigner } from "../blockchain/wallet.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";

// ─── Loan detail type ─────────────────────────────────────────────────────────

export interface LoanDetails {
  token: string;
  amountBorrowedInUSDT: string;
  principalAmount: string;
  collateralUsed: string;
  collateralChainId: string;
  lastUpdate: string;
  asset: string;
  userBorrowIndex: string;
  interestPaid: string;
  liquidationPoint: string;
  loanChainId: string;
  dueDate: string;
  isClosed: boolean;
  loanId: string;
  penaltyCount: number;
  isLiquidated: boolean;
  /** ISO-8601 string derived from dueDate Unix timestamp */
  dueDateISO: string;
  /** true if the loan is past its due date */
  isOverdue: boolean;
}

// Ethers returns a Result tuple/object; fields are accessed by name at runtime
// but TypeScript only knows the generic ethers.Result type. Cast explicitly.
export interface RawLoanResult {
  token: string;
  amountBorrowedInUSDT: bigint;
  principalAmount: bigint;
  collateralUsed: bigint;
  collateralChainId: bigint;
  lastUpdate: bigint;
  asset: string;
  userBorrowIndex: bigint;
  interestPaid: bigint;
  liquidationPoint: bigint;
  loanChainId: bigint;
  dueDate: bigint;
  isClosed: boolean;
  loanId: bigint;
  penaltyCount: number;
  isLiquidated: boolean;
}

export function parseLoanDetailsRaw(raw: unknown): LoanDetails {
  const r = raw as RawLoanResult;
  const dueDate = BigInt(r.dueDate ?? 0n);
  const dueDateMs = Number(dueDate) * 1000;
  return {
    token: r.token,
    amountBorrowedInUSDT: r.amountBorrowedInUSDT.toString(),
    principalAmount: r.principalAmount.toString(),
    collateralUsed: r.collateralUsed.toString(),
    collateralChainId: r.collateralChainId.toString(),
    lastUpdate: r.lastUpdate.toString(),
    asset: r.asset,
    userBorrowIndex: r.userBorrowIndex.toString(),
    interestPaid: r.interestPaid.toString(),
    liquidationPoint: r.liquidationPoint.toString(),
    loanChainId: r.loanChainId.toString(),
    dueDate: dueDate.toString(),
    isClosed: r.isClosed,
    loanId: r.loanId.toString(),
    penaltyCount: Number(r.penaltyCount),
    isLiquidated: r.isLiquidated,
    dueDateISO: new Date(dueDateMs).toISOString(),
    isOverdue: Date.now() > dueDateMs,
  };
}

// ─── Protocol-level reads ─────────────────────────────────────────────────────

/** Total protocol TVL in USD across all supported tokens (1e18 precision). */
export async function getTotalLiquidity(chain: ChainKey): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getTotalLiquidity();
  } catch (err) { wrapBlockchainError(err); }
}

/** Total liquidity for a specific token ID in token smallest unit. */
export async function getTotalLiquidityPerToken(tokenId: bigint, chain: ChainKey): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getTotalLiquidityPerToken(tokenId);
  } catch (err) { wrapBlockchainError(err); }
}

/** Total amount borrowed for a specific token ID. */
export async function getTotalBorrowedForToken(tokenId: bigint, chain: ChainKey): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getTotalBorroweedForAToken(tokenId);
  } catch (err) { wrapBlockchainError(err); }
}

/** Total collateral deposited across all users for a specific token ID. */
export async function getCollateralPerToken(tokenId: bigint, chain: ChainKey): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getCollateralPerToken(tokenId);
  } catch (err) { wrapBlockchainError(err); }
}

// ─── User-level reads ─────────────────────────────────────────────────────────

/** Deposit balance for a user on a given chain and token. */
export async function getUserBalance(
  chainId: bigint,
  userAddress: string,
  tokenId: bigint,
  chain: ChainKey
): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getUserBalance(chainId, userAddress, tokenId);
  } catch (err) { wrapBlockchainError(err); }
}

/** Collateral deposited by a user for a specific token on a given chain. */
export async function getCollateralDetails(
  chainId: bigint,
  userAddress: string,
  tokenId: bigint,
  chain: ChainKey
): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getCollateralDetailsOfUser(chainId, userAddress, tokenId);
  } catch (err) { wrapBlockchainError(err); }
}

/** Full loan details for a specific loan. */
export async function getLoanDetails(
  chainId: bigint,
  userAddress: string,
  tokenId: bigint,
  loanId: bigint,
  chain: ChainKey
): Promise<LoanDetails> {
  try {
    const raw = await getLendingPoolRead(chain).getLoanDetails(chainId, userAddress, tokenId, loanId);
    return parseLoanDetailsRaw(raw);
  } catch (err) { wrapBlockchainError(err); }
}

/** Total LP tokens held by a user. */
export async function getTotalLPTokensForUser(userAddress: string, chain: ChainKey): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getTotalLPTokensForTheUser(userAddress);
  } catch (err) { wrapBlockchainError(err); }
}

// ─── Pricing / index reads ────────────────────────────────────────────────────

/** USD value of a given token amount (1e18 precision). */
export async function getUsdValue(tokenId: bigint, amount: bigint, chain: ChainKey): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getUsdValue(tokenId, amount);
  } catch (err) { wrapBlockchainError(err); }
}

/** Token amount equivalent to a USD value (1e18 precision). */
export async function getTokenAmountFromUsd(tokenId: bigint, usdValue: bigint, chain: ChainKey): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getTokenAmountFromUsd(tokenId, usdValue);
  } catch (err) { wrapBlockchainError(err); }
}

/**
 * Current borrower index for a token.
 * Uses staticCall because getBorrowerIndex is `nonpayable` (updates state),
 * but we want a read-only snapshot without paying gas.
 */
export async function getBorrowerIndex(tokenId: bigint, chain: ChainKey): Promise<bigint> {
  try {
    const signer = getSigner(chain);
    const pool = getLendingPoolRead(chain);
    return await pool.getBorrowerIndex.staticCall(tokenId, { from: signer.address });
  } catch (err) { wrapBlockchainError(err); }
}

// ─── Contract metadata ────────────────────────────────────────────────────────

export async function getPriceFeedAddress(tokenId: bigint, chain: ChainKey): Promise<string> {
  try {
    return await getLendingPoolRead(chain).getPriceFeedAddress(tokenId);
  } catch (err) { wrapBlockchainError(err); }
}

export async function getTokenAddress(tokenId: bigint, chain: ChainKey): Promise<string> {
  try {
    return await getLendingPoolRead(chain).getTokenAddressFromTokenId(tokenId);
  } catch (err) { wrapBlockchainError(err); }
}

export async function getStableCoinAddress(chain: ChainKey): Promise<string> {
  try {
    return await getLendingPoolRead(chain).getStableCoinAddress();
  } catch (err) { wrapBlockchainError(err); }
}

export async function getLpTokenAddress(chain: ChainKey): Promise<string> {
  try {
    return await getLendingPoolRead(chain).getLpTokenAddress();
  } catch (err) { wrapBlockchainError(err); }
}

export async function getVaultAddress(chain: ChainKey): Promise<string> {
  try {
    return await getLendingPoolRead(chain).getVaultAddress();
  } catch (err) { wrapBlockchainError(err); }
}

// ─── ERC20 helpers ────────────────────────────────────────────────────────────

export interface TokenBalance {
  balance: string;
  decimals: number;
}

export async function getTokenBalance(
  tokenAddress: string,
  userAddress: string,
  chain: ChainKey
): Promise<TokenBalance> {
  try {
    const token = getERC20Read(tokenAddress, chain);
    const [balance, decimals]: [bigint, bigint] = await Promise.all([
      token.balanceOf(userAddress),
      token.decimals(),
    ]);
    return { balance: balance.toString(), decimals: Number(decimals) };
  } catch (err) { wrapBlockchainError(err); }
}

/** Number of loans a user has taken for a specific token on a given chain. */
export async function getUserLoanCount(
  chainId: bigint,
  userAddress: string,
  tokenId: bigint,
  chain: ChainKey
): Promise<bigint> {
  try {
    return await getLendingPoolRead(chain).getUserLoanCount(chainId, userAddress, tokenId);
  } catch (err) { wrapBlockchainError(err); }
}
