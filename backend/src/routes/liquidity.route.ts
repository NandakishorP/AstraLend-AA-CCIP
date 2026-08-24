import { type FastifyInstance } from "fastify";
import { env } from "../config/env.js";
import { depositLiquidity, withdrawLiquidity } from "../services/liquidity.service.js";

// ─── Shared schema fragments ──────────────────────────────────────────────────

const ADDRESS_SCHEMA = {
  type: "string",
  pattern: "^0x[a-fA-F0-9]{40}$",
  description: "Ethereum address (0x-prefixed, 20 bytes)",
} as const;

const UINT_STRING_SCHEMA = {
  type: "string",
  pattern: "^[0-9]+$",
  description: "Non-negative integer as a decimal string (avoids JS BigInt precision loss)",
} as const;

const CHAIN_SCHEMA = {
  type: "string",
  enum: ["eth", "arb"],
  description: "Target chain. Defaults to ACTIVE_CHAIN from server config.",
} as const;

const TX_RESULT_SCHEMA = {
  type: "object",
  properties: {
    txHash: { type: "string" },
    blockNumber: { type: "number" },
    gasUsed: { type: "string" },
  },
} as const;

const APPROVAL_RESULT_SCHEMA = {
  type: "object",
  properties: {
    wasNeeded: { type: "boolean" },
    txHash: { type: ["string", "null"] },
    blockNumber: { type: ["number", "null"] },
    gasUsed: { type: ["string", "null"] },
  },
} as const;

// ─── Routes ───────────────────────────────────────────────────────────────────

export default async function liquidityRoutes(fastify: FastifyInstance) {
  /**
   * POST /liquidity/deposit
   *
   * Adds liquidity to the lending pool. Mints LP tokens proportionally to the
   * current pool size. Automatically approves the Vault for the token if the
   * current allowance is insufficient.
   *
   * On Ethereum Sepolia: state is updated directly in GlobalStateManager.
   * On Arbitrum Sepolia: a CCIP message is sent to Ethereum — include ccipFee.
   */
  fastify.post<{
    Body: {
      tokenAddress: string;
      tokenId: number;
      amount: string;
      ccipFee?: string;
      chain?: string;
    };
  }>(
    "/deposit",
    {
      schema: {
        tags: ["liquidity"],
        summary: "Deposit liquidity — receive LP tokens",
        description:
          "Deposits ERC20 tokens into the lending pool. LP tokens are minted proportionally. " +
          "The Vault approval is handled automatically. " +
          "On non-Ethereum chains, a ccipFee in native wei must be provided.",
        body: {
          type: "object",
          required: ["tokenAddress", "tokenId", "amount"],
          additionalProperties: false,
          properties: {
            tokenAddress: ADDRESS_SCHEMA,
            tokenId: {
              type: "integer",
              minimum: 0,
              description: "Protocol token ID (0 = WETH, 1 = WBTC, ...)",
            },
            amount: { ...UINT_STRING_SCHEMA, description: "Amount in token smallest unit" },
            ccipFee: { ...UINT_STRING_SCHEMA, description: "Native-token CCIP fee in wei (required on non-ETH chains)" },
            chain: CHAIN_SCHEMA,
          },
        },
        response: {
          200: {
            type: "object",
            properties: {
              success: { type: "boolean" },
              message: { type: "string" },
              data: {
                type: "object",
                properties: {
                  approval: APPROVAL_RESULT_SCHEMA,
                  tx: TX_RESULT_SCHEMA,
                },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const { tokenAddress, tokenId, amount, ccipFee = "0", chain = env.ACTIVE_CHAIN } = request.body;

      const result = await depositLiquidity(
        tokenAddress,
        BigInt(tokenId),
        BigInt(amount),
        BigInt(ccipFee),
        chain as "eth" | "arb"
      );

      return reply.send({
        success: true,
        message: "Liquidity deposited. LP tokens minted to the signer wallet.",
        data: result,
      });
    }
  );

  /**
   * POST /liquidity/withdraw
   *
   * Withdraws previously deposited liquidity. Burns LP tokens proportionally.
   * The pool must have sufficient available (un-borrowed) liquidity.
   */
  fastify.post<{
    Body: {
      tokenId: number;
      amount: string;
      ccipFee?: string;
      chain?: string;
    };
  }>(
    "/withdraw",
    {
      schema: {
        tags: ["liquidity"],
        summary: "Withdraw liquidity — burn LP tokens",
        description:
          "Withdraws previously deposited tokens by burning LP tokens. " +
          "The pool must have sufficient un-borrowed liquidity.",
        body: {
          type: "object",
          required: ["tokenId", "amount"],
          additionalProperties: false,
          properties: {
            tokenId: {
              type: "integer",
              minimum: 0,
              description: "Protocol token ID",
            },
            amount: { ...UINT_STRING_SCHEMA, description: "Amount to withdraw in token smallest unit" },
            ccipFee: { ...UINT_STRING_SCHEMA, description: "Native-token CCIP fee in wei (required on non-ETH chains)" },
            chain: CHAIN_SCHEMA,
          },
        },
        response: {
          200: {
            type: "object",
            properties: {
              success: { type: "boolean" },
              message: { type: "string" },
              data: {
                type: "object",
                properties: { tx: TX_RESULT_SCHEMA },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const { tokenId, amount, ccipFee = "0", chain = env.ACTIVE_CHAIN } = request.body;

      const result = await withdrawLiquidity(
        BigInt(tokenId),
        BigInt(amount),
        BigInt(ccipFee),
        chain as "eth" | "arb"
      );

      return reply.send({
        success: true,
        message: "Liquidity withdrawn successfully.",
        data: result,
      });
    }
  );
}
