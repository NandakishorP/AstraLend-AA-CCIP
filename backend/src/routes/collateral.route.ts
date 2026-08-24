import { type FastifyInstance } from "fastify";
import { env } from "../config/env.js";
import { depositCollateral, withdrawCollateral } from "../services/collateral.service.js";

const ADDRESS_SCHEMA = {
  type: "string",
  pattern: "^0x[a-fA-F0-9]{40}$",
  description: "Ethereum address (0x-prefixed, 20 bytes)",
} as const;

const UINT_STRING_SCHEMA = {
  type: "string",
  pattern: "^[0-9]+$",
  description: "Non-negative integer as a decimal string",
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

export default async function collateralRoutes(fastify: FastifyInstance) {
  /**
   * POST /collateral/deposit
   *
   * Deposits collateral into the protocol. The collateral is held in the Vault
   * and can be used to back loans (up to 75% LTV).
   *
   * On Ethereum: updates GlobalStateManager + mirrors to Arbitrum.
   * On Arbitrum: sends CCIP message to Ethereum — provide ccipFee.
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
        tags: ["collateral"],
        summary: "Deposit collateral",
        description:
          "Deposits ERC20 collateral into the protocol. The collateral backs loans at a 75% LTV ratio. " +
          "Vault approval is handled automatically. " +
          "Cross-chain operations require a ccipFee in native wei.",
        body: {
          type: "object",
          required: ["tokenAddress", "tokenId", "amount"],
          additionalProperties: false,
          properties: {
            tokenAddress: ADDRESS_SCHEMA,
            tokenId: {
              type: "integer",
              minimum: 0,
              description: "Protocol token ID of the collateral asset",
            },
            amount: { ...UINT_STRING_SCHEMA, description: "Collateral amount in token smallest unit" },
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

      const result = await depositCollateral(
        tokenAddress,
        BigInt(tokenId),
        BigInt(amount),
        BigInt(ccipFee),
        chain as "eth" | "arb"
      );

      return reply.send({
        success: true,
        message: "Collateral deposited successfully.",
        data: result,
      });
    }
  );

  /**
   * POST /collateral/withdraw
   *
   * Withdraws unlocked collateral back to the signer wallet.
   * Only collateral not currently backing an active loan can be withdrawn.
   * Attempting to withdraw locked collateral will be rejected by the contract.
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
        tags: ["collateral"],
        summary: "Withdraw unlocked collateral",
        description:
          "Returns unlocked collateral to the signer wallet. " +
          "Collateral that is backing an active loan cannot be withdrawn — repay the loan first.",
        body: {
          type: "object",
          required: ["tokenId", "amount"],
          additionalProperties: false,
          properties: {
            tokenId: {
              type: "integer",
              minimum: 0,
              description: "Protocol token ID of the collateral asset",
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

      const result = await withdrawCollateral(
        BigInt(tokenId),
        BigInt(amount),
        BigInt(ccipFee),
        chain as "eth" | "arb"
      );

      return reply.send({
        success: true,
        message: "Collateral withdrawn successfully.",
        data: result,
      });
    }
  );
}
