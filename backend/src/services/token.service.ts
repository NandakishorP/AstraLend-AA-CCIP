import { type ChainKey } from "../config/env.js";
import { SUPPORTED_TOKENS, type TokenMeta } from "../config/tokens.js";
import { getLendingPoolRead, getERC20Read } from "../blockchain/contracts.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { cached } from "../utils/cache.js";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/** Token metadata with the on-chain address and decimals resolved. */
export interface ResolvedToken extends TokenMeta {
  address: string;
  /** True when the protocol has a price feed registered for this token ID. */
  registered: boolean;
}

/** Contract addresses and metadata never change for a deployment — cache aggressively. */
const TOKEN_TTL_MS = 5 * 60 * 1000;

/**
 * Resolves the live ERC-20 address, symbol and decimals for every supported token ID.
 *
 * The static registry in config/tokens.ts is only a fallback: the deploy script wires
 * arbitrary mock ERC-20s, so decimals must come from the token itself rather than
 * being assumed. A token whose address resolves to the zero address is reported with
 * `registered: false` instead of throwing — the frontend renders it as unavailable.
 */
export async function getResolvedTokens(chain: ChainKey): Promise<ResolvedToken[]> {
  return cached(`tokens:${chain}`, TOKEN_TTL_MS, async () => {
    try {
      const pool = getLendingPoolRead(chain);

      return await Promise.all(
        SUPPORTED_TOKENS.map(async (meta): Promise<ResolvedToken> => {
          const address: string = await pool.getTokenAddressFromTokenId(meta.tokenId);
          if (!address || address === ZERO_ADDRESS) {
            return { ...meta, address: ZERO_ADDRESS, registered: false };
          }

          // Decimals must come from the token — the testnet mocks are all 18 even
          // where the real asset is not. The symbol, by contrast, stays with the
          // registry: the mocks all report "E20M", which is useless in a UI.
          const decimals = await getERC20Read(address, chain)
            .decimals()
            .then(Number)
            .catch(() => meta.decimals);

          return { ...meta, address, decimals, registered: true };
        })
      );
    } catch (err) {
      wrapBlockchainError(err);
    }
  });
}

/** Resolves a single token by ID. Throws if the ID is not in the registry. */
export async function getResolvedToken(tokenId: number, chain: ChainKey): Promise<ResolvedToken> {
  const tokens = await getResolvedTokens(chain);
  const token = tokens.find((t) => t.tokenId === tokenId);
  if (!token) throw new Error(`Unknown token ID: ${tokenId}`);
  return token;
}

/** Stablecoin address + decimals for the chain, resolved from the contract. */
export async function getStableCoinMeta(chain: ChainKey): Promise<{
  address: string;
  decimals: number;
  symbol: string;
}> {
  return cached(`stable:${chain}`, TOKEN_TTL_MS, async () => {
    try {
      const address: string = await getLendingPoolRead(chain).getStableCoinAddress();
      const erc20 = getERC20Read(address, chain);
      const [decimals, symbol] = await Promise.all([
        erc20.decimals().then(Number).catch(() => 6),
        erc20.symbol().then(String).catch(() => "USDT"),
      ]);
      return { address, decimals, symbol };
    } catch (err) {
      wrapBlockchainError(err);
    }
  });
}

/** LP token address + decimals for the chain. */
export async function getLpTokenMeta(chain: ChainKey): Promise<{
  address: string;
  decimals: number;
  symbol: string;
}> {
  return cached(`lptoken:${chain}`, TOKEN_TTL_MS, async () => {
    try {
      const address: string = await getLendingPoolRead(chain).getLpTokenAddress();
      const decimals = await getERC20Read(address, chain)
        .decimals()
        .then(Number)
        .catch(() => 18);

      // The deployed LP token inherits the stablecoin's ERC-20 name and ticker,
      // so its on-chain symbol would show up as a duplicate of the stablecoin in
      // every balance list. Label it by its protocol role instead.
      return { address, decimals, symbol: "ALP" };
    } catch (err) {
      wrapBlockchainError(err);
    }
  });
}
