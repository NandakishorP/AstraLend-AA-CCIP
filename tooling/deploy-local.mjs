#!/usr/bin/env node
/**
 * Brings up the full two-chain demo environment.
 *
 *   node tooling/deploy-local.mjs
 *
 * Assumes two Anvil nodes are already running (see tooling/start-demo.sh):
 *   hub       Ethereum Sepolia chain id, port 8545
 *   satellite Arbitrum Sepolia chain id, port 8546
 *
 * Deploys the protocol to each, then cross-registers them — each chain has to
 * learn the *other* chain's receiver address and allow-list the other chain's
 * sender, which is impossible during a single-chain deploy because the
 * counterpart does not exist yet.
 *
 * Writes tooling/deployment.local.json, which the relayer and the backend read.
 */

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import { ethers } from "ethers";
import { CHAINS, CHAIN_LIST, DEPLOYER, DEPLOYMENT_FILE, REPO_ROOT } from "./config.mjs";

const REGISTRY_ABI = [
  "function setDestinationChainSelector(uint256 chainId, uint64 selector) external",
  "function setCrossChainRegistryAddress(uint64 selector, string name, address addr) external",
  "function setAddress(uint256 chainId, string name, address addr) external",
  "function getCrossChainAddress(uint64 selector, string name) external view returns (address)",
];

const POOL_ABI = [
  "function setallowListedSenders(address sender) external",
  "function setAllowedCallersFoCrossChainMessageSender(address sender, bool allowed) external",
  "function getUsdValue(uint64 tokenId, uint256 amount) external view returns (uint256)",
];

function log(step, message) {
  process.stdout.write(`\x1b[35m${step}\x1b[0m ${message}\n`);
}

/** Runs a forge deploy script against one node and parses its DEPLOY output. */
function deployChain(chain) {
  log("deploy", `${chain.name} (${chain.role}) → ${chain.rpcUrl}`);

  const output = execFileSync(
    "forge",
    [
      "script",
      chain.script,
      "--rpc-url",
      chain.rpcUrl,
      "--broadcast",
      "--private-key",
      DEPLOYER.privateKey,
      "--sender",
      DEPLOYER.address,
      "--skip-simulation",
    ],
    { cwd: REPO_ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }
  );

  if (!output.includes("ONCHAIN EXECUTION COMPLETE & SUCCESSFUL")) {
    throw new Error(`Deploy to ${chain.name} did not complete:\n${output.slice(-2000)}`);
  }

  // The scripts print one "DEPLOY key=0x…" line per address.
  const addresses = {};
  for (const match of output.matchAll(/DEPLOY (\w+)=(0x[0-9a-fA-F]{40})/g)) {
    addresses[match[1]] = ethers.getAddress(match[2]);
  }

  const required = ["lendingPool", "vault", "stableCoin", "router", "messageSender", "messageReceiver"];
  const missing = required.filter((key) => !addresses[key]);
  if (missing.length) {
    throw new Error(`Deploy to ${chain.name} did not report: ${missing.join(", ")}`);
  }

  log("deploy", `  pool ${addresses.lendingPool}  router ${addresses.router}`);
  return addresses;
}

/**
 * Teaches each chain about the other: the counterpart's receiver address (so
 * outbound messages have somewhere to go) and the counterpart's sender address
 * (so inbound messages pass the receiver's allow-list).
 */
