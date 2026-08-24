import { type FastifyInstance } from "fastify";
import { env, type ChainKey } from "../config/env.js";
import { getUserActivity } from "../services/activity.service.js";

const ADDRESS_SCHEMA = {
  type: "string",
  pattern: "^0x[a-fA-F0-9]{40}$",
  description: "Ethereum address (0x-prefixed, 20 bytes)",
} as const;

export default async function activityRoutes(fastify: FastifyInstance) {
  /**
   * GET /activity/:userAddress
   *
   * Transaction history for a wallet, decoded from protocol event logs.
   * No indexer required — every protocol event indexes the acting address as its
   * first topic, so the feed comes from a filtered `eth_getLogs` scan.
   */
  // Query parameters arrive as strings and the server runs ajv with type
  // coercion disabled, so numeric options are declared as digit strings and
  // parsed in the handler — matching the convention used by the other routes.
  fastify.get<{
    Params: { userAddress: string };
    Querystring: { chain?: string; limit?: string; fromBlock?: string };
  }>(
    "/:userAddress",
    {
      schema: {
        tags: ["activity"],
        summary: "Decoded protocol activity feed for a wallet",
        description:
          "Returns the user's supply, withdraw, collateral, borrow, repay and " +
          "cross-chain events, newest first, with block timestamps and decoded " +
          "amounts. Pass `fromBlock` (the value returned as `fromBlock`) to page " +
          "further back in history.",
        params: {
          type: "object",
          required: ["userAddress"],
          properties: { userAddress: ADDRESS_SCHEMA },
        },
        querystring: {
          type: "object",
          properties: {
            chain: { type: "string", enum: ["eth", "arb"] },
            limit: {
              type: "string",
              pattern: "^[0-9]{1,3}$",
              description: "Maximum events to return, 1–200 (default 50)",
            },
            fromBlock: {
              type: "string",
              pattern: "^[0-9]+$",
              description: "Start block for the scan",
            },
          },
        },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as ChainKey;
      const limit = Math.min(200, Math.max(1, Number(req.query.limit ?? 50)));
      const fromBlock = req.query.fromBlock !== undefined ? Number(req.query.fromBlock) : undefined;

      const feed = await getUserActivity(req.params.userAddress, chain, limit, fromBlock);
      return reply.send({ success: true, data: feed });
    }
  );
}
