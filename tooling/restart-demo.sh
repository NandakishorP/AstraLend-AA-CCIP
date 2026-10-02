#!/usr/bin/env bash
#
# Tears the demo down and brings it back up from a clean slate, then seeds a
# live cross-chain position so the UI is not empty.
#
#   ./tooling/restart-demo.sh          # seed on anvil account #1
#   ./tooling/restart-demo.sh 2        # seed on anvil account #2
#
# Takes roughly 90 seconds. Everything is left running in the background, so
# this terminal is free afterwards.
#
# Why the account index matters: MetaMask caches the next nonce per chain id,
# and the chain id stays 424242 across restarts. A rebuilt chain resets nonces
# to zero while MetaMask still remembers the old ones, which surfaces as a
# nonce conflict. Switching to an account MetaMask has never seen sidesteps it
# entirely -- no settings to hunt for.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Anvil's deterministic accounts. Index 0 is the deployer and is deliberately
# not offered: the deploy scripts and seed script both sign as it.
KEYS=(
  "" # 0 - reserved for deployment
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"
  "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
)
ADDRS=(
  ""
  "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
  "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
  "0x90F79bf6EB2c4f870365E785982E1f101E93b906"
  "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
)

IDX="${1:-1}"
if [ -z "${KEYS[$IDX]:-}" ]; then echo "pick an account index between 1 and 4" >&2; exit 1; fi

say() { printf "\033[35m>\033[0m %s\n" "$1"; }

say "stopping everything"
pkill -f "anvil --chain-id" 2>/dev/null || true
pkill -f "relayer.mjs" 2>/dev/null || true
pkill -f "tsx watch src/app.ts" 2>/dev/null || true
pkill -f "backend/node_modules/.bin/tsx" 2>/dev/null || true
pkill -f "next dev" 2>/dev/null || true
pkill -f "next-server" 2>/dev/null || true
rm -f backend/data/astralend.db*
sleep 2

say "rebuilding both chains and the full stack (~90s)"
nohup ./tooling/start-demo.sh > tooling/logs/start-demo.log 2>&1 &

for _ in $(seq 1 150); do
  curl -fsS -o /dev/null http://127.0.0.1:3000/ 2>/dev/null && break
  sleep 2
done
curl -fsS -o /dev/null http://127.0.0.1:3000/ 2>/dev/null || { echo "stack did not come up; see tooling/logs/" >&2; exit 1; }

say "seeding a cross-chain position on account #$IDX"
DEMO_KEY="${KEYS[$IDX]}" node tooling/scenario.mjs --seed 2>&1 | grep -E "supplied|posted|hub now sees|borrowed|records" || true

printf "\n  \033[35mReady.\033[0m\n"
cat <<BANNER

    Web app     http://localhost:3000
    API docs    http://localhost:3001/docs
    Relayer     http://localhost:8547/messages

    Use this account in MetaMask:
      ${ADDRS[$IDX]}
      ${KEYS[$IDX]}

    Network: AstraLend Hub, RPC http://127.0.0.1:8545, chain id 424242

BANNER
