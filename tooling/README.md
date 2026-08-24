# Local two-chain demo environment

Runs the whole protocol — both chains, cross-chain messaging, the API and the
web app — on one machine with no internet connection.

```bash
./tooling/start-demo.sh
```

| | |
| --- | --- |
| web app | http://localhost:3000 |
| API docs | http://localhost:3001/docs |
| relayer status | http://localhost:8547/messages |
| hub chain | http://localhost:8545 — Ethereum Sepolia chain id (11155111) |
| satellite chain | http://localhost:8546 — Arbitrum Sepolia chain id (421614) |

Demo wallet: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`, Anvil key #0.

## What each piece does

| File | Role |
| --- | --- |
| `start-demo.sh` | Starts both chains, deploys, updates `backend/.env`, starts relayer + API + web app |
| `deploy-local.mjs` | Deploys to both chains, then **cross-registers** them |
| `relayer.mjs` | Stands in for Chainlink's DON — delivers messages between the two nodes |
| `scenario.mjs` | Walks the full story end to end, and verifies it |
| `config.mjs` | Chain ids, CCIP selectors, ports — shared by the above |

## Why a relayer is needed

On a real network the Chainlink DON watches each chain's Router for outbound
messages and executes them on the destination. Between two Anvil nodes nothing
does that, so a deposit on the satellite chain would never reach the hub and the
protocol would look broken.

`relayer.mjs` closes the loop:

1. watches `MockCCIPRouter.MockCCIPMessageSent` on both chains
2. resolves the destination chain from the CCIP selector
3. impersonates the destination router (`anvil_impersonateAccount`)
4. calls `CrossChainMessageReceiver.ccipReceive` as that router

This mirrors what `CCIPLocalSimulatorFork` does inside the Foundry tests,
including encoding `sender` as a 32-byte `abi.encode(address)` — a 20-byte
packed value makes the receiver's `abi.decode(message.sender, (address))` revert
with no error data.

**Fidelity note.** The local demo swaps the CCIP Router for
`test/mocks/MockCCIPRouter.sol` so it runs offline and deterministically. Real
CCIP compatibility is evidenced separately by the integration tests, which run
against genuine forked Sepolia and Arbitrum Sepolia CCIP contracts:

```bash
forge test --match-path test/unit/CrossChainLending.t.sol
```

## Running the scenario

```bash
node tooling/scenario.mjs          # the whole story
node tooling/scenario.mjs --seed   # stop after borrowing, leave a live position
```

It walks, and asserts:

1. supply liquidity on the hub
2. post collateral on the **satellite** → arrives on the hub over CCIP
3. borrow stablecoin on the **hub** against that collateral
4. repay from the **satellite** → the hub's loan balance drops
5. fast-forward past the due date and run the keeper to liquidation

`--seed` is what to run before a live demo: it leaves a real cross-chain
position on screen for you to drive from the browser.

## Demo controls in the app

The dashboard shows a **Demo environment** panel when — and only when — the
backend detects this local setup (`tooling/deployment.local.json` present and
the chains answering Anvil-only RPC). It offers:

- **Advance chain time** — a 180-day term and a 3-stage liquidation cascade
  cannot be waited out on a testnet; here they take seconds
- **Run keeper** — lists overdue loans and calls `performUpkeep`
- **Cross-chain messages** — every message in flight, with delivery status
- **Chain clocks** — block height and how far each chain has been advanced

## A suggested five-minute demo

1. `./tooling/start-demo.sh`, then `node tooling/scenario.mjs --seed`
2. Open the dashboard. Point at **Collateral $4,000** and note it was posted on
   Arbitrum while the **$1,000 debt** was drawn on Ethereum.
3. Show the cross-chain message list — each one is a real delivered message.
4. Switch the chain selector to Arbitrum. The same position is visible there.
5. Press **+185d**, then **+30d**. The loan goes overdue.
6. Press **Run keeper** three times, advancing 30 days between each. Watch the
   penalties escalate, then the position liquidate.

## Resetting

Ctrl-C the script and run it again. Anvil keeps no state between runs, so every
start is a clean chain and a fresh deployment.

## Troubleshooting

**Messages stay "in flight".** The relayer is not running or crashed —
`tail tooling/logs/relayer.log`.

**"Demo controls are only available in the local environment".** The backend
cannot find `tooling/deployment.local.json`; re-run `deploy-local.mjs`.

**A transaction reverts with `InvalidChainId`.** The deployment predates the
allowed-chains fix. Redeploy.

## Real-world asset collateral

Deploy the RWA module onto a running hub, then drive the lifecycle:

```bash
# Addresses come from tooling/deployment.env, written by deploy-local.mjs.
export LENDING_POOL=$(grep ETH_LENDING_POOL_ADDRESS tooling/deployment.env | cut -d= -f2)
export STABLE_COIN=$(grep ETH_STABLE_COIN_ADDRESS  tooling/deployment.env | cut -d= -f2)

# Anvil accounts #2 and #3. Deliberately not #0: relayer.mjs signs with the
# deployer key continuously and anything sharing it loses the nonce race.
export DEMO_HOLDER=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
export SECURITY_TRUSTEE=0x90F79bf6EB2c4f870365E785982E1f101E93b906

forge script script/DeployRwa.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Then export the five DEPLOY rwa* addresses it prints and run:
RWA_TOKEN=0x… RWA_ISSUER=0x… RWA_LIENS=0x… node tooling/rwa-scenario.mjs
```

Copy the same addresses into `backend/.env` as `RWA_*_ADDRESS` for the
`/app/collateral` page to come alive.

### What the scenario proves

| Step | Claim |
| --- | --- |
| 3 | `balanceOf` is identical before and after pledging — nothing was transferred |
| 4 | The pledged part cannot move, and refuses with `RWAToken__Encumbered` specifically |
| 4 | A rival protocol with a full approval also cannot pull it — so the same holding cannot back two loans |
| 4 | The free remainder still transfers, so the charge is targeted rather than a freeze |
| 5 | The satellite's collateral rises by exactly the pledged amount, with no token contract there at all |
| 6 | The trustee forecloses and the instrument redeems itself — no court, no auction, no buyer |

The scenario is rerunnable: it tops the holder back up, and a foreclosed charge
does not block a later pledge.

### Two constraints worth knowing

**Loan tenor bounds the instrument.** `LoanController` fixes every loan at 180
days and refuses one that would outlive its collateral, so a 91-day bill cannot
back a standard loan at all. The demo deploys a 364-day bill for that reason.
RBI issues 91, 182 and 364-day tenors; only the longest works until loan
duration becomes configurable.

**The lien registry's authorised caller is the CollateralController, not the
pool proxy.** The pool delegates collateral handling, so the controller is what
calls `createLien`. Pointing it at the proxy reverts with
`Lien__OnlyPool(controller)`. `DeployRwa.s.sol` resolves it through
`getCollateralControllerAddress()`.
