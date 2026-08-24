#!/usr/bin/env node
/**
 * Local CCIP relayer — stands in for Chainlink's Decentralised Oracle Network.
 *
 *   node tooling/relayer.mjs
 *
 * On a real network the DON watches each chain's Router for outbound messages
 * and executes them on the destination chain. Nothing does that between two
 * Anvil nodes, so a deposit made on the satellite chain would never reach the
 * hub and the protocol would look broken.
 *
 * This service closes that loop:
 *
 *   1. watch MockCCIPRouter.MockCCIPMessageSent on every chain
 *   2. resolve the destination chain from the CCIP selector
 *   3. impersonate the destination chain's router (anvil_impersonateAccount)
 *   4. call CrossChainMessageReceiver.ccipReceive as that router
 *
 * Step 4 mirrors what CCIPLocalSimulatorFork does inside the Foundry tests,
 * including encoding `sender` as a 32-byte abi.encode(address) — a 20-byte
 * packed value makes the receiver's `abi.decode(message.sender, (address))`
 * revert with no error data, which is exactly the bug that silently broke the
 * test suite.
 *
 * Delivery status is exposed at http://127.0.0.1:8547 so the web app can show
 * messages in flight.
 */

import fs from "node:fs";
import http from "node:http";
import { ethers } from "ethers";
import { CHAINS, CHAIN_LIST, chainBySelector, DEPLOYMENT_FILE } from "./config.mjs";

const STATUS_PORT = 8547;
const POLL_MS = 1_000;

const ROUTER_ABI = [
  "event MockCCIPMessageSent(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address indexed sender, address receiver, bytes data, uint256 feePaid)",
];

const RECEIVER_ABI = [
  "function ccipReceive((bytes32 messageId, uint64 sourceChainSelector, bytes sender, bytes data, (address token, uint256 amount)[] destTokenAmounts) message) external",
];

const receiverInterface = new ethers.Interface(RECEIVER_ABI);

/** Ring buffer of recent messages, served to the UI. */
const API_BASE = process.env.API_BASE_URL ?? "http://127.0.0.1:3001";

const messages = [];
const MAX_TRACKED = 60;

/**
 * Message ids already handled.
 *
 * Block-range scans can overlap — a reorg-free local chain still re-reports the
 * same log if the cursor is rewound by a snapshot revert — and delivering a
 * state update twice would corrupt balances. Mirrors the simulator's own
 * `s_processedMessages` guard.
 */
const processed = new Set();

function record(entry) {
  messages.unshift(entry);
  if (messages.length > MAX_TRACKED) messages.length = MAX_TRACKED;
  return entry;
}

function log(level, message) {
  const colour = { info: "\x1b[36m", ok: "\x1b[32m", warn: "\x1b[33m", err: "\x1b[31m" }[level];
  process.stdout.write(`${colour}relayer\x1b[0m ${message}\n`);
}

function loadDeployment() {
  if (!fs.existsSync(DEPLOYMENT_FILE)) {
    throw new Error(`${DEPLOYMENT_FILE} not found — run tooling/deploy-local.mjs first`);
  }
  return JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));
}

/**
 * Delivers one message to its destination chain.
 *
 * Anvil lets us send a transaction *as* any address, so the destination router
 * — the only caller the receiver's `onlyRouter` guard accepts — can be
 * impersonated directly instead of deploying a privileged shim.
 */
async function deliver({ deployment, source, event }) {
  if (processed.has(event.args.messageId)) return;
  processed.add(event.args.messageId);

  const destination = chainBySelector(event.args.destinationChainSelector);

  const entry = record({
    messageId: event.args.messageId,
    from: source.key,
    to: destination?.key ?? `selector:${event.args.destinationChainSelector}`,
    sender: event.args.sender,
    receiver: event.args.receiver,
    sourceTxHash: event.transactionHash,
    status: "pending",
    error: null,
    sentAt: new Date().toISOString(),
    deliveredAt: null,
    destinationTxHash: null,
  });

  if (!destination) {
    entry.status = "undeliverable";
    entry.error = `No local chain has selector ${event.args.destinationChainSelector}`;
    log("warn", `${entry.messageId.slice(0, 10)} ${entry.error}`);
    return;
  }

  const destAddrs = deployment.chains[destination.key];
  const provider = new ethers.JsonRpcProvider(destination.rpcUrl, destination.chainId, {
    staticNetwork: ethers.Network.from(destination.chainId),
  });

  try {
    // Give the impersonated router gas, then let it speak for itself.
    await provider.send("anvil_setBalance", [destAddrs.router, "0x56BC75E2D63100000"]);
    await provider.send("anvil_impersonateAccount", [destAddrs.router]);

    const data = receiverInterface.encodeFunctionData("ccipReceive", [
      {
        messageId: event.args.messageId,
        sourceChainSelector: source.selector,
        // 32-byte ABI-encoded address, matching production OffRamp behaviour.
        sender: ethers.AbiCoder.defaultAbiCoder().encode(["address"], [event.args.sender]),
        data: event.args.data,
        destTokenAmounts: [],
      },
    ]);

    const txHash = await provider.send("eth_sendTransaction", [
      {
        from: destAddrs.router,
        to: event.args.receiver,
        data,
        gas: "0x1c9c380", // 30M — the receive path fans out across many contracts
      },
    ]);

    const receipt = await provider.waitForTransaction(txHash);
    await provider.send("anvil_stopImpersonatingAccount", [destAddrs.router]);

    if (receipt?.status === 1) {
      entry.status = "delivered";
      entry.deliveredAt = new Date().toISOString();
      entry.destinationTxHash = txHash;
      log("ok", `${entry.messageId.slice(0, 10)} ${source.key} → ${destination.key} delivered`);
      await reportStatus(entry.messageId, {
        status: "delivered",
        txHash,
        blockNumber: receipt.blockNumber,
      });
    } else {
      entry.status = "reverted";
      entry.error = "Destination execution reverted";
      entry.destinationTxHash = txHash;
      log("err", `${entry.messageId.slice(0, 10)} ${source.key} → ${destination.key} reverted`);
      await reportStatus(entry.messageId, { status: "failed", error: entry.error });
    }
  } catch (error) {
    entry.status = "failed";
    entry.error = error.shortMessage ?? error.message;
    log("err", `${entry.messageId.slice(0, 10)} ${entry.error}`);
    await reportStatus(entry.messageId, { status: "failed", error: entry.error });
  }
}

