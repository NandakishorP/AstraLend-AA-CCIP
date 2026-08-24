import { type FastifyInstance } from "fastify";
import { env } from "../config/env.js";
import {
  buildDepositLiquidity,
  buildWithdrawLiquidity,
  buildDepositCollateral,
  buildWithdrawCollateral,
  buildBorrowLoan,
  buildRepayLoan,
} from "../services/tx-builder.service.js";

/**
 * /tx/* — Unsigned transaction builder for MetaMask / wallet integration.
 *
 * Each endpoint returns an ordered array of `transactions`. The frontend
 * should submit them sequentially via:
 *
 *   for (const tx of transactions) {
 *     await window.ethereum.request({ method: "eth_sendTransaction", params: [tx] });
 *   }
 *
 * This removes the need for the backend to hold private keys in production.
 * All state-changing routes (/liquidity, /collateral, /loan) are still available
 * for server-side signing during development / testing.
 */

const ADDRESS_SCHEMA = {
  type: "string",
  pattern: "^0x[a-fA-F0-9]{40}$",
  description: "Ethereum address (0x-prefixed)",
} as const;

const UINT_STRING = {
  type: "string",
  pattern: "^[0-9]+$",
  description: "Non-negative integer as decimal string",
} as const;

const CHAIN_SCHEMA = {
  type: "string",
  enum: ["eth", "arb"],
  description: "Chain the user submits from",
} as const;

const UNSIGNED_TX_SCHEMA = {
  type: "object",
  properties: {
    to: { type: "string" },
    data: { type: "string" },
    value: { type: "string" },
    gasLimit: { type: "string" },
    chainId: { type: "number" },
    type: { type: "string" },
    description: { type: "string" },
  },
} as const;

const BUILD_RESULT_SCHEMA = {
  type: "object",
  properties: {
    success: { type: "boolean" },
    data: {
      type: "object",
      properties: {
        transactions: { type: "array", items: UNSIGNED_TX_SCHEMA },
        chainId: { type: "number" },
        summary: { type: "string" },
      },
    },
  },
} as const;

