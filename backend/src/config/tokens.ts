/**
 * Static token registry for supported protocol assets.
 *
 * tokenId corresponds to the index in the constructor's tokenAddresses array
 * (0 = WETH, 1 = WBTC by default from the deploy script).
 *
 * Fill in the deployed ERC-20 addresses after running the deploy script.
 * These are populated at runtime from the contract via getTokenAddressFromTokenId,
 * but having them here enables the frontend to show token info before a contract call.
 */
export interface TokenMeta {
  tokenId: number;
  symbol: string;
  name: string;
  decimals: number;
  /** Filled in from env after deployment; null = not yet configured */
  address: string | null;
}

export const SUPPORTED_TOKENS: TokenMeta[] = [
  { tokenId: 0, symbol: "WETH", name: "Wrapped Ether",   decimals: 18, address: null },
  { tokenId: 1, symbol: "WBTC", name: "Wrapped Bitcoin", decimals: 8,  address: null },
];

/** Returns token metadata by ID, or null if unknown. */
export function getTokenMeta(tokenId: number): TokenMeta | null {
  return SUPPORTED_TOKENS.find((t) => t.tokenId === tokenId) ?? null;
}

/** Number of supported token IDs to probe when enumerating (extend if more tokens are added). */
export const MAX_TOKEN_ID = SUPPORTED_TOKENS.length - 1;
