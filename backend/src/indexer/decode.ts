import { ethers } from "ethers";
import { createRequire } from "module";

const require = createRequire(import.meta.url);
const { abi: LendingPoolABI } = require("../abis/LendingPoolContract.json") as {
  abi: ethers.InterfaceAbi;
};

/**
 * Log decoding, shared by the indexer and the activity API.
 *
 * The event vocabulary lives here rather than in a service so that what gets
 * written to the database and what gets rendered can never drift apart.
 */

export const poolInterface = new ethers.Interface(LendingPoolABI);

/** The GSM's liquidation event — not part of the pool ABI. */
export const gsmInterface = new ethers.Interface([
  "event LoanLiquidated(address indexed user, address indexed token, uint256 loanAmount, uint256 collateralValue, uint256 liquidationPenalty)",
]);

/** The mock router's send event — the source half of a cross-chain message. */
export const mockRouterInterface = new ethers.Interface([
  "event MockCCIPMessageSent(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address indexed sender, address receiver, bytes data, uint256 feePaid)",
]);

export type ActivityKind =
  | "supply"
  | "withdraw"
  | "collateral-deposit"
  | "collateral-withdraw"
  | "collateral-release"
  | "borrow"
  | "repay"
  | "lp-burn"
  | "ccip-out"
  | "ccip-in"
  | "liquidation"
  | "lien-created"
  | "lien-released"
  | "lien-foreclosed"
  | "eligibility";

/**
 * Every protocol event the UI renders, mapped to a stable, human-facing kind.
 * Events not listed here (admin, plumbing) are ignored by the indexer.
 */
export const EVENT_KINDS: Record<string, { kind: ActivityKind; label: string }> = {
  LiquidityDeposited: { kind: "supply", label: "Supplied liquidity" },
  DepositWithdrawn: { kind: "withdraw", label: "Withdrew liquidity" },
  CollateralDeposited: { kind: "collateral-deposit", label: "Deposited collateral" },
  CollateralWithdrawed: { kind: "collateral-withdraw", label: "Withdrew collateral" },
  CollateralReleased: { kind: "collateral-release", label: "Collateral released" },
  LoanBorrowed: { kind: "borrow", label: "Borrowed" },
  LoanRepaid: { kind: "repay", label: "Repaid loan" },
  LpTokensBurned: { kind: "lp-burn", label: "Burned LP tokens" },
  DepositCollateralInitiated: { kind: "ccip-out", label: "Cross-chain collateral sent" },
  TokenTransferInitiated: { kind: "ccip-out", label: "Cross-chain transfer sent" },
  TokensReceivedFromCrossChain: { kind: "ccip-in", label: "Cross-chain transfer received" },
  LoanLiquidated: { kind: "liquidation", label: "Loan liquidated" },
  // Real-world asset collateral. LienCreated is not a log about a pledge
  // recorded elsewhere — it is the register entry itself, which is what makes
  // the charge good against third parties.
  LienCreated: { kind: "lien-created", label: "Collateral encumbered" },
  // Emitted by the security itself, not by us — the freeze is the issuer's
  // contract acting on our instruction as an appointed agent.
  TokensFrozen: { kind: "lien-created", label: "Security frozen in place" },
  TokensUnfrozen: { kind: "lien-released", label: "Security unfrozen" },
  LienIncreased: { kind: "lien-created", label: "Encumbrance increased" },
  LienDecreased: { kind: "lien-released", label: "Encumbrance reduced" },
  LienReleased: { kind: "lien-released", label: "Collateral released" },
  LienForeclosed: { kind: "lien-foreclosed", label: "Collateral foreclosed" },
  EligibilityGranted: { kind: "eligibility", label: "Eligibility attested" },
  EligibilityRevoked: { kind: "eligibility", label: "Eligibility revoked" },
};

export interface DecodedEvent {
  eventName: string;
  kind: ActivityKind;
  label: string;
  userAddress: string | null;
  tokenAddress: string | null;
  amount: string | null;
  args: Record<string, string>;
}

/**
 * Decodes one protocol log, or returns null when it is not a UI-facing event.
 *
 * Addresses are lower-cased on the way in so that database lookups by user are
 * exact-match rather than case-sensitive guesswork.
 */