async function crossRegister(deployment) {
  for (const local of CHAIN_LIST) {
    const remote = CHAIN_LIST.find((c) => c.key !== local.key);
    const localAddrs = deployment.chains[local.key];
    const remoteAddrs = deployment.chains[remote.key];

    const wallet = new ethers.Wallet(
      DEPLOYER.privateKey,
      new ethers.JsonRpcProvider(local.rpcUrl, local.chainId, {
        staticNetwork: ethers.Network.from(local.chainId),
      })
    );

    const registry = new ethers.Contract(localAddrs.registry, REGISTRY_ABI, wallet);
    const pool = new ethers.Contract(localAddrs.lendingPool, POOL_ABI, wallet);

    log("wire", `${local.name}: point at ${remote.name}`);

    // forge has just broadcast a long run of transactions from this same
    // account, so the nonce is read fresh and then tracked by hand — leaving it
    // to the provider picks up a stale cached value and fails with "nonce too
    // low" on the first call.
    let nonce = await wallet.provider.getTransactionCount(wallet.address, "pending");
    const send = async (promise) => {
      const tx = await promise;
      await tx.wait();
      nonce += 1;
    };

    // Where outbound messages for the remote chain should land.
    await send(
      registry.setCrossChainRegistryAddress(
        remote.selector,
        "crossChainMessageReceiverAddress",
        remoteAddrs.messageReceiver,
        { nonce }
      )
    );

    // Accept inbound messages that originated from the remote chain's sender.
    await send(pool.setallowListedSenders(remoteAddrs.messageSender, { nonce }));

    // The local sender must also accept calls from the local receiver, which
    // forwards responses back across the bridge.
    await send(
      pool.setAllowedCallersFoCrossChainMessageSender(localAddrs.messageReceiver, true, { nonce })
    );

    const check = await registry.getCrossChainAddress(
      remote.selector,
      "crossChainMessageReceiverAddress"
    );
    if (check !== remoteAddrs.messageReceiver) {
      throw new Error(`Cross-registration failed on ${local.name}: got ${check}`);
    }
  }
}

/** Sanity-check that the pool answers reads through the proxy. */
async function verify(deployment) {
  for (const chain of CHAIN_LIST) {
    const provider = new ethers.JsonRpcProvider(chain.rpcUrl, chain.chainId, {
      staticNetwork: ethers.Network.from(chain.chainId),
    });
    const pool = new ethers.Contract(deployment.chains[chain.key].lendingPool, POOL_ABI, provider);
    const price = await pool.getUsdValue(0, ethers.parseEther("1"));
    if (price === 0n) throw new Error(`${chain.name}: pool priced WETH at zero`);
    log("verify", `${chain.name}: 1 WETH = $${ethers.formatEther(price)}`);
  }
}

async function main() {
  const deployment = { createdAt: new Date().toISOString(), chains: {} };

  for (const chain of CHAIN_LIST) {
    deployment.chains[chain.key] = deployChain(chain);
  }

  await crossRegister(deployment);
  await verify(deployment);

  fs.writeFileSync(DEPLOYMENT_FILE, `${JSON.stringify(deployment, null, 2)}\n`);
  log("done", `wrote ${DEPLOYMENT_FILE}`);

  // Emit the env the backend needs, so start-demo.sh can splice it in.
  let env = [
    `ETH_LENDING_POOL_ADDRESS=${deployment.chains.eth.lendingPool}`,
    `ETH_VAULT_ADDRESS=${deployment.chains.eth.vault}`,
    `ETH_STABLE_COIN_ADDRESS=${deployment.chains.eth.stableCoin}`,
    `ARB_LENDING_POOL_ADDRESS=${deployment.chains.arb.lendingPool}`,
    `ARB_VAULT_ADDRESS=${deployment.chains.arb.vault}`,
    `ARB_STABLE_COIN_ADDRESS=${deployment.chains.arb.stableCoin}`,
  ].join("\n");
  env += `\nETH_CCIP_ROUTER_ADDRESS=${deployment.chains.eth.router}`;
  env += `\nARB_CCIP_ROUTER_ADDRESS=${deployment.chains.arb.router}`;
  fs.writeFileSync(`${REPO_ROOT}/tooling/deployment.env`, `${env}\n`);
  log("done", "wrote tooling/deployment.env");
}

main().catch((error) => {
  process.stderr.write(`\x1b[31mdeploy failed\x1b[0m ${error.message}\n`);
  process.exit(1);
});