export default async function txBuilderRoutes(fastify: FastifyInstance) {

  // ─── Liquidity ──────────────────────────────────────────────────────────────

  fastify.post<{ Body: { userAddress: string; tokenId: number; amount: string; ccipFee?: string; chain?: string } }>(
    "/liquidity/deposit",
    {
      schema: {
        tags: ["tx-builder"],
        summary: "Build unsigned depositLiquidity transaction(s) for MetaMask",
        body: {
          type: "object",
          required: ["userAddress", "tokenId", "amount"],
          additionalProperties: false,
          properties: {
            userAddress: ADDRESS_SCHEMA,
            tokenId: { type: "integer", minimum: 0 },
            amount: UINT_STRING,
            ccipFee: UINT_STRING,
            chain: CHAIN_SCHEMA,
          },
        },
        response: { 200: BUILD_RESULT_SCHEMA },
      },
    },
    async (req, reply) => {
      const { userAddress, tokenId, amount, ccipFee = "0", chain = env.ACTIVE_CHAIN } = req.body;
      const result = await buildDepositLiquidity(
        userAddress, BigInt(tokenId), BigInt(amount), BigInt(ccipFee), chain as "eth" | "arb"
      );
      return reply.send({ success: true, data: result });
    }
  );

  fastify.post<{ Body: { userAddress: string; tokenId: number; amount: string; ccipFee?: string; chain?: string } }>(
    "/liquidity/withdraw",
    {
      schema: {
        tags: ["tx-builder"],
        summary: "Build unsigned withdrawDeposit transaction for MetaMask",
        body: {
          type: "object",
          required: ["userAddress", "tokenId", "amount"],
          additionalProperties: false,
          properties: {
            userAddress: ADDRESS_SCHEMA,
            tokenId: { type: "integer", minimum: 0 },
            amount: UINT_STRING,
            ccipFee: UINT_STRING,
            chain: CHAIN_SCHEMA,
          },
        },
        response: { 200: BUILD_RESULT_SCHEMA },
      },
    },
    async (req, reply) => {
      const { userAddress, tokenId, amount, ccipFee = "0", chain = env.ACTIVE_CHAIN } = req.body;
      const result = await buildWithdrawLiquidity(
        userAddress, BigInt(tokenId), BigInt(amount), BigInt(ccipFee), chain as "eth" | "arb"
      );
      return reply.send({ success: true, data: result });
    }
  );

  // ─── Collateral ─────────────────────────────────────────────────────────────

  fastify.post<{ Body: { userAddress: string; tokenId: number; amount: string; ccipFee?: string; chain?: string } }>(
    "/collateral/deposit",
    {
      schema: {
        tags: ["tx-builder"],
        summary: "Build unsigned depositCollateral transaction(s) for MetaMask",
        body: {
          type: "object",
          required: ["userAddress", "tokenId", "amount"],
          additionalProperties: false,
          properties: {
            userAddress: ADDRESS_SCHEMA,
            tokenId: { type: "integer", minimum: 0 },
            amount: UINT_STRING,
            ccipFee: UINT_STRING,
            chain: CHAIN_SCHEMA,
          },
        },
        response: { 200: BUILD_RESULT_SCHEMA },
      },
    },
    async (req, reply) => {
      const { userAddress, tokenId, amount, ccipFee = "0", chain = env.ACTIVE_CHAIN } = req.body;
      const result = await buildDepositCollateral(
        userAddress, BigInt(tokenId), BigInt(amount), BigInt(ccipFee), chain as "eth" | "arb"
      );
      return reply.send({ success: true, data: result });
    }
  );

  fastify.post<{ Body: { userAddress: string; tokenId: number; amount: string; ccipFee?: string; chain?: string } }>(
    "/collateral/withdraw",
    {
      schema: {
        tags: ["tx-builder"],
        summary: "Build unsigned withdrawCollateral transaction for MetaMask",
        body: {
          type: "object",
          required: ["userAddress", "tokenId", "amount"],
          additionalProperties: false,
          properties: {
            userAddress: ADDRESS_SCHEMA,
            tokenId: { type: "integer", minimum: 0 },
            amount: UINT_STRING,
            ccipFee: UINT_STRING,
            chain: CHAIN_SCHEMA,
          },
        },
        response: { 200: BUILD_RESULT_SCHEMA },
      },
    },
    async (req, reply) => {
      const { userAddress, tokenId, amount, ccipFee = "0", chain = env.ACTIVE_CHAIN } = req.body;
      const result = await buildWithdrawCollateral(
        userAddress, BigInt(tokenId), BigInt(amount), BigInt(ccipFee), chain as "eth" | "arb"
      );
      return reply.send({ success: true, data: result });
    }
  );

  // ─── Loan ───────────────────────────────────────────────────────────────────

  fastify.post<{
    Body: {
      userAddress: string;
      collateralChainId: number;
      tokenId: number;
      amount: string;
      ccipFee?: string;
      chain?: string;
    };
  }>(
    "/loan/borrow",
    {
      schema: {
        tags: ["tx-builder"],
        summary: "Build unsigned borrowLoan transaction for MetaMask",
        body: {
          type: "object",
          required: ["userAddress", "collateralChainId", "tokenId", "amount"],
          additionalProperties: false,
          properties: {
            userAddress: ADDRESS_SCHEMA,
            collateralChainId: { type: "integer", minimum: 1 },
            tokenId: { type: "integer", minimum: 0 },
            amount: UINT_STRING,
            ccipFee: UINT_STRING,
            chain: CHAIN_SCHEMA,
          },
        },
        response: { 200: BUILD_RESULT_SCHEMA },
      },
    },
    async (req, reply) => {
      const { userAddress, collateralChainId, tokenId, amount, ccipFee = "0", chain = env.ACTIVE_CHAIN } = req.body;
      const result = await buildBorrowLoan(
        userAddress, BigInt(collateralChainId), BigInt(tokenId), BigInt(amount), BigInt(ccipFee),
        chain as "eth" | "arb"
      );
      return reply.send({ success: true, data: result });
    }
  );

  fastify.post<{
    Body: {
      userAddress: string;
      loanChainId: number;
      tokenId: number;
      amount: string;
      loanId: number;
      ccipFee?: string;
      chain?: string;
    };
  }>(
    "/loan/repay",
    {
      schema: {
        tags: ["tx-builder"],
        summary: "Build unsigned repayLoan transaction(s) for MetaMask",
        description:
          "Returns [approve stablecoin for Vault (if needed), repayLoan]. " +
          "Submit both in order. Use GET /loan/repay-amount first to get the exact amount.",
        body: {
          type: "object",
          required: ["userAddress", "loanChainId", "tokenId", "amount", "loanId"],
          additionalProperties: false,
          properties: {
            userAddress: ADDRESS_SCHEMA,
            loanChainId: { type: "integer", minimum: 1 },
            tokenId: { type: "integer", minimum: 0 },
            amount: UINT_STRING,
            loanId: { type: "integer", minimum: 0 },
            ccipFee: UINT_STRING,
            chain: CHAIN_SCHEMA,
          },
        },
        response: { 200: BUILD_RESULT_SCHEMA },
      },
    },
    async (req, reply) => {
      const { userAddress, loanChainId, tokenId, amount, loanId, ccipFee = "0", chain = env.ACTIVE_CHAIN } = req.body;
      const result = await buildRepayLoan(
        userAddress, BigInt(loanChainId), BigInt(tokenId), BigInt(amount), BigInt(loanId),
        BigInt(ccipFee), chain as "eth" | "arb"
      );
      return reply.send({ success: true, data: result });
    }
  );
}