export function decodeProtocolLog(log: {
  topics: readonly string[];
  data: string;
}): DecodedEvent | null {
  let parsed: ethers.LogDescription | null = null;
  for (const iface of [poolInterface, gsmInterface]) {
    try {
      parsed = iface.parseLog({ topics: [...log.topics], data: log.data });
      if (parsed) break;
    } catch {
      // Not this ABI; try the next.
    }
  }
  if (!parsed) return null;

  const mapping = EVENT_KINDS[parsed.name];
  if (!mapping) return null;

  const args: Record<string, string> = {};
  let userAddress: string | null = null;
  let tokenAddress: string | null = null;
  let amount: string | null = null;

  parsed.fragment.inputs.forEach((input, i) => {
    const value = parsed.args[i];

    // An indexed struct — LoanBorrowed carries one — is hashed by the EVM, so
    // the topic holds a digest rather than the fields. Nothing to surface.
    if (input.type === "tuple") return;

    const asString = value?.toString() ?? "";

    if (input.name === "user" || input.name === "user_") {
      userAddress = asString.toLowerCase();
      return;
    }
    if (input.type === "address" && tokenAddress === null) {
      tokenAddress = ethers.getAddress(asString);
      return;
    }
    if (amount === null && input.type.startsWith("uint") && /amount|total/i.test(input.name)) {
      amount = asString;
      return;
    }
    args[input.name] = asString;
  });

  return {
    eventName: parsed.name,
    kind: mapping.kind,
    label: mapping.label,
    userAddress,
    tokenAddress,
    amount,
    args,
  };
}

export interface DecodedCcipSend {
  messageId: string;
  destinationChainSelector: string;
  sender: string;
  receiver: string;
  feePaid: string;
  /** The acting user, recovered from the protocol payload when decodable. */
  userAddress: string | null;
  /** The protocol action the message carries, when decodable. */
  action: string | null;
}

/**
 * Decodes the mock router's send event.
 *
 * The payload is the protocol's own `CrossChainPayLoad` struct, ABI-encoded
 * behind a leading communication id. Decoding it is best-effort: it lets the UI
 * attribute a message to a user and label it, but a payload shape this indexer
 * does not recognise is still recorded as an untagged in-flight message rather
 * than being dropped.
 */
export function decodeCcipSend(log: {
  topics: readonly string[];
  data: string;
}): DecodedCcipSend | null {
  let parsed: ethers.LogDescription | null = null;
  try {
    parsed = mockRouterInterface.parseLog({ topics: [...log.topics], data: log.data });
  } catch {
    return null;
  }
  if (!parsed) return null;

  const payload = decodePayload(parsed.args.data as string);

  return {
    messageId: parsed.args.messageId as string,
    destinationChainSelector: (parsed.args.destinationChainSelector as bigint).toString(),
    sender: ethers.getAddress(parsed.args.sender as string),
    receiver: ethers.getAddress(parsed.args.receiver as string),
    feePaid: (parsed.args.feePaid as bigint).toString(),
    userAddress: payload?.user ?? null,
    action: payload?.action ?? null,
  };
}

/** Action ids as ordered in `LendingPoolContract.ActionType`. */
const ACTION_TYPES = [
  "DEPOSIT_LIQUIDITY",
  "WITHDRAW_LIQUIDITY",
  "DEPOSIT_COLLATERAL",
  "WITHDRAW_COLLATERAL",
  "BORROW_LOAN",
  "REPAY_LOAN",
  "TRANSFER",
];

function decodePayload(data: string): { user: string; action: string | null } | null {
  try {
    // (uint64 communicationId, CrossChainPayLoad)
    const [, payload] = ethers.AbiCoder.defaultAbiCoder().decode(
      [
        "uint64",
        "tuple(uint8 actionType, uint64 chainId, address user, uint64 crossChaintokenId, uint256 amountToTransfer, string messageToTransfer, bytes extraInformation)",
      ],
      data
    );
    return {
      user: (payload.user as string).toLowerCase(),
      action: ACTION_TYPES[Number(payload.actionType)] ?? null,
    };
  } catch {
    return null;
  }
}
