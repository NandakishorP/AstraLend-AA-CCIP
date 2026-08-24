import { ethers } from "ethers";
import { CHAIN_CONFIGS, type ChainKey } from "../config/env.js";
import { ConfigError, BlockchainError } from "../errors.js";

// One provider instance per chain, lazily created and reused.
const providerCache = new Map<ChainKey, ethers.JsonRpcProvider>();

export function getProvider(chain: ChainKey): ethers.JsonRpcProvider {
  const cached = providerCache.get(chain);
  if (cached) return cached;

  const config = CHAIN_CONFIGS[chain];
  if (!config.rpcUrl) {
    throw new ConfigError(`RPC URL not configured for chain "${chain}"`);
  }

  const provider = new ethers.JsonRpcProvider(config.rpcUrl, config.chainId, {
    staticNetwork: ethers.Network.from(config.chainId),
  });

  providerCache.set(chain, provider);
  return provider;
}

/**
 * Verifies the provider can reach the network and returns the current block number.
 * Throws BlockchainError if the provider is unreachable.
 */
export async function checkProviderHealth(chain: ChainKey): Promise<{
  chainId: number;
  blockNumber: number;
  latencyMs: number;
}> {
  const provider = getProvider(chain);
  const start = Date.now();
  try {
    const [network, blockNumber] = await Promise.all([
      provider.getNetwork(),
      provider.getBlockNumber(),
    ]);
    return {
      chainId: Number(network.chainId),
      blockNumber,
      latencyMs: Date.now() - start,
    };
  } catch (err) {
    throw new BlockchainError(
      `Provider for chain "${chain}" is unreachable: ${(err as Error).message}`,
      err
    );
  }
}
