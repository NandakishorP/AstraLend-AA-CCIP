import "dotenv/config";
import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import swagger from "@fastify/swagger";
import swaggerUI from "@fastify/swagger-ui";

import { env } from "./config/env.js";
import { AppError, ContractError } from "./errors.js";

import healthRoutes from "./routes/health.route.js";
import liquidityRoutes from "./routes/liquidity.route.js";
import collateralRoutes from "./routes/collateral.route.js";
import loanRoutes from "./routes/loan.route.js";
import protocolRoutes from "./routes/protocol.route.js";
import portfolioRoutes from "./routes/portfolio.route.js";
import feesRoutes from "./routes/fees.route.js";
import txBuilderRoutes from "./routes/tx-builder.route.js";
import marketRoutes from "./routes/market.route.js";
import activityRoutes from "./routes/activity.route.js";
import faucetRoutes from "./routes/faucet.route.js";
import demoRoutes from "./routes/demo.route.js";
import analyticsRoutes from "./routes/analytics.route.js";
import { startIndexer, stopIndexer } from "./indexer/indexer.js";
import { startSnapshotter, stopSnapshotter } from "./indexer/snapshotter.js";
import { getDb, closeDb } from "./db/index.js";

// ─── Build app ────────────────────────────────────────────────────────────────

export async function buildApp(): Promise<FastifyInstance> {
  const isPretty = env.LOG_LEVEL === "debug" || env.LOG_LEVEL === "trace";
  const fastify = Fastify({
    logger: {
      level: env.LOG_LEVEL,
      ...(isPretty ? { transport: { target: "pino-pretty", options: { colorize: true } } } : {}),
      serializers: {
        req(req) {
          return { method: req.method, url: req.url, requestId: req.id };
        },
      },
    },
    genReqId: () => crypto.randomUUID(), // Correlation ID on every request
    ajv: {
      customOptions: {
        strict: false, // Allow extra keywords like `description` in schemas
        coerceTypes: false,
        allErrors: false,
      },
    },
  });

  // ─── Security ───────────────────────────────────────────────────────────────

  await fastify.register(helmet, {
    contentSecurityPolicy: false, // Swagger UI needs inline scripts
  });

  await fastify.register(cors, {
    origin: true, // Tighten to specific origins before production
    methods: ["GET", "POST", "OPTIONS"],
  });

  await fastify.register(rateLimit, {
    max: 100,
    timeWindow: "1 minute",
    errorResponseBuilder: (_req, context) => ({
      success: false,
      error: "RATE_LIMIT_EXCEEDED",
      message: `Rate limit exceeded. Try again in ${Math.ceil(context.ttl / 1000)} seconds.`,
      retryAfterMs: context.ttl,
    }),
  });

  // ─── OpenAPI / Swagger ───────────────────────────────────────────────────────

  await fastify.register(swagger, {
    openapi: {
      openapi: "3.0.3",
      info: {
        title: "AstraLend API",
        description: [
          "Backend API for the AstraLend cross-chain DeFi lending protocol.",
          "",
          "## Protocol flow",
          "1. **Deposit liquidity** — add tokens to the pool, receive LP tokens",
          "2. **Deposit collateral** — lock tokens as loan collateral",
          "3. **Borrow** — take a stablecoin loan against collateral (75% LTV, 180-day term)",
          "4. **Repay** — settle interest first, then principal; collateral is released on full repayment",
          "5. **Withdraw** — reclaim liquidity or unlocked collateral",
          "",
          "## Cross-chain notes",
          "All write endpoints accept an optional `ccipFee` (native wei).",
          "On **Ethereum Sepolia** this is zero — state updates are direct.",
          "On **Arbitrum Sepolia** a CCIP fee must be provided — the operation is",
          "forwarded to Ethereum via Chainlink CCIP.",
          "",
          "## Amount encoding",
          "All amounts are passed and returned as **decimal strings** to avoid",
          "JavaScript's 53-bit integer precision limit with large wei values.",
        ].join("\n"),
        version: "1.0.0",
        contact: { name: "AstraLend" },
      },
      tags: [
        { name: "health",      description: "Liveness and readiness probes" },
        { name: "liquidity",   description: "Deposit and withdraw liquidity — mint/burn LP tokens" },
        { name: "collateral",  description: "Deposit and withdraw collateral" },
        { name: "loan",        description: "Borrow stablecoin and repay loans" },
        { name: "protocol",    description: "Read-only protocol state queries" },
        { name: "portfolio",   description: "Full user position snapshot — single call for dashboard" },
        { name: "fees",        description: "CCIP fee estimation before cross-chain operations" },
        { name: "tx-builder",  description: "Build unsigned transactions for MetaMask / wallet signing" },
        { name: "markets",     description: "Market stats — liquidity, utilization, rates, prices" },
        { name: "activity",    description: "Decoded on-chain activity feed per wallet" },
        { name: "faucet",      description: "Testnet faucet for mock collateral and stablecoin" },
        { name: "analytics",   description: "Indexed history: TVL series, market series, usage stats, cross-chain log" },
        { name: "demo",        description: "Local two-chain demo controls \u2014 chain clocks, relayer, keeper" },
      ],
      components: {
        securitySchemes: {},
      },
    },
  });

  await fastify.register(swaggerUI, {
    routePrefix: "/docs",
    uiConfig: {
      docExpansion: "list",
      deepLinking: true,
      tryItOutEnabled: true,
    },
  });

  // ─── BigInt serializer ───────────────────────────────────────────────────────
  // Fastify's default JSON.stringify blows up on BigInt. This hook converts
  // all BigInt values to decimal strings before serialization.

  fastify.addHook("preSerialization", async (_req, _reply, payload) => {
    return JSON.parse(
      JSON.stringify(payload, (_key, value) =>
        typeof value === "bigint" ? value.toString() : value
      )
    );
  });

  // ─── Request logging ─────────────────────────────────────────────────────────

  fastify.addHook("onRequest", async (request) => {
    request.log.info({ requestId: request.id }, "incoming request");
  });

  fastify.addHook("onResponse", async (request, reply) => {
    request.log.info(
      { requestId: request.id, statusCode: reply.statusCode, responseTime: reply.elapsedTime.toFixed(2) + "ms" },
      "request completed"
    );
  });

  // ─── Global error handler ─────────────────────────────────────────────────────
  // Converts all error types into a consistent JSON response shape.

  fastify.setErrorHandler(async (error, request, reply) => {
      const requestId = request.id;
      // Cast to a duck-typed shape that covers both FastifyError and our AppError
      const fastifyErr = error as Error & { statusCode?: number; validation?: unknown[] };

      // Fastify validation errors (JSON Schema failures)
      if (fastifyErr.validation) {
        request.log.warn({ requestId, validation: fastifyErr.validation }, "request validation failed");
        return reply.status(400).send({
          success: false,
          error: "VALIDATION_ERROR",
          message: "Request validation failed.",
          details: fastifyErr.validation,
          requestId,
        });
      }

      // Fastify rate-limit errors (already formatted by errorResponseBuilder above)
      if (fastifyErr.statusCode === 429) {
        return reply.status(429).send(error);
      }

      // Our typed application errors
      if (error instanceof AppError) {
        const level = error.statusCode >= 500 ? "error" : "warn";
        request.log[level](
          { requestId, code: error.code, statusCode: error.statusCode, details: error.details },
          error.message
        );

        const body: Record<string, unknown> = {
          success: false,
          error: error.code,
          message: error.message,
          requestId,
        };

        // Include decoded args for contract errors so callers can react programmatically
        if (error instanceof ContractError) {
          body["contractError"] = error.contractErrorName;
          if (error.args && Object.keys(error.args).length > 0) {
            body["contractErrorArgs"] = error.args;
          }
        }

        if (error.details !== undefined && error.statusCode < 500) {
          body["details"] = error.details;
        }

        return reply.status(error.statusCode).send(body);
      }

      // Unknown / unhandled errors
      request.log.error({ requestId, err: error }, "unhandled error");
      return reply.status(500).send({
        success: false,
        error: "INTERNAL_SERVER_ERROR",
        message: "An unexpected error occurred.",
        requestId,
      });
    }
  );

  // ─── 404 handler ─────────────────────────────────────────────────────────────

  fastify.setNotFoundHandler(async (request, reply) => {
    return reply.status(404).send({
      success: false,
      error: "NOT_FOUND",
      message: `Route ${request.method} ${request.url} not found.`,
      requestId: request.id,
    });
  });

  // ─── Routes ───────────────────────────────────────────────────────────────────

  await fastify.register(healthRoutes,     { prefix: "/health" });
  await fastify.register(liquidityRoutes,  { prefix: "/liquidity" });
  await fastify.register(collateralRoutes, { prefix: "/collateral" });
  await fastify.register(loanRoutes,       { prefix: "/loan" });
  await fastify.register(protocolRoutes,   { prefix: "/protocol" });
  await fastify.register(portfolioRoutes,  { prefix: "/portfolio" });
  await fastify.register(feesRoutes,       { prefix: "/fees" });
  await fastify.register(txBuilderRoutes,  { prefix: "/tx" });
  await fastify.register(marketRoutes,     { prefix: "/markets" });
  await fastify.register(activityRoutes,   { prefix: "/activity" });
  await fastify.register(faucetRoutes,     { prefix: "/faucet" });
  await fastify.register(demoRoutes,       { prefix: "/demo" });
  await fastify.register(analyticsRoutes,  { prefix: "/analytics" });

  return fastify;
}

