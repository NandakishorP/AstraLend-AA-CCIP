import { type FastifyInstance } from "fastify";
import { env, type ChainKey } from "../config/env.js";
import { drip, getFaucetStatus } from "../services/faucet.service.js";

export default async function faucetRoutes(fastify: FastifyInstance) {
  /**
   * GET /faucet/status
   * Which assets this deployment can actually mint. The UI hides the faucet
   * entirely when nothing is mintable.
   */
  fastify.get<{ Querystring: { chain?: string } }>(
    "/status",
    {
      schema: {
        tags: ["faucet"],
        summary: "Faucet availability and mintable assets",
        querystring: {
          type: "object",
          properties: { chain: { type: "string", enum: ["eth", "arb"] } },
        },
      },
    },
    async (req, reply) => {
      const chain = (req.query.chain ?? env.ACTIVE_CHAIN) as ChainKey;
      return reply.send({ success: true, data: await getFaucetStatus(chain) });
    }
  );

  /**
   * POST /faucet/drip
   * Mints test collateral or stablecoin to an address so a new user can walk the
   * full deposit → borrow → repay flow. Testnet only — on a production deployment
   * the underlying mint reverts and the error is returned unchanged.
   */
  fastify.post<{
    Body: { target: string; recipient: string; amount?: string; chain?: string };
  }>(
    "/drip",
    {
      schema: {
        tags: ["faucet"],
        summary: "Mint test tokens to an address",
        description:
          "Mints mock collateral (by token ID) or the protocol stablecoin (target " +
          '"stable") to the given recipient. `amount` is in whole tokens, not wei, ' +
          "and is capped per request.",
        body: {
          type: "object",
          required: ["target", "recipient"],
          additionalProperties: false,
          properties: {
            target: {
              type: "string",
              pattern: "^([0-9]+|stable|stablecoin)$",
              description: 'Protocol token ID, or "stable" for the stablecoin',
            },
            recipient: { type: "string", pattern: "^0x[a-fA-F0-9]{40}$" },
            amount: {
              type: "string",
              pattern: "^[0-9]+$",
              description: "Amount in whole tokens (default 10)",
            },
            chain: { type: "string", enum: ["eth", "arb"] },
          },
        },
      },
    },
    async (req, reply) => {
      const { target, recipient, amount, chain = env.ACTIVE_CHAIN } = req.body;
      const result = await drip(
        target,
        recipient,
        amount !== undefined ? BigInt(amount) : undefined,
        chain as ChainKey
      );
      return reply.send({
        success: true,
        message: `Minted test ${result.symbol} to ${recipient}.`,
        data: result,
      });
    }
  );
}
