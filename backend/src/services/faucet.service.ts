import { ethers } from "ethers";
import { type ChainKey } from "../config/env.js";
import { getERC20Write, getERC20Read } from "../blockchain/contracts.js";
import { sendRaw, getSigner, type TxResult } from "../blockchain/wallet.js";
import { wrapBlockchainError } from "../blockchain/decoder.js";
import { ValidationError } from "../errors.js";
import { getResolvedTokens, getStableCoinMeta } from "./token.service.js";

/**
 * Testnet faucet.
 *
 * The protocol's collateral assets are mock ERC-20s and the stablecoin mints to
 * its owner, which is the deployer key this service signs with. That makes it
 * possible to hand a new user starting balances so they can walk the full
 * deposit → borrow → repay flow without hunting for testnet assets.
 *
 * This is deliberately testnet-only: on a real deployment the mint calls revert,
 * and the error surfaces to the caller unchanged.
 */

/** Per-request cap, expressed in whole tokens, to keep the faucet from being drained. */
const MAX_WHOLE_TOKENS = 1_000_000n;

/** Default drip when the caller does not name an amount. */
const DEFAULT_WHOLE_TOKENS = 10n;

export interface FaucetResult {
  tokenAddress: string;
  symbol: string;
  decimals: number;
  /** Amount minted, in the token's smallest unit */
  amount: string;
  recipient: string;
  tx: TxResult;
}

/** Resolves a faucet target — either a protocol token ID or the stablecoin. */
async function resolveTarget(
  target: string,
  chain: ChainKey
): Promise<{ address: string; symbol: string; decimals: number }> {
  if (target === "stable" || target === "stablecoin") {
    const stable = await getStableCoinMeta(chain);
    return { address: stable.address, symbol: stable.symbol, decimals: stable.decimals };
  }

  const tokenId = Number(target);
  if (!Number.isInteger(tokenId)) {
    throw new ValidationError(`Unknown faucet target: "${target}". Use a token ID or "stable".`);
  }

  const tokens = await getResolvedTokens(chain);
  const token = tokens.find((t) => t.tokenId === tokenId);
  if (!token || !token.registered) {
    throw new ValidationError(`Token ID ${tokenId} is not registered on chain "${chain}".`);
  }
  return { address: token.address, symbol: token.symbol, decimals: token.decimals };
}

/**
 * Mints test tokens to `recipient`.
 *
 * @param target     - Protocol token ID as a string, or "stable" for the stablecoin
 * @param recipient  - Address to receive the tokens
 * @param wholeUnits - Amount in whole tokens (not smallest units). Capped.
 * @param chain      - Chain to mint on
 */
export async function drip(
  target: string,
  recipient: string,
  wholeUnits: bigint | undefined,
  chain: ChainKey
): Promise<FaucetResult> {
  try {
    const amountWhole = wholeUnits ?? DEFAULT_WHOLE_TOKENS;
    if (amountWhole <= 0n) {
      throw new ValidationError("Faucet amount must be greater than zero.");
    }
    if (amountWhole > MAX_WHOLE_TOKENS) {
      throw new ValidationError(
        `Faucet amount is capped at ${MAX_WHOLE_TOKENS} whole tokens per request.`
      );
    }

    const token = await resolveTarget(target, chain);
    const amount = amountWhole * 10n ** BigInt(token.decimals);

    const tx = await sendRaw(chain, async (nonce) => {
      const erc20 = getERC20Write(token.address, chain);
      const gasEstimate: bigint = await erc20.mint.estimateGas(recipient, amount);
      return erc20.mint(recipient, amount, {
        nonce,
        gasLimit: (gasEstimate * 120n) / 100n,
      }) as Promise<ethers.TransactionResponse>;
    });

    return {
      tokenAddress: token.address,
      symbol: token.symbol,
      decimals: token.decimals,
      amount: amount.toString(),
      recipient,
      tx,
    };
  } catch (err) {
    if (err instanceof ValidationError) throw err;
    wrapBlockchainError(err);
  }
}

/**
 * Reports whether the faucet can actually mint each asset on this chain, and the
 * signer's own balances. The UI uses this to hide the faucet on a deployment
 * where minting is not permitted rather than letting the user hit a revert.
 */
export async function getFaucetStatus(chain: ChainKey): Promise<{
  available: boolean;
  signer: string;
  assets: { target: string; symbol: string; address: string; mintable: boolean }[];
}> {
  try {
    const signer = getSigner(chain);
    const [tokens, stable] = await Promise.all([
      getResolvedTokens(chain),
      getStableCoinMeta(chain),
    ]);

    const candidates = [
      ...tokens
        .filter((t) => t.registered)
        .map((t) => ({ target: String(t.tokenId), symbol: t.symbol, address: t.address })),
      { target: "stable", symbol: stable.symbol, address: stable.address },
    ];

    const assets = await Promise.all(
      candidates.map(async (asset) => {
        // A static mint of 1 unit tells us whether the call would revert, without
        // spending gas or changing state.
        const mintable = await getERC20Read(asset.address, chain)
          .mint.staticCall(signer.address, 1n, { from: signer.address })
          .then(() => true)
          .catch(() => false);
        return { ...asset, mintable };
      })
    );

    return {
      available: assets.some((a) => a.mintable),
      signer: signer.address,
      assets,
    };
  } catch (err) {
    wrapBlockchainError(err);
  }
}
