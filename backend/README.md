# AstraLend backend

Fastify + ethers service that sits between the AstraLend contracts and the web
app. It does three jobs:

1. **Aggregates reads.** One `/portfolio/:address` call replaces a dozen
   contract reads and returns the derived numbers the UI needs — USD values,
   accrued interest, health factors, borrowing power.
2. **Builds transactions.** `/tx/*` returns *unsigned* transactions for the
   user's wallet to sign. The backend's own key never moves user funds.
3. **Translates errors.** Solidity custom errors are decoded into sentences a
   user can act on, with the raw error name preserved for the client.

## Running it

```bash
npm install
cp .env.example .env      # fill in RPC URLs and deployed addresses
npm run dev               # tsx watch, http://localhost:3000
```

`GET /docs` serves the full OpenAPI reference with a try-it console.

### Environment

| Variable | Purpose |
| --- | --- |
| `ETH_SEPOLIA_RPC_URL` / `ARB_SEPOLIA_RPC_URL` | Chain endpoints. Point at `http://localhost:8545` for a local Anvil node. |
| `PRIVATE_KEY` | Signer for the faucet and the server-signed write endpoints. Not used by the wallet-signed flow. |
| `ACTIVE_CHAIN` | `eth` or `arb`; the default when a request omits `?chain=`. |
| `ETH_*_ADDRESS` / `ARB_*_ADDRESS` | Deployed lending pool (the **proxy**), vault and stablecoin per chain. |
| `PORT`, `HOST`, `LOG_LEVEL` | Server basics. |

Addresses come from `broadcast/DeployChainA.s.sol/<chainId>/run-latest.json`
after a deploy — the lending pool address is the `TransparentUpgradeableProxy`,
not the implementation.

## Endpoints

| Group | Route | Notes |
| --- | --- | --- |
| health | `GET /health`, `GET /health/ready` | Liveness, and per-chain RPC + contract reachability. Returns the report unwrapped, for container probes. |
| markets | `GET /markets`, `GET /markets/:tokenId` | Liquidity, collateral, borrows, prices, utilization, rates, TVL, risk parameters. Cached 10s. |
| portfolio | `GET /portfolio/:address` | Full user snapshot with risk math. |
| activity | `GET /activity/:address` | Decoded event history straight from logs. No indexer. |
| protocol | `GET /protocol/*` | Individual contract reads, when the aggregates are more than you need. |
| fees | `GET /fees/estimate` | CCIP fee for an operation. Zero on the hub chain. |
| tx-builder | `POST /tx/**` | Unsigned transactions for wallet signing. |
| liquidity / collateral / loan | `POST /liquidity/*`, … | Server-signed writes using `PRIVATE_KEY`. Useful for scripts and testing. |
| faucet | `GET /faucet/status`, `POST /faucet/drip` | Testnet mock assets. Reports per-asset mintability rather than failing blind. |

Every amount crosses the wire as a **decimal string**; USD values are 1e18-scaled
integers. Percentages and health factors are plain numbers.

## Design notes

- **Rates are recomputed, not read.** `InterestRateModel` is not reachable
  through the lending pool's ABI, so `market.service.ts` reproduces its kinked
  curve — including the quirk that utilization is measured as collateral over
  liquidity-plus-collateral. Keep it in sync with the Solidity if that changes.
- **Debt is derived, not fetched per loan.** Current debt is principal scaled by
  the ratio of the live borrower index to the index captured at origination,
  which is exactly what `getAmountToRepay` does — one read instead of N.
- **`getAmountToRepay` resolves against `msg.sender`.** Wallet-signed flows must
  pass `userAddress`, or the backend signer's loan gets priced instead.
- **Nonces are serialised.** Every server-signed transaction, approvals
  included, goes through one queue per chain (`blockchain/wallet.ts`). Never
  call `signer.sendTransaction` directly.
