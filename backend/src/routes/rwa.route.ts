import { type FastifyInstance } from "fastify";
import { getAgency, getHolding, getLien, getNav, isConfigured } from "../services/rwa.service.js";
import { ValidationError } from "../errors.js";

const ADDRESS_PATTERN = "^0x[a-fA-F0-9]{40}$";

function assertAddress(value: string, field: string): string {
  if (!/^0x[a-fA-F0-9]{40}$/.test(value)) {
    throw new ValidationError(`${field} must be a 20-byte hex address.`);
  }
  return value;
}

/**
 * Real-world asset collateral.
 *
 * Every route here is hub-only. The instrument exists on one chain and never
 * moves, so there is no chain parameter to take — only messages about its
 * encumbrance cross to the satellite.
 */
export default async function rwaRoutes(fastify: FastifyInstance) {
  /**
   * GET /rwa/status
   *
   * Whether the RWA module is deployed and wired. The frontend uses this to
   * decide whether to show the section at all, so it must not throw when the
   * module is absent.
   */
  fastify.get(
    "/status",
    {
      schema: {
        tags: ["rwa"],
        summary: "Whether encumbered RWA collateral is available on this deployment",
      },
    },
    async (_req, reply) => reply.send({ success: true, data: { available: isConfigured() } })
  );

  /**
   * GET /rwa/agency
   *
   * Whether the issuer has appointed our lien registry as an agent on the
   * security. Nothing else in this module works without it — every pledge
   * reverts with NotAgent — so it is worth being able to see directly rather
   * than inferring it from a failed borrow.
   */
  fastify.get(
    "/agency",
    {
      schema: {
        tags: ["rwa"],
        summary: "Whether the protocol holds agent rights on the security",
        description:
          "The collateral is a third-party ERC-3643 issuance. Freezing a holder's " +
          "balance in place requires agent rights granted by the issuer — the " +
          "on-chain half of the tri-party agreement.",
      },
    },
    async (_req, reply) => reply.send({ success: true, data: await getAgency() })
  );

  /**
   * GET /rwa/nav
   *
   * Current value of the instrument, plus where it sits on its accretion curve.
   *
   * A Treasury bill has no price to report — it is bought at a discount and
   * redeems at par on a known date, so its value is a deterministic function of
   * time. It is computed on read, which is why `isStale` is always false.
   */
  fastify.get(
    "/nav",
    {
      schema: {
        tags: ["rwa"],
        summary: "Net asset value and accretion progress",
        description:
          "Returns NAV per token, the issue price and face value that bound it, " +
          "the maturity date and how far along the accretion curve the instrument " +
          "is. NAV is computed rather than attested, so it can never be stale.",
      },
    },
    async (_req, reply) => reply.send({ success: true, data: await getNav() })
  );

  /**
   * GET /rwa/holding/:address
   *
   * What the holder owns and how much of it is pledged.
   *
   * These are reported side by side deliberately. With crypto collateral the
   * vault balance tells you what is locked; with an encumbrance the borrower
   * still holds everything, and only the gap between balance and free tells
   * the story.
   */
  fastify.get<{ Params: { address: string } }>(
    "/holding/:address",
    {
      schema: {
        tags: ["rwa"],
        summary: "Balance, encumbrance and free balance for a holder",
        params: {
          type: "object",
          required: ["address"],
          properties: { address: { type: "string", pattern: ADDRESS_PATTERN } },
        },
      },
    },
    async (req, reply) => {
      const address = assertAddress(req.params.address, "address");
      return reply.send({ success: true, data: await getHolding(address) });
    }
  );

  /**
   * GET /rwa/lien/:address
   *
   * The borrower's entry in the register, or null if they have never pledged.
   */
  fastify.get<{ Params: { address: string } }>(
    "/lien/:address",
    {
      schema: {
        tags: ["rwa"],
        summary: "The recorded charge over a borrower's holding",
        description:
          "One running-account lien per holder and asset, matching how the pool " +
          "aggregates collateral. Returns null when no charge has ever been " +
          "perfected against this address.",
        params: {
          type: "object",
          required: ["address"],
          properties: { address: { type: "string", pattern: ADDRESS_PATTERN } },
        },
      },
    },
    async (req, reply) => {
      const address = assertAddress(req.params.address, "address");
      return reply.send({ success: true, data: await getLien(address) });
    }
  );
}