/**
 * Tells the API how a delivery went.
 *
 * The backend indexes *sends* off the source chain, but only the relayer knows
 * whether the destination execution succeeded — so it reports the outcome here.
 * Failures to report are logged and swallowed: the relayer's job is delivering
 * messages, and it must not stall because the API happens to be down.
 */
async function reportStatus(messageId, body) {
  try {
    const response = await fetch(
      `${API_BASE}/analytics/cross-chain/${messageId}/status`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      }
    );
    if (!response.ok) {
      log("warn", `status report for ${messageId.slice(0, 10)} returned ${response.status}`);
    }
  } catch {
    log("warn", `could not report status for ${messageId.slice(0, 10)} — API unreachable`);
  }
}

/**
 * Polls a chain for new router events.
 *
 * Polling rather than a filter subscription: Anvil's HTTP transport drops
 * installed filters when a snapshot is reverted, which the demo's reset button
 * does, and a silently dead subscription is far worse than a 1s delay.
 */
function watchChain(deployment, chain, queue, backfill = true) {
  const provider = new ethers.JsonRpcProvider(chain.rpcUrl, chain.chainId, {
    staticNetwork: ethers.Network.from(chain.chainId),
  });
  const router = new ethers.Contract(deployment.chains[chain.key].router, ROUTER_ABI, provider);
  let cursor = null;

  async function tick() {
    try {
      const head = await provider.getBlockNumber();
      // Start from genesis, not the head. Anything sent while the relayer was
      // down would otherwise never be delivered, silently stalling the protocol
      // mid-demo. Already-delivered messages are filtered by `processed`, which
      // is seeded from the API on startup.
      if (cursor === null) cursor = backfill ? 0 : head;
      if (head < cursor) cursor = head; // chain was reset underneath us
      if (head >= cursor) {
        const events = await router.queryFilter("MockCCIPMessageSent", cursor, head);
        for (const event of events) queue.push({ source: chain, event });
        cursor = head + 1;
      }
    } catch (error) {
      log("warn", `${chain.key}: ${error.shortMessage ?? error.message}`);
    }
  }

  return tick;
}

function serveStatus() {
  http
    .createServer((req, res) => {
      res.setHeader("access-control-allow-origin", "*");
      res.setHeader("content-type", "application/json");
      if (req.url?.startsWith("/messages")) {
        res.end(JSON.stringify({ success: true, data: { messages } }));
        return;
      }
      res.end(
        JSON.stringify({
          success: true,
          data: {
            status: "running",
            chains: CHAIN_LIST.map((c) => c.key),
            pending: messages.filter((m) => m.status === "pending").length,
            delivered: messages.filter((m) => m.status === "delivered").length,
          },
        })
      );
    })
    .listen(STATUS_PORT, "127.0.0.1", () => {
      log("info", `status endpoint on http://127.0.0.1:${STATUS_PORT}`);
    });
}

/**
 * Loads already-delivered message ids from the API.
 *
 * Re-delivering a message would apply the same state change twice — a duplicate
 * collateral credit, a double repayment. The API persists delivery outcomes, so
 * it is the authority on what has already landed. If it cannot be reached the
 * relayer still starts, but scans from the head instead of genesis, trading
 * backfill for the guarantee that it never double-applies.
 */
async function seedProcessed() {
  try {
    const response = await fetch(`${API_BASE}/analytics/cross-chain?limit=200`);
    if (!response.ok) throw new Error(`status ${response.status}`);
    const body = await response.json();
    let seeded = 0;
    for (const message of body.data.messages ?? []) {
      if (message.status === "delivered") {
        processed.add(message.messageId);
        seeded++;
      }
    }
    log("ok", `seeded ${seeded} delivered message(s) from the API`);
    return true;
  } catch (error) {
    log("warn", `could not seed delivered messages (${error.message}); starting from head`);
    return false;
  }
}

async function main() {
  const deployment = loadDeployment();
  log("info", `hub ${CHAINS.eth.rpcUrl} · satellite ${CHAINS.arb.rpcUrl}`);

  // Must complete before the watchers start, so the first scan already knows
  // which messages not to re-deliver.
  const seeded = await seedProcessed();

  const queue = [];
  const tickers = CHAIN_LIST.map((chain) => watchChain(deployment, chain, queue, seeded));
  serveStatus();

  // Single consumer: messages must be delivered in the order they were sent,
  // because the protocol's own state transitions depend on that ordering.
  for (;;) {
    await Promise.all(tickers.map((tick) => tick()));
    while (queue.length) {
      const item = queue.shift();
      // A single undeliverable message must never take the relayer down —
      // during a demo that would look like the whole protocol had stalled.
      try {
        await deliver({ deployment, source: item.source, event: item.event });
      } catch (error) {
        log("err", `unhandled delivery error: ${error.message}`);
      }
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
}

main().catch((error) => {
  process.stderr.write(`\x1b[31mrelayer failed\x1b[0m ${error.message}\n`);
  process.exit(1);
});
