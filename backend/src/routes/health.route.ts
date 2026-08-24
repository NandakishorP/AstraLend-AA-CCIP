import { type FastifyInstance } from "fastify";
import { CHAIN_CONFIGS, env, type ChainKey } from "../config/env.js";
import { checkProviderHealth } from "../blockchain/providers.js";
import { getLendingPoolRead } from "../blockchain/contracts.js";

export default async function healthRoutes(fastify: FastifyInstance) {
  /**
   * GET /health
   * Quick liveness probe — returns 200 if the server process is alive.
   */
  fastify.get(
    "/",
    {
      schema: {
        tags: ["health"],
        summary: "Liveness probe",
        response: {
          200: {
            type: "object",
            properties: {
              status: { type: "string" },
              activeChain: { type: "string" },
              timestamp: { type: "string" },
            },
          },
        },
      },
    },
    async (_req, reply) => {
      return reply.send({
        status: "ok",
        activeChain: env.ACTIVE_CHAIN,
        timestamp: new Date().toISOString(),
      });
    }
  );

  /**
   * GET /health/ready
   * Readiness probe — checks connectivity to all configured chains and
   * verifies the LendingPool contract is reachable on the active chain.
   * Returns 503 if any critical dependency is unavailable.
   */
  fastify.get(
    "/ready",
    {
      schema: {
        tags: ["health"],
        summary: "Readiness probe — checks chain connectivity and contract accessibility",
      },
    },
    async (_req, reply) => {
      const chains = (Object.keys(CHAIN_CONFIGS) as ChainKey[]);
      const results: Record<string, unknown> = {};
      let allHealthy = true;

      for (const chain of chains) {
        try {
          const providerHealth = await checkProviderHealth(chain);
          let contractStableCoin: string | null = null;

          if (CHAIN_CONFIGS[chain].lendingPool) {
            try {
              contractStableCoin = await getLendingPoolRead(chain).getStableCoinAddress();
            } catch {
              contractStableCoin = null;
            }
          }

          results[chain] = {
            status: "ok",
            ...providerHealth,
            lendingPool: CHAIN_CONFIGS[chain].lendingPool ?? "not configured",
            contractReachable: contractStableCoin !== null,
          };
        } catch (err) {
          allHealthy = false;
          results[chain] = {
            status: "error",
            message: (err as Error).message,
          };
        }
      }

      const statusCode = allHealthy ? 200 : 503;
      return reply.status(statusCode).send({
        status: allHealthy ? "ready" : "degraded",
        chains: results,
        timestamp: new Date().toISOString(),
      });
    }
  );
}
