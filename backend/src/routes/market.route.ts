import { type FastifyInstance } from "fastify";
import { env, type ChainKey } from "../config/env.js";
import { getMarketOverview } from "../services/market.service.js";
import { ValidationError } from "../errors.js";

const CHAIN_QS = {
  chain: {
    type: "string",
    enum: ["eth", "arb"],
    description: "Target chain. Defaults to ACTIVE_CHAIN.",
  },
} as const;

export default async function marketRoutes(fastify: FastifyInstance) {
  /**
   * GET /markets
   *
   * The single read behind the markets table, the landing page stats bar and the
   * borrow form's rate preview: per-token liquidity, collateral, borrows, prices,
   * utilization and rates, plus protocol-wide aggregates and risk parameters.
   */
  fastify.get<{ Querystring: { chain?: string } }>(
    "/",
    {
      schema: {
        tags: ["markets"],
        summary: "Full market overview — per-token stats plus protocol aggregates",
        description:
          "Returns every supported market with supplied liquidity, locked collateral, " +
          "outstanding borrows, USD prices, utilization and the borrow/supply rates " +
          "derived from the on-chain kinked interest rate model. Also returns TVL, " +
          "LP token value and the protocol's risk parameters (LTV, liquidation " +
          "threshold and penalty, loan duration). Cached for 10 seconds.",
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as ChainKey;
      const overview = await getMarketOverview(chain);
      return reply.send({ success: true, data: overview });
    }
  );

  /**
   * GET /markets/:tokenId
   * A single market — used by the deposit and borrow forms.
   */
  fastify.get<{ Params: { tokenId: string }; Querystring: { chain?: string } }>(
    "/:tokenId",
    {
      schema: {
        tags: ["markets"],
        summary: "Single market by token ID",
        params: {
          type: "object",
          required: ["tokenId"],
          properties: { tokenId: { type: "string", pattern: "^[0-9]+$" } },
        },
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as ChainKey;
      const overview = await getMarketOverview(chain);
      const market = overview.markets.find((m) => m.tokenId === Number(req.params.tokenId));

      if (!market) {
        throw new ValidationError(`No market for token ID ${req.params.tokenId}.`);
      }

      return reply.send({
        success: true,
        data: { ...market, parameters: overview.parameters, chainId: overview.chainId },
      });
    }
  );
}
