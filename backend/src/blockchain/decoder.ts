import { ethers } from "ethers";
import { createRequire } from "module";
import {
  AppError,
  ContractError,
  BlockchainError,
  SOLIDITY_ERROR_MESSAGES,
  interpolateMessage,
} from "../errors.js";

const require = createRequire(import.meta.url);

// Load all error definitions — pool from both the LendingPoolContract ABI
// and a manually curated list covering the controllers and vault errors
// that surface through inner calls.
const lendingPoolJSON = require("../abis/LendingPoolContract.json") as { abi: ethers.InterfaceAbi };

// Additional error fragments not present in the LendingPool ABI but emitted
// by inner contracts (Vault, controllers, GSM) during revert propagation.
const EXTRA_ERROR_FRAGMENTS = [
  "error Vault__AmountShouldBeGreaterThanZero()",
  "error Vault__TokenIsNotAllowedToDeposit(address token)",
  "error Vault__UnauthorizedAccess()",
  "error Vault__VaultPaused()",
  "error LoanController__AmountShouldBeGreaterThanZero()",
  "error LoanController__NotEnoughCollateral()",
  "error LoanController__InsufficentFees()",
  "error LoanController__TransferFailed()",
  "error LoanController__LoanAmountExceeded()",
  "error CollateralController__InsufficentFees()",
  "error CollateralController__TransferFailed()",
  "error CollateralContorller__InvalidRequestAmount()",
  "error LiquidityController__AmountShouldBeGreaterThanZero()",
  "error LiquidityController__InsufficentFees()",
  "error LiquidityController__TransferFailed()",
  "error LiquidityController__LpTokenMintFailed()",
  "error CrossChainMessageSender__InsufficentFees()",
  "error CrossChainMessageSender__DestinationChainNotAllowed(uint64 destinationChainSelector)",
  "error CrossChainMessageSender__InvalidReceiverAddress()",
  "error CrossChainMessageSender__InsufficentBalance()",
  "error GlobalStateManager__InvalidSender(address sender)",
  "error GlobalStateManager__LoanIsNotActive()",
  "error GlobalStateManager__NotLiquidatable()",
];

const errorInterface = new ethers.Interface([
  ...lendingPoolJSON.abi,
  ...EXTRA_ERROR_FRAGMENTS,
]);

/**
 * Attempts to decode a Solidity custom error from a failed ethers transaction.
 *
 * If the error is a known Solidity revert, throws a `ContractError` with a
 * human-readable message (interpolated from decoded args).
 *
 * If the error is not a contract revert, returns without throwing so the
 * caller can apply their own handling (e.g., retry logic).
 */
export function decodeContractError(err: unknown): void {
  const error = err as Record<string, unknown>;

  // ethers v6 wraps reverts in a CallExceptionError with `data` field
  const revertData =
    (error?.["data"] as string | undefined) ??
    (error?.["revert"] as Record<string, unknown> | undefined)?.["data"] as string | undefined ??
    extractNestedData(error);

  if (!revertData || revertData === "0x") return;

  try {
    const decoded = errorInterface.parseError(revertData);
    if (!decoded) return;

    // Build a flat string → string args map from positional decoded args
    const args: Record<string, string> = {};
    decoded.fragment.inputs.forEach((input, i) => {
      args[input.name] = decoded.args[i]?.toString() ?? "";
    });

    const template = SOLIDITY_ERROR_MESSAGES[decoded.name];
    const message = template
      ? interpolateMessage(template, args)
      : `Contract reverted: ${decoded.name}(${Object.values(args).join(", ")})`;

    throw new ContractError(decoded.name, message, args);
  } catch (innerErr) {
    // Re-throw if we just constructed the ContractError above
    if (innerErr instanceof ContractError) throw innerErr;
    // Otherwise the ABI parse failed — not a known custom error, fall through
  }
}

/** Recursively tries to find error data buried in nested ethers error objects. */
function extractNestedData(err: Record<string, unknown>): string | undefined {
  const nested = err?.["error"] as Record<string, unknown> | undefined;
  if (!nested) return undefined;
  const data = nested["data"] as string | undefined;
  if (data) return data;
  return extractNestedData(nested);
}

/**
 * Wraps any unknown error thrown by the blockchain layer into a typed error.
 * Call this at service boundaries to ensure only typed errors escape.
 */
export function wrapBlockchainError(err: unknown): never {
  // Already typed — rethrow as-is so the original status code and message
  // survive (a misconfigured address is a 500 ConfigError, not a 502).
  if (err instanceof AppError) throw err;

  // Try to decode as a Solidity error first
  try {
    decodeContractError(err);
  } catch (decoded) {
    throw decoded;
  }

  const message = (err as Error)?.message ?? "Unknown blockchain error";
  throw new BlockchainError(message, err);
}
