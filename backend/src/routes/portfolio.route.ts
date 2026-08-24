import { type FastifyInstance } from "fastify";
import { env } from "../config/env.js";
import { getUserPortfolio } from "../services/portfolio.service.js";

const ADDRESS_SCHEMA = {
  type: "string",
  pattern: "^0x[a-fA-F0-9]{40}$",
  description: "Ethereum address (0x-prefixed, 20 bytes)",
} as const;

export default async function portfolioRoutes(fastify: FastifyInstance) {
  /**
   * GET /portfolio/:userAddress
   *
   * Returns the complete on-chain state for a user in a single call:
   *   - LP token balance
   *   - Per-token liquidity deposits, collateral deposits, wallet balances
   *   - All active loans (with due dates, interest, collateral used)
   *   - Stablecoin wallet balance
   *
   * This is the primary endpoint for a dashboard — it replaces ~10 individual calls.
   */
  fastify.get<{
    Params: { userAddress: string };
    Querystring: { chain?: string };
  }>(
    "/:userAddress",
    {
      schema: {
        tags: ["portfolio"],
        summary: "Full user portfolio snapshot",
        description:
          "Returns all on-chain state for a user in one call: LP balance, " +
          "liquidity deposits, collateral, active loans, and wallet balances. " +
          "Use this as the primary data source for a dashboard page.",
        params: {
          type: "object",
          required: ["userAddress"],
          properties: { userAddress: ADDRESS_SCHEMA },
        },
        querystring: {
          type: "object",
          properties: {
            chain: { type: "string", enum: ["eth", "arb"], description: "Target chain" },
          },
        },
      },
    },
    async (request, reply) => {
      const { userAddress } = request.params;
      const chain = (request.query.chain ?? env.ACTIVE_CHAIN) as "eth" | "arb";

      const portfolio = await getUserPortfolio(userAddress, chain);
      return reply.send({ success: true, data: portfolio });
    }
  );
}
