import { type FastifyInstance } from "fastify";
import { env } from "../config/env.js";
import { estimateCcipFee, type FeeOperation } from "../services/fees.service.js";

const OPERATIONS: FeeOperation[] = [
  "depositLiquidity",
  "withdrawLiquidity",
  "depositCollateral",
  "withdrawCollateral",
  "borrowLoan",
  "repayLoan",
];

export default async function feesRoutes(fastify: FastifyInstance) {
  /**
   * GET /fees/estimate
   *
   * Estimates the CCIP native-token fee required before submitting a cross-chain
   * operation. Returns 0 on Ethereum (no CCIP needed). On Arbitrum the fee must
   * be included as msg.value in the contract call.
   *
   * The frontend should call this before showing the transaction confirmation
   * modal so the user sees the expected fee upfront.
   */
  fastify.get<{
    Querystring: {
      operation: string;
      tokenId: string;
      amount: string;
      chain?: string;
    };
  }>(
    "/estimate",
    {
      schema: {
        tags: ["fees"],
        summary: "Estimate CCIP fee for an operation",
        description:
          "Returns the native-token CCIP fee (in wei) needed for a cross-chain operation. " +
          "On Ethereum Sepolia this is always 0. On Arbitrum Sepolia you must include " +
          "the recommended fee as msg.value (the `ccipFee` field in write endpoints). " +
          "Call this before showing the transaction confirmation modal.",
        querystring: {
          type: "object",
          required: ["operation", "tokenId", "amount"],
          properties: {
            operation: {
              type: "string",
              enum: OPERATIONS,
              description: "The protocol operation to estimate fees for",
            },
            tokenId: { type: "string", pattern: "^[0-9]+$", description: "Protocol token ID" },
            amount: { type: "string", pattern: "^[0-9]+$", description: "Amount in token smallest unit" },
            chain: { type: "string", enum: ["eth", "arb"], description: "Chain the user submits from" },
          },
        },
      },
    },
    async (request, reply) => {
      const { operation, tokenId, amount, chain = env.ACTIVE_CHAIN } = request.query;

      const estimate = await estimateCcipFee(
        operation as FeeOperation,
        BigInt(tokenId),
        BigInt(amount),
        chain as "eth" | "arb"
      );

      return reply.send({ success: true, data: estimate });
    }
  );
}
