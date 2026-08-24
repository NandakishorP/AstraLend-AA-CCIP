import { type FastifyInstance } from "fastify";
import {
  findKeeperCandidates,
  getDemoStatus,
  runKeeper,
  timeTravel,
} from "../services/demo.service.js";

const ADDRESS_SCHEMA = {
  type: "string",
  pattern: "^0x[a-fA-F0-9]{40}$",
} as const;

/**
 * Controls for the local two-chain demo environment.
 *
 * Not part of the protocol API: these drive an Anvil-only environment so the
 * full lifecycle — including a 180-day loan term and the liquidation cascade —
 * can be shown in minutes. Against a real network they report themselves
 * unavailable and do nothing.
 */
export default async function demoRoutes(fastify: FastifyInstance) {
  /**
   * GET /demo/status
   * Chain clocks, relayer health and cross-chain messages in flight.
   */
  fastify.get(
    "/status",
    {
      schema: {
        tags: ["demo"],
        summary: "Demo environment status: chain clocks, relayer, messages in flight",
        description:
          "Returns `available: false` outside the local two-chain environment. " +
          "`skewSeconds` shows how far each chain's clock has been advanced past real time.",
      },
    },
    async (_req, reply) => {
      return reply.send({ success: true, data: await getDemoStatus() });
    }
  );

  /**
   * POST /demo/time-travel
   * Advances both chains' clocks so time-gated behaviour can be demonstrated.
   */
  fastify.post<{ Body: { seconds?: number; days?: number } }>(
    "/time-travel",
    {
      schema: {
        tags: ["demo"],
        summary: "Advance both chain clocks",
        description:
          "Moves every chain forward by the same interval. Loans run for 180 days " +
          "and the liquidation cascade adds 30 days per penalty, so demonstrating " +
          "the full lifecycle needs roughly 300 days of chain time.",
        body: {
          type: "object",
          additionalProperties: false,
          properties: {
            seconds: { type: "integer", minimum: 1, description: "Seconds to advance" },
            days: { type: "integer", minimum: 1, description: "Days to advance (convenience)" },
          },
        },
      },
    },
    async (request, reply) => {
      const { seconds, days } = request.body ?? {};
      const advance = seconds ?? (days ?? 1) * 86_400;
      const result = await timeTravel(advance);
      return reply.send({
        success: true,
        message: `Advanced every chain by ${Math.round(advance / 86_400)} day(s).`,
        data: result,
      });
    }
  );

  /**
   * GET /demo/keeper/:userAddress
   * Which loans the keeper would act on, without acting.
   */
  fastify.get<{ Params: { userAddress: string } }>(
    "/keeper/:userAddress",
    {
      schema: {
        tags: ["demo"],
        summary: "Loans currently eligible for the liquidation keeper",
        params: {
          type: "object",
          required: ["userAddress"],
          properties: { userAddress: ADDRESS_SCHEMA },
        },
      },
    },
    async (request, reply) => {
      const candidates = await findKeeperCandidates(request.params.userAddress, "eth");
      return reply.send({
        success: true,
        data: {
          candidates,
          upkeepNeeded: candidates.length > 0,
        },
      });
    }
  );

  /**
   * POST /demo/keeper
   * Runs the keeper: escalates penalties, and liquidates once they run out.
   */
  fastify.post<{ Body: { userAddress: string } }>(
    "/keeper",
    {
      schema: {
        tags: ["demo"],
        summary: "Run the liquidation keeper",
        description:
          "Calls performUpkeep for every overdue loan. The contract escalates: the " +
          "first two runs add a 5% penalty and extend the due date by 30 days, and " +
          "the third liquidates the position.",
        body: {
          type: "object",
          required: ["userAddress"],
          additionalProperties: false,
          properties: { userAddress: ADDRESS_SCHEMA },
        },
      },
    },
    async (request, reply) => {
      const result = await runKeeper(request.body.userAddress);
      return reply.send({ success: true, message: result.message, data: result });
    }
  );
}
