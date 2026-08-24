import { type FastifyInstance } from "fastify";
import { env } from "../config/env.js";
import {
  getTotalLiquidity,
  getTotalLiquidityPerToken,
  getTotalBorrowedForToken,
  getCollateralPerToken,
  getUserBalance,
  getCollateralDetails,
  getLoanDetails,
  getTotalLPTokensForUser,
  getUsdValue,
  getTokenAmountFromUsd,
  getBorrowerIndex,
  getPriceFeedAddress,
  getTokenAddress,
  getStableCoinAddress,
  getLpTokenAddress,
  getVaultAddress,
  getTokenBalance,
  getUserLoanCount,
} from "../services/protocol.service.js";
import { SUPPORTED_TOKENS } from "../config/tokens.js";

const ADDRESS_SCHEMA = {
  type: "string",
  pattern: "^0x[a-fA-F0-9]{40}$",
} as const;

const CHAIN_QS = {
  chain: {
    type: "string",
    enum: ["eth", "arb"],
    description: "Target chain. Defaults to ACTIVE_CHAIN.",
  },
} as const;

export default async function protocolRoutes(fastify: FastifyInstance) {

  // ─── Protocol-level ──────────────────────────────────────────────────────────

  fastify.get<{ Querystring: { chain?: string } }>(
    "/tvl",
    {
      schema: {
        tags: ["protocol"],
        summary: "Total Value Locked across all tokens (USD, 1e18 precision)",
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const total = await getTotalLiquidity(chain);
      return reply.send({ success: true, data: { totalLiquidityUsd: total.toString() } });
    }
  );

  fastify.get<{ Params: { tokenId: string }; Querystring: { chain?: string } }>(
    "/liquidity/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "Total liquidity for a specific token ID",
        params: {
          type: "object",
          required: ["tokenId"],
          properties: { tokenId: { type: "string", pattern: "^[0-9]+$" } },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const amount = await getTotalLiquidityPerToken(BigInt(req.params.tokenId), chain);
      return reply.send({ success: true, data: { tokenId: req.params.tokenId, amount: amount.toString() } });
    }
  );

  fastify.get<{ Params: { tokenId: string }; Querystring: { chain?: string } }>(
    "/borrowed/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "Total borrowed amount for a specific token ID",
        params: {
          type: "object",
          required: ["tokenId"],
          properties: { tokenId: { type: "string", pattern: "^[0-9]+$" } },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const amount = await getTotalBorrowedForToken(BigInt(req.params.tokenId), chain);
      return reply.send({ success: true, data: { tokenId: req.params.tokenId, amount: amount.toString() } });
    }
  );

  fastify.get<{ Params: { tokenId: string }; Querystring: { chain?: string } }>(
    "/collateral/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "Total collateral deposited for a specific token ID",
        params: {
          type: "object",
          required: ["tokenId"],
          properties: { tokenId: { type: "string", pattern: "^[0-9]+$" } },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const amount = await getCollateralPerToken(BigInt(req.params.tokenId), chain);
      return reply.send({ success: true, data: { tokenId: req.params.tokenId, amount: amount.toString() } });
    }
  );

  // ─── User-level ───────────────────────────────────────────────────────────────

  fastify.get<{
    Params: { chainId: string; userAddress: string; tokenId: string };
    Querystring: { chain?: string };
  }>(
    "/user/balance/:chainId/:userAddress/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "User deposit balance",
        params: {
          type: "object",
          required: ["chainId", "userAddress", "tokenId"],
          properties: {
            chainId: { type: "string", pattern: "^[0-9]+$" },
            userAddress: ADDRESS_SCHEMA,
            tokenId: { type: "string", pattern: "^[0-9]+$" },
          },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const { chainId, userAddress, tokenId } = req.params;
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const balance = await getUserBalance(BigInt(chainId), userAddress, BigInt(tokenId), chain);
      return reply.send({ success: true, data: { chainId, userAddress, tokenId, balance: balance.toString() } });
    }
  );

  fastify.get<{
    Params: { chainId: string; userAddress: string; tokenId: string };
    Querystring: { chain?: string };
  }>(
    "/user/collateral/:chainId/:userAddress/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "User collateral details",
        params: {
          type: "object",
          required: ["chainId", "userAddress", "tokenId"],
          properties: {
            chainId: { type: "string", pattern: "^[0-9]+$" },
            userAddress: ADDRESS_SCHEMA,
            tokenId: { type: "string", pattern: "^[0-9]+$" },
          },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const { chainId, userAddress, tokenId } = req.params;
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const amount = await getCollateralDetails(BigInt(chainId), userAddress, BigInt(tokenId), chain);
      return reply.send({ success: true, data: { chainId, userAddress, tokenId, collateral: amount.toString() } });
    }
  );

  fastify.get<{
    Params: { chainId: string; userAddress: string; tokenId: string; loanId: string };
    Querystring: { chain?: string };
  }>(
    "/user/loan/:chainId/:userAddress/:tokenId/:loanId",
    {
      schema: {
        tags: ["protocol"],
        summary: "Loan details",
        description: "Returns the full loan struct including principal, interest paid, collateral used, due date, and status.",
        params: {
          type: "object",
          required: ["chainId", "userAddress", "tokenId", "loanId"],
          properties: {
            chainId: { type: "string", pattern: "^[0-9]+$" },
            userAddress: ADDRESS_SCHEMA,
            tokenId: { type: "string", pattern: "^[0-9]+$" },
            loanId: { type: "string", pattern: "^[0-9]+$" },
          },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const { chainId, userAddress, tokenId, loanId } = req.params;
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const details = await getLoanDetails(
        BigInt(chainId), userAddress, BigInt(tokenId), BigInt(loanId), chain
      );
      return reply.send({ success: true, data: details });
    }
  );

  fastify.get<{ Params: { userAddress: string }; Querystring: { chain?: string } }>(
    "/user/lptokens/:userAddress",
    {
      schema: {
        tags: ["protocol"],
        summary: "User LP token balance",
        params: {
          type: "object",
          required: ["userAddress"],
          properties: { userAddress: ADDRESS_SCHEMA },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const amount = await getTotalLPTokensForUser(req.params.userAddress, chain);
      return reply.send({ success: true, data: { userAddress: req.params.userAddress, lpTokens: amount.toString() } });
    }
  );

  fastify.get<{
    Params: { tokenAddress: string; userAddress: string };
    Querystring: { chain?: string };
  }>(
    "/user/token-balance/:tokenAddress/:userAddress",
    {
      schema: {
        tags: ["protocol"],
        summary: "ERC20 token balance for any address",
        params: {
          type: "object",
          required: ["tokenAddress", "userAddress"],
          properties: {
            tokenAddress: ADDRESS_SCHEMA,
            userAddress: ADDRESS_SCHEMA,
          },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const { tokenAddress, userAddress } = req.params;
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const result = await getTokenBalance(tokenAddress, userAddress, chain);
      return reply.send({ success: true, data: { tokenAddress, userAddress, ...result } });
    }
  );

  // ─── Pricing / index ──────────────────────────────────────────────────────────

  fastify.get<{ Params: { tokenId: string; amount: string }; Querystring: { chain?: string } }>(
    "/usd-value/:tokenId/:amount",
    {
      schema: {
        tags: ["protocol"],
        summary: "USD value of a token amount (1e18 precision)",
        params: {
          type: "object",
          required: ["tokenId", "amount"],
          properties: {
            tokenId: { type: "string", pattern: "^[0-9]+$" },
            amount: { type: "string", pattern: "^[0-9]+$" },
          },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const usd = await getUsdValue(BigInt(req.params.tokenId), BigInt(req.params.amount), chain);
      return reply.send({ success: true, data: { tokenId: req.params.tokenId, amount: req.params.amount, usdValue: usd.toString() } });
    }
  );

  fastify.get<{ Params: { tokenId: string; usdValue: string }; Querystring: { chain?: string } }>(
    "/token-amount/:tokenId/:usdValue",
    {
      schema: {
        tags: ["protocol"],
        summary: "Token amount equivalent to a USD value (1e18 precision)",
        params: {
          type: "object",
          required: ["tokenId", "usdValue"],
          properties: {
            tokenId: { type: "string", pattern: "^[0-9]+$" },
            usdValue: { type: "string", pattern: "^[0-9]+$" },
          },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const tokenAmount = await getTokenAmountFromUsd(BigInt(req.params.tokenId), BigInt(req.params.usdValue), chain);
      return reply.send({ success: true, data: { tokenId: req.params.tokenId, usdValue: req.params.usdValue, tokenAmount: tokenAmount.toString() } });
    }
  );

  fastify.get<{ Params: { tokenId: string }; Querystring: { chain?: string } }>(
    "/borrower-index/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "Current borrower index (interest accumulator) for a token",
        params: {
          type: "object",
          required: ["tokenId"],
          properties: { tokenId: { type: "string", pattern: "^[0-9]+$" } },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const index = await getBorrowerIndex(BigInt(req.params.tokenId), chain);
      return reply.send({ success: true, data: { tokenId: req.params.tokenId, borrowerIndex: index.toString() } });
    }
  );

  // ─── Contract addresses ───────────────────────────────────────────────────────

  fastify.get<{ Params: { tokenId: string }; Querystring: { chain?: string } }>(
    "/price-feed/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "Chainlink price feed address for a token",
        params: { type: "object", required: ["tokenId"], properties: { tokenId: { type: "string", pattern: "^[0-9]+$" } } },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const address = await getPriceFeedAddress(BigInt(req.params.tokenId), chain);
      return reply.send({ success: true, data: { tokenId: req.params.tokenId, priceFeedAddress: address } });
    }
  );

  fastify.get<{ Params: { tokenId: string }; Querystring: { chain?: string } }>(
    "/token-address/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "ERC20 token address for a protocol token ID",
        params: { type: "object", required: ["tokenId"], properties: { tokenId: { type: "string", pattern: "^[0-9]+$" } } },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const address = await getTokenAddress(BigInt(req.params.tokenId), chain);
      return reply.send({ success: true, data: { tokenId: req.params.tokenId, tokenAddress: address } });
    }
  );

  fastify.get<{ Querystring: { chain?: string } }>(
    "/addresses",
    {
      schema: {
        tags: ["protocol"],
        summary: "Key protocol contract addresses (stablecoin, LP token, vault)",
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const [stableCoin, lpToken, vault] = await Promise.all([
        getStableCoinAddress(chain),
        getLpTokenAddress(chain),
        getVaultAddress(chain),
      ]);
      return reply.send({ success: true, data: { stableCoin, lpToken, vault } });
    }
  );

  /**
   * GET /protocol/tokens
   * Returns the static registry of supported tokens (symbol, decimals, tokenId).
   * The frontend uses this to populate token selectors and format amounts.
   */
  fastify.get<{ Querystring: { chain?: string } }>(
    "/tokens",
    {
      schema: {
        tags: ["protocol"],
        summary: "Supported token registry (symbol, decimals, tokenId)",
        description:
          "Returns the list of tokens supported by the protocol with their IDs, " +
          "symbols, and decimals. On-chain addresses are resolved live from the contract.",
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const tokens = await Promise.all(
        SUPPORTED_TOKENS.map(async (t) => {
          const tokenAddress: string = await getTokenAddress(BigInt(t.tokenId), chain);
          return { ...t, address: tokenAddress };
        })
      );
      return reply.send({ success: true, data: { tokens } });
    }
  );

  /**
   * GET /protocol/user/loan-count/:chainId/:userAddress/:tokenId
   * Number of loans a user has taken for a specific token.
   * Use this to enumerate loan IDs (0 .. count-1) before fetching each loan.
   */
  fastify.get<{
    Params: { chainId: string; userAddress: string; tokenId: string };
    Querystring: { chain?: string };
  }>(
    "/user/loan-count/:chainId/:userAddress/:tokenId",
    {
      schema: {
        tags: ["protocol"],
        summary: "Number of loans a user has taken for a token",
        description:
          "Returns the total loan count for a user/token pair. " +
          "Loan IDs run from 0 to count-1. Use GET /protocol/user/loan/:chainId/:user/:tokenId/:loanId to fetch each.",
        params: {
          type: "object",
          required: ["chainId", "userAddress", "tokenId"],
          properties: {
            chainId: { type: "string", pattern: "^[0-9]+$" },
            userAddress: { type: "string", pattern: "^0x[a-fA-F0-9]{40}$" },
            tokenId: { type: "string", pattern: "^[0-9]+$" },
          },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const { chainId, userAddress, tokenId } = req.params;
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";
      const count = await getUserLoanCount(BigInt(chainId), userAddress, BigInt(tokenId), chain);
      return reply.send({ success: true, data: { chainId, userAddress, tokenId, loanCount: count.toString() } });
    }
  );
}
