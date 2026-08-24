/**
 * Base application error. All custom errors extend this.
 * `statusCode` maps directly to HTTP status codes.
 */
export class AppError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
    public readonly code: string,
    public readonly details?: unknown
  ) {
    super(message);
    this.name = this.constructor.name;
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * Input failed JSON Schema or semantic validation.
 * HTTP 400
 */
export class ValidationError extends AppError {
  constructor(message: string, details?: unknown) {
    super(message, 400, "VALIDATION_ERROR", details);
  }
}

/**
 * A Solidity custom error was decoded from a reverted transaction.
 * HTTP 422 — the request was well-formed but the contract rejected it.
 */
export class ContractError extends AppError {
  constructor(
    public readonly contractErrorName: string,
    message: string,
    public readonly args?: Record<string, string>
  ) {
    super(message, 422, "CONTRACT_ERROR", { contractErrorName, args });
  }
}

/**
 * A raw blockchain/network error that could not be decoded as a contract error.
 * HTTP 502 — upstream blockchain node or network issue.
 */
export class BlockchainError extends AppError {
  constructor(message: string, details?: unknown) {
    super(message, 502, "BLOCKCHAIN_ERROR", details);
  }
}

/**
 * A required env variable or contract address is missing/misconfigured.
 * HTTP 500
 */
export class ConfigError extends AppError {
  constructor(message: string) {
    super(message, 500, "CONFIG_ERROR");
  }
}

/**
 * Centralized human-readable messages for each known Solidity custom error.
 * Interpolate {argName} placeholders using the decoded args.
 */
export const SOLIDITY_ERROR_MESSAGES: Record<string, string> = {
  // LendingPoolContract
  LendingPoolContract__AmountShouldBeGreaterThanZero: "Amount must be greater than zero.",
  LendingPoolContract__TokenIsNotAllowedToDeposit:
    "This token is not supported by the protocol.",
  LendingPoolContract__InsufficentBalance:
    "Insufficient balance. Requested: {amount}, available: {availableAmount}.",
  LendingPoolContract__LoanPending:
    "Cannot perform this action while a loan is still pending.",
  LendingPoolContract__NotEnoughCollateral:
    "Insufficient collateral. Deposit more collateral or reduce the borrow amount (max 75% LTV).",
  LendingPoolContract__LoanAmountExceeded:
    "Repayment amount exceeds the total outstanding debt.",
  LendingPoolContract__InvalidRequestAmount: "Invalid request amount.",
  LendingPoolContract__LoanIsNotActive: "The specified loan is not active.",
  LendingPoolContract__LoanStillPending: "The loan is still pending settlement.",
  LendingPoolContract__NotLiquidatable: "This loan does not meet liquidation criteria.",
  LendingPoolContract__LpTokenMintFailed: "LP token minting failed.",
  LendingPoolContract__InsufficentLpTokenBalance:
    "Insufficient LP token balance to perform this operation.",
  LendingPoolContract__InsufficentFees:
    "Insufficient CCIP fee. Provide more native token via the ccipFee field.",
  LendingPoolContract__TransferFailed:
    "Native token fee transfer to the cross-chain sender failed.",
  LendingPoolContract__InvalidRequest: "Invalid request.",
  LendingPoolContract__InvalidChainId:
    "This chain ID is not allowed by the protocol.",
  LendingPoolContract__InvalidAddress: "Invalid address provided.",
  LendingPoolContract__TokenAddressAndPriceFeedAddressMismatch:
    "Token address count ({tokenAddressLength}) must match price feed address count ({priceFeedAddressLength}).",

  // Vault
  Vault__AmountShouldBeGreaterThanZero: "Vault: amount must be greater than zero.",
  Vault__TokenIsNotAllowedToDeposit:
    "Vault: token {token} is not supported for deposit.",
  Vault__UnauthorizedAccess:
    "Vault: caller is not an authorized contract.",
  Vault__VaultPaused:
    "The vault is currently paused. Try again later.",

  // LoanController
  LoanController__AmountShouldBeGreaterThanZero: "Amount must be greater than zero.",
  LoanController__NotEnoughCollateral:
    "Not enough collateral to cover this loan (75% LTV limit).",
  LoanController__InsufficentFees: "Insufficient CCIP fee for cross-chain loan.",
  LoanController__TransferFailed: "Loan controller: fee transfer failed.",
  LoanController__LoanAmountExceeded: "Repayment exceeds total debt.",

  // CollateralController
  CollateralController__InsufficentFees:
    "Insufficient CCIP fee for cross-chain collateral operation.",
  CollateralController__TransferFailed: "Collateral controller: fee transfer failed.",
  CollateralContorller__InvalidRequestAmount: "Invalid collateral amount.",

  // LiquidityController
  LiquidityController__AmountShouldBeGreaterThanZero: "Amount must be greater than zero.",
  LiquidityController__InsufficentFees:
    "Insufficient CCIP fee for cross-chain liquidity operation.",
  LiquidityController__TransferFailed: "Liquidity controller: fee transfer failed.",
  LiquidityController__LpTokenMintFailed: "LP token minting failed.",

  // CrossChainMessageSender
  CrossChainMessageSender__InsufficentFees: "Insufficient CCIP fees.",
  CrossChainMessageSender__DestinationChainNotAllowed:
    "Destination chain {destinationChainSelector} is not whitelisted.",
  CrossChainMessageSender__InvalidReceiverAddress:
    "Invalid cross-chain receiver address.",
  CrossChainMessageSender__InsufficentBalance:
    "Cross-chain sender has insufficient token balance.",

  // GlobalStateManager
  GlobalStateManager__InvalidSender:
    "Caller {sender} is not authorized to update global state.",
  GlobalStateManager__LoanIsNotActive: "Loan is not active in global state.",
  GlobalStateManager__NotLiquidatable: "Loan is not eligible for liquidation.",

  // OpenZeppelin
  SafeERC20FailedOperation:
    "ERC20 operation failed for token {token}. Check your token allowance and balance.",
  ReentrancyGuardReentrantCall: "Reentrancy detected.",
  OwnableUnauthorizedAccount: "Caller {account} is not the contract owner.",
  InvalidInitialization: "Contract is already initialized.",
};

/**
 * Interpolates {placeholder} tokens in a message string with decoded error args.
 */
export function interpolateMessage(
  template: string,
  args: Record<string, string>
): string {
  return template.replace(/\{(\w+)\}/g, (_, key: string) => args[key] ?? `<${key}>`);
}
