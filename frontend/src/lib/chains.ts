import { createConfig, http } from "wagmi";
import { defineChain } from "viem";
import { arbitrumSepolia as arbitrumSepoliaBase } from "wagmi/chains";
import { injected, metaMask } from "wagmi/connectors";
import type { ChainKey } from "./types";

/**
 * A local Anvil node forked to Sepolia's chain ID is the standard development
 * setup for this protocol, so both the hosted testnet RPC and localhost resolve
 * to the same wagmi chain. `NEXT_PUBLIC_ETH_RPC_URL` overrides the transport
 * when pointing the UI at a local node.
 */
// Default to the local nodes rather than letting these fall through to viem's
// public endpoints. An unset variable used to mean `http(undefined)`, which
// silently resolved to the public Arbitrum Sepolia RPC: the wallet submitted to
// the local node and succeeded, then the app waited for the receipt on a chain
// that had never seen the transaction. The action modal hung on "Confirming"
// forever even though the transaction had landed.
const ethRpc = process.env.NEXT_PUBLIC_ETH_RPC_URL ?? "http://127.0.0.1:8545";
const arbRpc = process.env.NEXT_PUBLIC_ARB_RPC_URL ?? "http://127.0.0.1:8546";

/**
 * The hub chain, defined locally instead of using viem's `sepolia`.
 *
 * Sepolia's id (11155111) is reserved by MetaMask for its own built-in network,
 * and a custom RPC cannot take ownership of it — transactions get built against
 * public Sepolia, where the local accounts hold nothing, so every send fails on
 * "insufficient funds". Running the hub on its own id removes the collision.
 * The contracts still default to the real testnet ids; the deploy script points
 * this deployment at these.
 */
export const astraHub = defineChain({
  id: 424242,
  name: "AstraLend Hub",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
});

/** The satellite, repointed at the local node for the same reason as above. */
export const astraSatellite = defineChain({
  ...arbitrumSepoliaBase,
  rpcUrls: { default: { http: [arbRpc] } },
});

export const wagmiConfig = createConfig({
  chains: [astraHub, astraSatellite],
  connectors: [metaMask(), injected({ shimDisconnect: true })],
  transports: {
    [astraHub.id]: http(ethRpc),
    [astraSatellite.id]: http(arbRpc),
  },
  ssr: true,
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}

// ─── Chain metadata ───────────────────────────────────────────────────────────

export interface ChainMeta {
  key: ChainKey;
  id: number;
  name: string;
  shortName: string;
  /** The hub chain owns global state; satellites mirror to it over CCIP. */
  role: "hub" | "satellite";
  explorer: string;
  accent: string;
}

export const CHAINS: Record<ChainKey, ChainMeta> = {
  eth: {
    key: "eth",
    id: astraHub.id,
    name: "AstraLend Hub",
    shortName: "Ethereum",
    role: "hub",
    explorer: "https://sepolia.etherscan.io",
    accent: "#8b5cf6",
  },
  arb: {
    key: "arb",
    id: astraSatellite.id,
    name: "Arbitrum Sepolia",
    shortName: "Arbitrum",
    role: "satellite",
    explorer: "https://sepolia.arbiscan.io",
    accent: "#22d3ee",
  },
};

export const CHAIN_LIST = Object.values(CHAINS);

export function chainKeyFromId(chainId: number | undefined): ChainKey | undefined {
  return CHAIN_LIST.find((chain) => chain.id === chainId)?.key;
}

export function explorerTx(chain: ChainKey, hash: string): string {
  return `${CHAINS[chain].explorer}/tx/${hash}`;
}

export function explorerAddress(chain: ChainKey, address: string): string {
  return `${CHAINS[chain].explorer}/address/${address}`;
}
