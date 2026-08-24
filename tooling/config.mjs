/**
 * Shared configuration for the local two-chain demo environment.
 *
 * One hub (Ethereum) and one satellite (Arbitrum), each on its own Anvil node.
 * Chain ids and CCIP selectors deliberately match the real networks so the same
 * Registry entries and relayer routing work unchanged against a testnet.
 */

import { fileURLToPath } from "node:url";
import path from "node:path";

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Anvil's first account — funded, and the deployer/owner of everything. */
export const DEPLOYER = {
  address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
};

export const CHAINS = {
  eth: {
    key: "eth",
    role: "hub",
    name: "Ethereum Sepolia",
    chainId: 424242,
    selector: 16015286601757825753n,
    port: 8545,
    rpcUrl: "http://127.0.0.1:8545",
    script: "script/DeployChainA.s.sol",
  },
  arb: {
    key: "arb",
    role: "satellite",
    name: "Arbitrum Sepolia",
    chainId: 421614,
    selector: 3478487238524512106n,
    port: 8546,
    rpcUrl: "http://127.0.0.1:8546",
    script: "script/DeployChainB.s.sol",
  },
};

export const CHAIN_LIST = Object.values(CHAINS);

/** Written by deploy-local.mjs, read by the relayer and the backend. */
export const DEPLOYMENT_FILE = path.join(REPO_ROOT, "tooling", "deployment.local.json");

/** Resolves a chain config from a CCIP selector, for relayer routing. */
export function chainBySelector(selector) {
  const wanted = BigInt(selector);
  return CHAIN_LIST.find((chain) => chain.selector === wanted);
}
