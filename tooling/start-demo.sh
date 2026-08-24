#!/usr/bin/env bash
#
# Brings up the entire AstraLend demo on one machine, with no internet needed.
#
#   ./tooling/start-demo.sh
#
#   hub chain        http://127.0.0.1:8545   (Ethereum Sepolia chain id)
#   satellite chain  http://127.0.0.1:8546   (Arbitrum Sepolia chain id)
#   relayer status   http://127.0.0.1:8547
#   API              http://127.0.0.1:3001
#   web app          http://127.0.0.1:3000
#
# Everything is logged to tooling/logs/. Ctrl-C stops all of it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="$ROOT/tooling/logs"
mkdir -p "$LOGS"

DEPLOYER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

say() { printf "\033[35m▸\033[0m %s\n" "$1"; }

cleanup() {
  say "stopping…"
  # Kill the whole process group's children we started, quietly.
  for pid in ${PIDS:-}; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PIDS=""
start() { # start <logfile> <command...>
  local logfile="$1"; shift
  "$@" >"$LOGS/$logfile" 2>&1 &
  PIDS="$PIDS $!"
}

wait_for() { # wait_for <url> <label>
  local url="$1" label="$2"
  for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then say "$label ready"; return 0; fi
    sleep 1
  done
  echo "timed out waiting for $label ($url)" >&2
  exit 1
}

# ── Chains ────────────────────────────────────────────────────────────────────
say "starting hub chain (Ethereum Sepolia id) on :8545"
start anvil-eth.log anvil --chain-id 11155111 --port 8545 --silent

say "starting satellite chain (Arbitrum Sepolia id) on :8546"
start anvil-arb.log anvil --chain-id 421614 --port 8546 --silent

sleep 3
cast block-number --rpc-url http://127.0.0.1:8545 >/dev/null
cast block-number --rpc-url http://127.0.0.1:8546 >/dev/null
say "both chains up"

# ── Contracts ─────────────────────────────────────────────────────────────────
say "deploying protocol to both chains (takes ~30s)"
node "$ROOT/tooling/deploy-local.mjs"

# Splice the fresh addresses into the backend's .env, preserving everything else.
say "updating backend/.env with the new addresses"
while IFS='=' read -r key value; do
  [ -z "$key" ] && continue
  if grep -q "^${key}=" "$ROOT/backend/.env"; then
    sed -i '' -e "s|^${key}=.*|${key}=${value}|" "$ROOT/backend/.env"
  else
    printf '%s=%s\n' "$key" "$value" >>"$ROOT/backend/.env"
  fi
done <"$ROOT/tooling/deployment.env"

sed -i '' \
  -e 's|^ETH_SEPOLIA_RPC_URL=.*|ETH_SEPOLIA_RPC_URL=http://127.0.0.1:8545|' \
  -e 's|^ARB_SEPOLIA_RPC_URL=.*|ARB_SEPOLIA_RPC_URL=http://127.0.0.1:8546|' \
  -e 's|^PORT=.*|PORT=3001|' \
  "$ROOT/backend/.env"

# ── Services ──────────────────────────────────────────────────────────────────
say "starting CCIP relayer"
start relayer.log node "$ROOT/tooling/relayer.mjs"
wait_for http://127.0.0.1:8547/ "relayer"

say "starting API"
start backend.log npm --prefix "$ROOT/backend" run dev
wait_for http://127.0.0.1:3001/health "API"

say "starting web app"
start frontend.log npm --prefix "$ROOT/frontend" run dev
wait_for http://127.0.0.1:3000/ "web app"

cat <<BANNER

  \033[35mAstraLend demo is running\033[0m

    web app          http://localhost:3000
    API docs         http://localhost:3001/docs
    relayer status   http://localhost:8547/messages

    hub chain        http://localhost:8545   (chain id 11155111)
    satellite chain  http://localhost:8546   (chain id 421614)

    demo wallet      0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
    private key      $DEPLOYER_KEY

  Logs are in tooling/logs/. Press Ctrl-C to stop everything.

BANNER

wait
