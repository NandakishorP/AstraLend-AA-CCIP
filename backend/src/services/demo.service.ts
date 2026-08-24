import { ethers } from "ethers";
import fs from "node:fs";
import path from "node:path";
import { CHAIN_CONFIGS, type ChainKey } from "../config/env.js";
import { getProvider } from "../blockchain/providers.js";
import { getSigner } from "../blockchain/wallet.js";
import { getLendingPoolRead } from "../blockchain/contracts.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { AppError, ValidationError } from "../errors.js";
import { getResolvedTokens } from "./token.service.js";

/**
 * Demo-environment controls.
 *
 * These exist so the protocol can be shown end to end on local nodes: a
 * 180-day loan term and a liquidation cascade are not demonstrable on a real
 * testnet, but a local chain can be moved forward in time at will.
 *
 * Every endpoint here is inert unless the local demo environment is present.
 * They depend on Anvil-only RPC methods (`evm_increaseTime`, `evm_mine`) and on
 * the deployment manifest that tooling/deploy-local.mjs writes — against a real
 * network there is no manifest, and the routes report themselves unavailable
 * rather than doing anything.
 */

const DEPLOYMENT_FILE = path.resolve(process.cwd(), "..", "tooling", "deployment.local.json");
const RELAYER_URL = process.env["RELAYER_URL"] ?? "http://127.0.0.1:8547";

interface DeploymentManifest {
  createdAt: string;
  chains: Record<string, Record<string, string>>;
}

/** Reads the local deployment manifest, or null when not in a demo environment. */
export function readManifest(): DeploymentManifest | null {
  try {
    if (!fs.existsSync(DEPLOYMENT_FILE)) return null;
    return JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8")) as DeploymentManifest;
  } catch {
    return null;
  }
}

function requireManifest(): DeploymentManifest {
  const manifest = readManifest();
  if (!manifest) {
    throw new AppError(
      "Demo controls are only available in the local two-chain environment. " +
        "Start it with tooling/start-demo.sh.",
      503,
      "DEMO_UNAVAILABLE"
    );
  }
  return manifest;
}

// ─── Environment status ───────────────────────────────────────────────────────

export interface RelayerMessage {
  messageId: string;
  from: string;
  to: string;
  status: "pending" | "delivered" | "reverted" | "failed" | "undeliverable";
  sentAt: string;
  deliveredAt: string | null;
  sourceTxHash: string;
  destinationTxHash: string | null;
  error: string | null;
}

export interface DemoChainStatus {
  chain: ChainKey;
  name: string;
  chainId: number;
  role: "hub" | "satellite";
  blockNumber: number;
  /** Chain clock, which time-travel moves independently of wall time. */
  timestamp: number;
  timestampISO: string;
  /** Seconds the chain clock runs ahead of real time. */
  skewSeconds: number;
  reachable: boolean;
}

export interface DemoStatus {
  available: boolean;
  deployedAt: string | null;
  chains: DemoChainStatus[];
  relayer: { reachable: boolean; pending: number; delivered: number };
  messages: RelayerMessage[];
}

