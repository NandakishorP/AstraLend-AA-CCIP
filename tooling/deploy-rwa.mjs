#!/usr/bin/env node
/**
 * Deploys the real-world asset module across both chains.
 *
 *   node tooling/deploy-rwa.mjs
 *
 * Assumes the protocol is already deployed (tooling/deploy-local.mjs).
 *
 * Two chains, deliberately asymmetric:
 *
 *   hub        the instrument itself — token, issuer, lien registry,
 *              eligibility registry, valuation
 *   satellite  a valuation oracle and an asset registration, nothing more
 *
 * The satellite gets no token and no registry because neither belongs there.
 * It only ever learns that a charge exists, through the mirrored collateral
 * message. What it does need is a way to value what it has been told about, and
 * for a Treasury bill that is free: the value is arithmetic over four constants,
 * so the same oracle deployed on both chains derives the same number with no
 * feed and no cross-chain quote. The constants are read back off the hub oracle
 * here rather than re-specified, so the two curves cannot drift apart.
 *
 * Writes the addresses into backend/.env and prints the exports the scenario
 * needs.
 */

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";
import { CHAINS, DEPLOYER, DEPLOYMENT_FILE, REPO_ROOT } from "./config.mjs";

// Anvil accounts #2 and #3. Not #0: relayer.mjs signs with the deployer key
// continuously and anything sharing it loses the nonce race. Holder and trustee
// are separate from each other because they are separate legal parties.
const HOLDER = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC";
const TRUSTEE = "0x90F79bf6EB2c4f870365E785982E1f101E93b906";

const NAV_ABI = [
  "function issuePrice() view returns (uint256)",
  "function faceValue() view returns (uint256)",
  "function issueDate() view returns (uint64)",
  "function maturityDate() view returns (uint64)",
];

const log = (t) => process.stdout.write(`\x1b[35mrwa\x1b[0m ${t}\n`);

function forgeScript(script, rpcUrl, env) {
  const out = execFileSync(
    "forge",
    ["script", script, "--rpc-url", rpcUrl, "--broadcast", "--private-key", DEPLOYER.privateKey],
    { cwd: REPO_ROOT, encoding: "utf8", env: { ...process.env, ...env }, stdio: ["ignore", "pipe", "pipe"] }
  );
  const addresses = {};
  for (const match of out.matchAll(/DEPLOY (\w+)=(0x[0-9a-fA-F]{40})/g)) {
    addresses[match[1]] = ethers.getAddress(match[2]);
  }
  return addresses;
}

async function main() {
  const deployment = JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, "utf8"));

  log(`hub → ${CHAINS.eth.rpcUrl}`);
  const hub = forgeScript("script/DeployRwa.s.sol", CHAINS.eth.rpcUrl, {
    LENDING_POOL: deployment.chains.eth.lendingPool,
    STABLE_COIN: deployment.chains.eth.stableCoin,
    DEMO_HOLDER: HOLDER,
    SECURITY_TRUSTEE: TRUSTEE,
  });
  log(`  token ${hub.rwaToken}  registry ${hub.rwaLienRegistry}`);

  // Read the curve back off the hub rather than restating it, so the satellite
  // cannot be given a different instrument by accident.
  const hubProvider = new ethers.JsonRpcProvider(CHAINS.eth.rpcUrl, CHAINS.eth.chainId, {
    staticNetwork: ethers.Network.from(CHAINS.eth.chainId),
  });
  const navOracle = new ethers.Contract(hub.rwaNavOracle, NAV_ABI, hubProvider);
  const curve = {
    ISSUE_PRICE: (await navOracle.issuePrice()).toString(),
    FACE_VALUE: (await navOracle.faceValue()).toString(),
    ISSUE_DATE: (await navOracle.issueDate()).toString(),
    MATURITY_DATE: (await navOracle.maturityDate()).toString(),
  };

  log(`satellite → ${CHAINS.arb.rpcUrl}`);
  const satellite = forgeScript("script/DeployRwaSatellite.s.sol", CHAINS.arb.rpcUrl, {
    LENDING_POOL: deployment.chains.arb.lendingPool,
    RWA_TOKEN: hub.rwaToken,
    ...curve,
  });
  log(`  valuation ${satellite.rwaNavOracleSatellite} (same curve, no bridge)`);

  // ─── backend/.env ─────────────────────────────────────────────────────────
  const envPath = path.join(REPO_ROOT, "backend", ".env");
  if (fs.existsSync(envPath)) {
    let env = fs.readFileSync(envPath, "utf8");
    env = env.replace(/\n# ─── Real-world asset[\s\S]*?(?=\n# ───|$)/, "");
    env += [
      "",
      "# ─── Real-world asset collateral (hub only) ───────────────────────────────────",
      "# Written by tooling/deploy-rwa.mjs.",
      `RWA_TOKEN_ADDRESS=${hub.rwaToken}`,
      `RWA_ISSUER_ADDRESS=${hub.rwaIssuer}`,
      `RWA_LIEN_REGISTRY_ADDRESS=${hub.rwaLienRegistry}`,
      `RWA_ELIGIBILITY_ADDRESS=${hub.rwaEligibility}`,
      `RWA_NAV_ORACLE_ADDRESS=${hub.rwaNavOracle}`,
      "",
    ].join("\n");
    fs.writeFileSync(envPath, env);
    log("wrote backend/.env — restart the API to pick it up");
  }

  const addrFile = path.join(REPO_ROOT, "tooling", "rwa.env");
  fs.writeFileSync(addrFile, [
    `export RWA_TOKEN=${hub.rwaToken}`,
    `export RWA_ISSUER=${hub.rwaIssuer}`,
    `export RWA_LIENS=${hub.rwaLienRegistry}`,
    `export RWA_ELIG=${hub.rwaEligibility}`,
    `export RWA_NAV=${hub.rwaNavOracle}`,
    "",
  ].join("\n"));

  log("wrote tooling/rwa.env");
  process.stdout.write("\nNext:\n  source tooling/rwa.env && node tooling/rwa-scenario.mjs\n\n");
}

main().catch((error) => {
  process.stderr.write(`\n\x1b[31m${error.stderr?.toString() ?? error.message}\x1b[0m\n`);
  process.exit(1);
});