// ─── Entry point ──────────────────────────────────────────────────────────────

async function start() {
  const app = await buildApp();
  try {
    // Open (and migrate) the database before serving, so a schema problem fails
    // at boot rather than on the first request that needs it.
    getDb();

    await app.listen({ port: env.PORT, host: env.HOST });
    app.log.info(`Swagger docs available at http://${env.HOST}:${env.PORT}/docs`);

    // The indexer and snapshotter run alongside the API in-process. They are
    // started after `listen` so a slow backfill never delays readiness.
    startIndexer({
      info: (msg) => app.log.info(msg),
      warn: (msg) => app.log.warn(msg),
      error: (msg) => app.log.error(msg),
    });
    startSnapshotter({
      info: (msg) => app.log.info(msg),
      warn: (msg) => app.log.warn(msg),
    });

    // Stop the background loops before the process exits, so an in-flight write
    // cannot land against a closed database handle.
    const shutdown = async (signal: string) => {
      app.log.info(`${signal} received, shutting down`);
      stopIndexer();
      stopSnapshotter();
      await app.close();
      closeDb();
      process.exit(0);
    };
    process.on("SIGINT", () => void shutdown("SIGINT"));
    process.on("SIGTERM", () => void shutdown("SIGTERM"));
  } catch (err) {
    app.log.error(err, "Failed to start server");
    process.exit(1);
  }
}

start();
