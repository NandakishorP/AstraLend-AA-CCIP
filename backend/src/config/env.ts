import "dotenv/config";
import { z } from "zod";
import { ConfigError } from "../errors.js";

const envSchema = z.object({
  // RPC URLs
  ETH_SEPOLIA_RPC_URL: z.string().url("ETH_SEPOLIA_RPC_URL must be a valid URL"),
  ARB_SEPOLIA_RPC_URL: z.string().url("ARB_SEPOLIA_RPC_URL must be a valid URL"),

  // Signer
  PRIVATE_KEY: z
    .string()
    .regex(/^0x[0-9a-fA-F]{64}$/, "PRIVATE_KEY must be a 32-byte hex string prefixed with 0x"),

  // Active chain
  ACTIVE_CHAIN: z.enum(["eth", "arb"]).default("eth"),

  // Contract addresses — optional at startup, validated per-request
  ETH_LENDING_POOL_ADDRESS: z.string().optional(),
  ETH_VAULT_ADDRESS: z.string().optional(),
  ETH_STABLE_COIN_ADDRESS: z.string().optional(),
  ARB_LENDING_POOL_ADDRESS: z.string().optional(),
  ARB_VAULT_ADDRESS: z.string().optional(),
  ARB_STABLE_COIN_ADDRESS: z.string().optional(),

  // Real-world asset collateral. Hub-only by design: the instrument exists on
  // one chain and only messages about its encumbrance ever cross, so there are
  // no satellite equivalents of these.
  RWA_TOKEN_ADDRESS: z.string().optional(),
  RWA_ISSUER_ADDRESS: z.string().optional(),
  RWA_LIEN_REGISTRY_ADDRESS: z.string().optional(),
  RWA_ELIGIBILITY_ADDRESS: z.string().optional(),
  RWA_NAV_ORACLE_ADDRESS: z.string().optional(),

  // CCIP router per chain. Indexing these lets the API track cross-chain
  // messages in flight; without them everything else still works.
  ETH_CCIP_ROUTER_ADDRESS: z.string().optional(),
  ARB_CCIP_ROUTER_ADDRESS: z.string().optional(),

  // Persistence + indexer
  DATABASE_PATH: z.string().default("./data/astralend.db"),
  /** Set false to run the API as a pure pass-through to the chain. */
  INDEXER_ENABLED: z
    .string()
    .default("true")
    .transform((value) => value !== "false"),
  /** How often to look for new blocks, in ms. */
  INDEXER_POLL_MS: z.coerce.number().int().positive().default(2000),
  /** Blocks per getLogs window during backfill. */
  INDEXER_BATCH_BLOCKS: z.coerce.number().int().positive().default(2000),
  /** How often to write a protocol/market time-series row, in ms. */
  SNAPSHOT_INTERVAL_MS: z.coerce.number().int().positive().default(30_000),

  // Server
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default("0.0.0.0"),
  LOG_LEVEL: z.enum(["trace", "debug", "info", "warn", "error", "fatal"]).default("info"),
});

function parseEnv() {
  const result = envSchema.safeParse(process.env);
  if (!result.success) {
    const formatted = result.error.issues
      .map((i) => `  • ${i.path.join(".")}: ${i.message}`)
      .join("\n");
    throw new Error(`Invalid environment configuration:\n${formatted}`);
  }
  return result.data;
}

export const env = parseEnv();

export type ChainKey = "eth" | "arb";

export const CHAIN_CONFIGS: Record<ChainKey, {
  chainId: number;
  name: string;
  rpcUrl: string;
  lendingPool: string | undefined;
  vault: string | undefined;
  stableCoin: string | undefined;
  ccipRouter: string | undefined;
  /** CCIP chain selector — the id cross-chain messages are addressed with. */
  chainSelector: string;
}> = {
  eth: {
    chainId: 424242,
    name: "Ethereum Sepolia",
    rpcUrl: env.ETH_SEPOLIA_RPC_URL,
    lendingPool: env.ETH_LENDING_POOL_ADDRESS,
    vault: env.ETH_VAULT_ADDRESS,
    stableCoin: env.ETH_STABLE_COIN_ADDRESS,
    ccipRouter: env.ETH_CCIP_ROUTER_ADDRESS,
    chainSelector: "16015286601757825753",
  },
  arb: {
    chainId: 421614,
    name: "Arbitrum Sepolia",
    rpcUrl: env.ARB_SEPOLIA_RPC_URL,
    lendingPool: env.ARB_LENDING_POOL_ADDRESS,
    vault: env.ARB_VAULT_ADDRESS,
    stableCoin: env.ARB_STABLE_COIN_ADDRESS,
    ccipRouter: env.ARB_CCIP_ROUTER_ADDRESS,
    chainSelector: "3478487238524512106",
  },
};

export function getChainConfig(chain: ChainKey) {
  return CHAIN_CONFIGS[chain];
}

export function requireAddress(chain: ChainKey, key: "lendingPool" | "vault" | "stableCoin"): string {
  const config = CHAIN_CONFIGS[chain];
  const value = config[key];
  if (!value) {
    // Thrown as a typed ConfigError so the API answers with a readable
    // "not deployed on this chain" message instead of a bare 500.
    throw new ConfigError(
      `AstraLend is not configured on ${config.name}: no ${key} address. ` +
        `Set ${chain.toUpperCase()}_${key === "lendingPool" ? "LENDING_POOL" : key === "stableCoin" ? "STABLE_COIN" : "VAULT"}_ADDRESS after deploying there.`
    );
  }
  return value;
}