async function fetchRelayer(pathname: string): Promise<unknown | null> {
  try {
    const response = await fetch(`${RELAYER_URL}${pathname}`, {
      signal: AbortSignal.timeout(2000),
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

/** Everything the demo panel renders in one call. */
export async function getDemoStatus(): Promise<DemoStatus> {
  const manifest = readManifest();
  const now = Math.floor(Date.now() / 1000);

  const chains = await Promise.all(
    (Object.keys(CHAIN_CONFIGS) as ChainKey[]).map(async (chain): Promise<DemoChainStatus> => {
      const config = CHAIN_CONFIGS[chain];
      const base = {
        chain,
        name: config.name,
        chainId: config.chainId,
        role: (chain === "eth" ? "hub" : "satellite") as "hub" | "satellite",
      };
      try {
        const provider = getProvider(chain);
        const block = await provider.getBlock("latest");
        if (!block) throw new Error("no block");
        return {
          ...base,
          blockNumber: block.number,
          timestamp: block.timestamp,
          timestampISO: new Date(block.timestamp * 1000).toISOString(),
          skewSeconds: block.timestamp - now,
          reachable: true,
        };
      } catch {
        return {
          ...base,
          blockNumber: 0,
          timestamp: 0,
          timestampISO: new Date(0).toISOString(),
          skewSeconds: 0,
          reachable: false,
        };
      }
    })
  );

  const messagesBody = (await fetchRelayer("/messages")) as
    | { data?: { messages?: RelayerMessage[] } }
    | null;
  const summaryBody = (await fetchRelayer("/")) as
    | { data?: { pending?: number; delivered?: number } }
    | null;

  const messages = messagesBody?.data?.messages ?? [];

  return {
    available: manifest !== null,
    deployedAt: manifest?.createdAt ?? null,
    chains,
    relayer: {
      reachable: summaryBody !== null,
      pending: summaryBody?.data?.pending ?? 0,
      delivered: summaryBody?.data?.delivered ?? 0,
    },
    messages,
  };
}

// ─── Time travel ──────────────────────────────────────────────────────────────

export interface TimeTravelResult {
  advancedSeconds: number;
  chains: { chain: ChainKey; timestamp: number; timestampISO: string }[];
}

/**
 * Advances every configured chain's clock by the same amount.
 *
 * Both chains move together deliberately: letting them drift apart would make
 * a loan look overdue on one side and current on the other, which is confusing
 * to watch and not a state a real deployment can reach.
 */
export async function timeTravel(seconds: number): Promise<TimeTravelResult> {
  requireManifest();
  if (!Number.isFinite(seconds) || seconds <= 0) {
    throw new ValidationError("Advance must be a positive number of seconds.");
  }
  if (seconds > 400 * 24 * 60 * 60) {
    throw new ValidationError("Refusing to advance more than 400 days in one step.");
  }

  const chains: TimeTravelResult["chains"] = [];
  for (const chain of Object.keys(CHAIN_CONFIGS) as ChainKey[]) {
    try {
      const provider = getProvider(chain);
      await provider.send("evm_increaseTime", [seconds]);
      await provider.send("evm_mine", []);
      const block = await provider.getBlock("latest");
      chains.push({
        chain,
        timestamp: block?.timestamp ?? 0,
        timestampISO: new Date((block?.timestamp ?? 0) * 1000).toISOString(),
      });
    } catch (err) {
      throw new AppError(
        `Chain "${chain}" does not support time travel — is it an Anvil node? ` +
          `(${(err as Error).message})`,
        503,
        "DEMO_UNAVAILABLE"
      );
    }
  }

  return { advancedSeconds: seconds, chains };
}

// ─── Liquidation keeper ───────────────────────────────────────────────────────

const GSM_ABI = [
  "function checkUpkeep(bytes) view returns (bool upkeepNeeded, bytes performData)",
  "function performUpkeep(bytes performData)",
];

const POOL_LOAN_ABI = [
  "function getUserLoanCount(uint256 chainId, address user, uint64 tokenId) view returns (uint256)",
  "function getLoanDetails(uint256 chainId, address user, uint64 tokenId, uint256 loanId) view returns (tuple(address token, uint256 amountBorrowedInUSDT, uint256 principalAmount, uint256 collateralUsed, uint256 collateralChainId, uint256 lastUpdate, address asset, uint256 userBorrowIndex, uint256 interestPaid, uint256 liquidationPoint, uint256 loanChainId, uint256 dueDate, bool isClosed, uint256 loanId, uint8 penaltyCount, bool isLiquidated))",
];

export interface KeeperCandidate {
  chainId: number;
  borrower: string;
  tokenId: number;
  loanId: number;
  dueDate: number;
  overdueDays: number;
  penaltyCount: number;
  outstanding: string;
}

export interface KeeperRunResult {
  scanned: number;
  acted: { candidate: KeeperCandidate; txHash: string; outcome: string }[];
  message: string;
}

/**
 * Finds loans the keeper can act on for one borrower.
 *
 * The scan runs here rather than through the GSM's own `checkUpkeep` because
 * that function's output cannot currently be fed to `performUpkeep` — it
 * encodes the borrower first while `performUpkeep` decodes a chain id first.
 * `performUpkeep` itself is correct, so the backend enumerates candidates and
 * encodes the payload the way the executor expects.
 */
export async function findKeeperCandidates(
  userAddress: string,
  chain: ChainKey = "eth"
): Promise<KeeperCandidate[]> {
  try {
    const provider = getProvider(chain);
    const poolAddress = CHAIN_CONFIGS[chain].lendingPool;
    if (!poolAddress) return [];

    const pool = new ethers.Contract(poolAddress, POOL_LOAN_ABI, provider);
    const tokens = await getResolvedTokens(chain);
    const block = await provider.getBlock("latest");
    const now = block?.timestamp ?? Math.floor(Date.now() / 1000);

    // Loans are keyed by the chain they were taken on; on the hub that means
    // both the hub's own chain id and any satellite a loan was opened from.
    const chainIds = (Object.keys(CHAIN_CONFIGS) as ChainKey[]).map(
      (key) => CHAIN_CONFIGS[key].chainId
    );

    const candidates: KeeperCandidate[] = [];

    for (const chainId of chainIds) {
      for (const token of tokens) {
        if (!token.registered) continue;
        const count: bigint = await pool
          .getUserLoanCount(chainId, userAddress, token.tokenId)
          .catch(() => 0n);

        // Loan ids are 1-based.
        for (let loanId = 1; loanId <= Number(count); loanId++) {
          const loan = await pool
            .getLoanDetails(chainId, userAddress, token.tokenId, loanId)
            .catch(() => null);
          if (!loan || loan.token === ethers.ZeroAddress) continue;
          if (loan.isClosed || loan.isLiquidated) continue;

          const dueDate = Number(loan.dueDate);
          if (dueDate === 0 || now <= dueDate) continue;

          candidates.push({
            chainId,
            borrower: userAddress,
            tokenId: token.tokenId,
            loanId,
            dueDate,
            overdueDays: Math.floor((now - dueDate) / 86_400),
            penaltyCount: Number(loan.penaltyCount),
            outstanding: loan.amountBorrowedInUSDT.toString(),
          });
        }
      }
    }

    return candidates;
  } catch (err) {
    wrapBlockchainError(err);
  }
}

/**
 * Runs the keeper against every overdue loan for a borrower.
 *
 * The contract escalates rather than liquidating outright: the first two runs
 * add a 5% penalty and extend the due date by 30 days, and only the third
 * liquidates. The UI surfaces that so the escalation is visible rather than
 * looking like a no-op.
 */
export async function runKeeper(userAddress: string): Promise<KeeperRunResult> {
  const manifest = requireManifest();
  const gsmAddress = manifest.chains["eth"]?.["gsm"];
  if (!gsmAddress) {
    throw new AppError("Deployment manifest has no GSM address.", 503, "DEMO_UNAVAILABLE");
  }

  const candidates = await findKeeperCandidates(userAddress, "eth");
  if (candidates.length === 0) {
    return { scanned: 0, acted: [], message: "No overdue loans — nothing for the keeper to do." };
  }

  const signer = getSigner("eth");
  const gsm = new ethers.Contract(gsmAddress, GSM_ABI, signer);
  const acted: KeeperRunResult["acted"] = [];

  for (const candidate of candidates) {
    const performData = ethers.AbiCoder.defaultAbiCoder().encode(
      ["uint256", "address", "uint64", "uint256"],
      [candidate.chainId, candidate.borrower, candidate.tokenId, candidate.loanId]
    );

    try {
      const tx = await gsm.performUpkeep(performData, { gasLimit: 8_000_000 });
      const receipt = await tx.wait();
      acted.push({
        candidate,
        txHash: receipt.hash,
        outcome:
          candidate.penaltyCount >= 2
            ? "liquidated — collateral seized and the loan closed"
            : `penalty ${candidate.penaltyCount + 1} of 2 applied, +5% debt, due date extended 30 days`,
      });
    } catch (err) {
      acted.push({
        candidate,
        txHash: "",
        outcome: `keeper call failed: ${(err as Error).message.split("\n")[0]}`,
      });
    }
  }

  return {
    scanned: candidates.length,
    acted,
    message: `Keeper acted on ${acted.length} overdue loan(s).`,
  };
}
