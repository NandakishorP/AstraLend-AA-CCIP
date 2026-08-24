import { type FastifyInstance } from "fastify";
import { env } from "../config/env.js";
import { borrowLoan, repayLoan, getAmountToRepay } from "../services/loan.service.js";

const UINT_STRING_SCHEMA = {
  type: "string",
  pattern: "^[0-9]+$",
  description: "Non-negative integer as a decimal string",
} as const;

const CHAIN_SCHEMA = {
  type: "string",
  enum: ["eth", "arb"],
  description: "Target chain. Defaults to ACTIVE_CHAIN from server config.",
} as const;

const TX_RESULT_SCHEMA = {
  type: "object",
  properties: {
    txHash: { type: "string" },
    blockNumber: { type: "number" },
    gasUsed: { type: "string" },
  },
} as const;

const APPROVAL_RESULT_SCHEMA = {
  type: "object",
  properties: {
    wasNeeded: { type: "boolean" },
    txHash: { type: ["string", "null"] },
    blockNumber: { type: ["number", "null"] },
    gasUsed: { type: ["string", "null"] },
  },
} as const;

export default async function loanRoutes(fastify: FastifyInstance) {
  /**
   * POST /loan/borrow
   *
   * Borrows stablecoin against deposited collateral.
   *
   * Constraints enforced by the contract:
   *   - Max borrowable = collateralValueUSD × 75% LTV
   *   - Amount is in stablecoin smallest unit (6 decimals)
   *   - Loan is due in 180 days
   *   - Interest accrues via a kink-based borrower index
   *
   * On Ethereum: updates GSM + transfers stablecoin to caller.
   * On Arbitrum: sends CCIP message to Ethereum — provide ccipFee.
   */
  fastify.post<{
    Body: {
      collateralChainId: number;
      tokenId: number;
      amount: string;
      ccipFee?: string;
      chain?: string;
    };
  }>(
    "/borrow",
    {
      schema: {
        tags: ["loan"],
        summary: "Borrow stablecoin against collateral",
        description:
          "Takes a loan in stablecoin against previously deposited collateral. " +
          "Maximum borrow amount is 75% of collateral USD value. " +
          "Amount is in stablecoin smallest unit (6 decimals, USDT-like). " +
          "Loan is due in 180 days with dynamic interest accrual.",
        body: {
          type: "object",
          required: ["collateralChainId", "tokenId", "amount"],
          additionalProperties: false,
          properties: {
            collateralChainId: {
              type: "integer",
              minimum: 1,
              description: "Chain ID where collateral was deposited (e.g., 11155111 for ETH Sepolia)",
            },
            tokenId: {
              type: "integer",
              minimum: 0,
              description: "Protocol token ID of the collateral backing this loan",
            },
            amount: {
              ...UINT_STRING_SCHEMA,
              description: "Borrow amount in stablecoin smallest unit (6 decimals)",
            },
            ccipFee: {
              ...UINT_STRING_SCHEMA,
              description: "Native-token CCIP fee in wei (required on non-ETH chains)",
            },
            chain: CHAIN_SCHEMA,
          },
        },
        response: {
          200: {
            type: "object",
            properties: {
              success: { type: "boolean" },
              message: { type: "string" },
              data: {
                type: "object",
                properties: { tx: TX_RESULT_SCHEMA },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const { collateralChainId, tokenId, amount, ccipFee = "0", chain = env.ACTIVE_CHAIN } =
        request.body;

      const result = await borrowLoan(
        BigInt(collateralChainId),
        BigInt(tokenId),
        BigInt(amount),
        BigInt(ccipFee),
        chain as "eth" | "arb"
      );

      return reply.send({
        success: true,
        message: "Loan borrowed. Stablecoin transferred to the signer wallet.",
        data: result,
      });
    }
  );

  /**
   * POST /loan/repay
   *
   * Repays an outstanding loan (partially or in full).
   *
   * Repayment rules:
   *   - Interest is settled first, then principal is reduced
   *   - Overpayment is rejected by the contract
   *   - When fully repaid, collateral is automatically unlocked
   *
   * Use GET /loan/repay-amount to get the exact current total owed before
   * submitting a full repayment to avoid overpayment reverts.
   *
   * The stablecoin allowance for the Vault is handled automatically.
   */
  fastify.post<{
    Body: {
      loanChainId: number;
      tokenId: number;
      amount: string;
      loanId: number;
      ccipFee?: string;
      chain?: string;
    };
  }>(
    "/repay",
    {
      schema: {
        tags: ["loan"],
        summary: "Repay a loan (partially or fully)",
        description:
          "Repays an outstanding loan. Interest is settled before principal. " +
          "Overpayment is rejected — call GET /loan/repay-amount first to get the exact total. " +
          "Vault stablecoin approval is handled automatically. " +
          "Full repayment automatically releases the locked collateral.",
        body: {
          type: "object",
          required: ["loanChainId", "tokenId", "amount", "loanId"],
          additionalProperties: false,
          properties: {
            loanChainId: {
              type: "integer",
              minimum: 1,
              description: "Chain ID where the loan was taken",
            },
            tokenId: {
              type: "integer",
              minimum: 0,
              description: "Protocol token ID of the collateral",
            },
            amount: {
              ...UINT_STRING_SCHEMA,
              description: "Repayment amount in stablecoin smallest unit (6 decimals)",
            },
            loanId: {
              type: "integer",
              minimum: 0,
              description: "Unique loan identifier (visible in LoanBorrowed event or GET /protocol/user/loan)",
            },
            ccipFee: {
              ...UINT_STRING_SCHEMA,
              description: "Native-token CCIP fee in wei (required on non-ETH chains)",
            },
            chain: CHAIN_SCHEMA,
          },
        },
        response: {
          200: {
            type: "object",
            properties: {
              success: { type: "boolean" },
              message: { type: "string" },
              data: {
                type: "object",
                properties: {
                  approval: APPROVAL_RESULT_SCHEMA,
                  tx: TX_RESULT_SCHEMA,
                },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const { loanChainId, tokenId, amount, loanId, ccipFee = "0", chain = env.ACTIVE_CHAIN } =
        request.body;

      const result = await repayLoan(
        BigInt(loanChainId),
        BigInt(tokenId),
        BigInt(amount),
        BigInt(loanId),
        BigInt(ccipFee),
        chain as "eth" | "arb"
      );

      return reply.send({
        success: true,
        message: "Loan repayment submitted.",
        data: result,
      });
    }
  );

  /**
   * GET /loan/repay-amount
   *
   * Returns the current total amount owed (principal + accrued interest) for a
   * specific loan. Use this before calling POST /loan/repay to determine the
   * exact full repayment amount and avoid overpayment reverts.
   *
   * Uses staticCall internally (reads without paying gas).
   */
  fastify.get<{
    Querystring: {
      loanChainId: string;
      tokenId: string;
      loanId: string;
      userAddress?: string;
      chain?: string;
    };
  }>(
    "/repay-amount",
    {
      schema: {
        tags: ["loan"],
        summary: "Get total amount owed (principal + interest)",
        description:
          "Returns the current total repayment amount for a loan including accrued interest. " +
          "Call this before POST /loan/repay to get the exact amount for a full repayment. " +
          "The contract resolves the loan against msg.sender, so wallet-signed flows must " +
          "pass `userAddress` — otherwise the backend signer's loan is priced instead.",
        querystring: {
          type: "object",
          required: ["loanChainId", "tokenId", "loanId"],
          properties: {
            loanChainId: { type: "string", pattern: "^[0-9]+$", description: "Chain ID where loan was taken" },
            tokenId: { type: "string", pattern: "^[0-9]+$" },
            loanId: { type: "string", pattern: "^[0-9]+$" },
            userAddress: {
              type: "string",
              pattern: "^0x[a-fA-F0-9]{40}$",
              description: "Borrower address. Defaults to the backend signer.",
            },
            chain: CHAIN_SCHEMA,
          },
        },
        response: {
          200: {
            type: "object",
            properties: {
              success: { type: "boolean" },
              data: {
                type: "object",
                properties: {
                  amountToRepay: { type: "string", description: "Total owed in stablecoin smallest unit (6 dec)" },
                  loanChainId: { type: "string" },
                  tokenId: { type: "string" },
                  loanId: { type: "string" },
                },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const { loanChainId, tokenId, loanId, userAddress, chain = env.ACTIVE_CHAIN } = request.query;

      const amount = await getAmountToRepay(
        BigInt(loanChainId),
        BigInt(tokenId),
        BigInt(loanId),
        chain as "eth" | "arb",
        userAddress
      );

      return reply.send({
        success: true,
        data: {
          amountToRepay: amount.toString(),
          loanChainId,
          tokenId,
          loanId,
          userAddress: userAddress ?? null,
        },
      });
    }
  );
}
