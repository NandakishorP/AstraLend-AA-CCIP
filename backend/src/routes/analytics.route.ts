import { type FastifyInstance } from "fastify";
import { env, type ChainKey } from "../config/env.js";
import {
  getCrossChainFeed,
  getMarketHistory,
  getProtocolHistory,
  getProtocolStats,
  type Range,
} from "../services/analytics.service.js";
import { getIndexerStatus } from "../indexer/indexer.js";
import { ccipRepo } from "../db/repositories.js";

const RANGES: Range[] = ["1h", "6h", "24h", "7d", "30d", "all"];

const CHAIN_QS = {
  chain: { type: "string", enum: ["eth", "arb"], description: "Target chain." },
} as const;

const RANGE_QS = {
  range: {
    type: "string",
    enum: RANGES,
    default: "24h",
    description: "Time window for the series.",
  },
} as const;

export default async function analyticsRoutes(fastify: FastifyInstance) {
  /**
   * GET /analytics/tvl
   * TVL, borrows and collateral over time — the dashboard's headline chart.
   * Only answerable from indexed snapshots; the chain has no history of it.
   */
  fastify.get<{ Querystring: { chain?: string; range?: Range } }>(
    "/tvl",
    {
      schema: {
        tags: ["analytics"],
        summary: "Protocol TVL / borrows / collateral time series",
        description:
          "Returns a time series built from indexer snapshots, plus the percentage " +
          "change across the window. Chain state can only report the present, so " +
          "this endpoint is empty until the indexer has been running.",
        querystring: { type: "object", properties: { ...CHAIN_QS, ...RANGE_QS } },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as ChainKey;
      const range = (req.query.range ?? "24h") as Range;
      return reply.send({ success: true, data: getProtocolHistory(chain, range) });
    }
  );

  /**
   * GET /analytics/market/:tokenId
   * Utilization, rates, price and liquidity for a single market over time.
   */
  fastify.get<{ Params: { tokenId: string }; Querystring: { chain?: string; range?: Range } }>(
    "/market/:tokenId",
    {
      schema: {
        tags: ["analytics"],
        summary: "Per-market history (utilization, APR, price, liquidity)",
        params: {
          type: "object",
          required: ["tokenId"],
          properties: { tokenId: { type: "string", pattern: "^[0-9]+$" } },
        },
        querystring: { type: "object", properties: { ...CHAIN_QS, ...RANGE_QS } },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as ChainKey;
      const range = (req.query.range ?? "24h") as Range;
      return reply.send({
        success: true,
        data: getMarketHistory(chain, Number(req.params.tokenId), range),
      });
    }
  );

  /**
   * GET /analytics/stats
   * Unique participants, event totals by kind, and cross-chain delivery stats.
   */
  fastify.get<{ Querystring: { chain?: string } }>(
    "/stats",
    {
      schema: {
        tags: ["analytics"],
        summary: "Protocol usage statistics",
        description:
          "Aggregate counts derived from the full indexed event history — unique " +
          "addresses, events by kind, and cross-chain delivery success and latency.",
        querystring: { type: "object", properties: CHAIN_QS },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as ChainKey;
      return reply.send({ success: true, data: getProtocolStats(chain) });
    }
  );

  /**
   * GET /analytics/cross-chain
   * Every CCIP message the indexer has seen, with delivery status and latency.
   */
  fastify.get<{ Querystring: { limit?: string; userAddress?: string } }>(
    "/cross-chain",
    {
      schema: {
        tags: ["analytics"],
        summary: "Cross-chain message log with delivery status",
        description:
          "Messages are persisted when sent and updated when delivered, so a " +
          "message that was in flight across a restart is still shown as pending " +
          "rather than being lost.",
        querystring: {
          type: "object",
          properties: {
            // Query values arrive as strings and the app disables ajv type
            // coercion on purpose, so numeric params are validated as strings
            // and converted in the handler.
            limit: { type: "string", pattern: "^[0-9]+$", default: "25" },
            userAddress: { type: "string", pattern: "^0x[a-fA-F0-9]{40}$" },
          },
        },
      },
    },
    async (req, reply) => {
      const limit = Math.min(200, Math.max(1, Number(req.query.limit ?? 25)));
      const feed = getCrossChainFeed(limit, req.query.userAddress);
      return reply.send({ success: true, data: feed });
    }
  );

  /**
   * GET /analytics/indexer
   * Indexer health per chain — how far behind the head each one is.
   */
  fastify.get(
    "/indexer",
    {
      schema: {
        tags: ["analytics"],
        summary: "Indexer status per chain",
        description:
          "Reports the cursor position against the chain head, events indexed, " +
          "reorgs handled and the last error. `blocksBehind` at 0 means the " +
          "database is current.",
      },
    },
    async (_req, reply) => {
      return reply.send({ success: true, data: { chains: await getIndexerStatus() } });
    }
  );

  /**
   * POST /analytics/cross-chain/:messageId/status
   *
   * Closes the loop on a cross-chain message. The relayer calls this once it has
   * executed a message on the destination chain, which is the only party that
   * knows the outcome — the send event says a message left, not that it landed.
   *
   * The indexer records sends; this records deliveries. Together they give the
   * pending/delivered/failed view the UI shows.
   */
  fastify.post<{
    Params: { messageId: string };
    Body: { status: "delivered" | "failed"; txHash?: string; blockNumber?: number; error?: string };
  }>(
    "/cross-chain/:messageId/status",
    {
      schema: {
        tags: ["analytics"],
        summary: "Record the delivery outcome of a cross-chain message",
        params: {
          type: "object",
          required: ["messageId"],
          properties: { messageId: { type: "string", pattern: "^0x[a-fA-F0-9]{64}$" } },
        },
        body: {
          type: "object",
          required: ["status"],
          additionalProperties: false,
          properties: {
            status: { type: "string", enum: ["delivered", "failed"] },
            txHash: { type: "string" },
            blockNumber: { type: "integer", minimum: 0 },
            error: { type: "string" },
          },
        },
      },
    },
    async (req, reply) => {
      const { messageId } = req.params;
      if (req.body.status === "delivered") {
        ccipRepo.markDelivered(messageId, req.body.txHash ?? "", req.body.blockNumber ?? 0);
      } else {
        ccipRepo.markFailed(messageId, req.body.error ?? "delivery failed");
      }
      return reply.send({ success: true, data: { messageId, status: req.body.status } });
    }
  );
}
