# AstraLend

Cross-chain money market protocol enabling borrowing and lending across multiple chains using Chainlink CCIP for state synchronization.

Built to explore the challenges of maintaining consistency in cross-chain DeFi protocols. ~6,000 lines of Solidity across 50+ modular contracts.

## Features

**Cross-Chain Functionality:**
- Deposit collateral on one chain, borrow on another
- CCIP messaging for state synchronization  
- Global state manager on Ethereum
- State mirrors on satellite chains (Arbitrum, etc.)

**Architecture:**
- 50+ modular contracts including Vault, CollateralManager, LoanManager, GlobalStateManager
- ERC-677 token integration for callback behavior
- Custom error handling and security-focused design

**Testing:**
- Foundry test suite with comprehensive coverage
- Cross-chain integration tests using CCIPLocalSimulatorFork
- Automated liquidation tests with Chainlink Keepers

## Architecture Overview

### Ethereum (Main Chain)
- Holds canonical state via `GlobalStateManager`
- Processes cross-chain CCIP messages
- Updates CollateralManager, LoanManager, and Vault

### Satellite Chains
- Deployed instances of LendingPoolContract, StateMirror
- Read from Ethereum using CCIP message relays
- Act on mirrored state synced from Ethereum

### Cross-Chain Messaging
- Implemented via Chainlink CCIP
- Custom CrossChainPayload structure for typed communication
- Messages contain ActionType, token IDs, amounts, and metadata

## Tech Stack

- Solidity ^0.8.x
- Foundry for testing & deployment
- Chainlink CCIP
- OpenZeppelin Contracts (upgradeable, behind a transparent proxy)
- ERC-677
- Fastify, TypeScript and SQLite for the API and indexer
- Next.js, wagmi and viem for the web app

## Testing

Local simulation using forked Sepolia and Arbitrum Sepolia networks with full CCIP flow.

```bash
git submodule update --init --recursive
./patches/apply.sh      # required after a fresh clone — see below
forge test
```

```bash
# Run with verbosity
forge test -vvv

# Run a single file
forge test --match-path test/unit/CrossChainLending.t.sol
```

The cross-chain suite routes messages with `CCIPLocalSimulatorFork`. Two bugs in
that simulator stop delivery, so [`patches/apply.sh`](patches/apply.sh) must be run
after a fresh clone or any `git submodule update`. It is idempotent and refuses to
apply against an unexpected upstream version.
[`patches/README.md`](patches/README.md) explains both fixes and how to tell when
upstream has made them unnecessary.

> If these tests start failing with unrelated-looking errors — "not enough
> collateral", `0 != 1000000000000000000` — suspect message delivery first. When
> a message is not delivered the destination state simply never changes, and it
> is the *next* assertion that fails.

## Running it locally

Two chains, cross-chain messaging, the API and the web app, all on one machine
with no internet:

```bash
./tooling/start-demo.sh              # brings everything up
node tooling/scenario.mjs --seed     # leaves a live cross-chain position
```

Then open http://localhost:3000. The dashboard carries a demo panel showing chain
clocks, time travel, the liquidation keeper and every CCIP message in flight.

The lifecycle this exercises, end to end across both nodes:

| Step | Where | Result |
| --- | --- | --- |
| Supply liquidity | hub | 20 WETH into the pool |
| Post collateral | satellite | travels to the hub as a message |
| Borrow | hub | 1,000 SC against collateral held on the other chain |
| Repay | satellite | hub debt drops to 500 SC |
| Liquidate | hub | two penalties, then collateral seized |

Liquidation is gated at 180 days, so it is only demonstrable on a local node whose
clock can be advanced. [`tooling/README.md`](tooling/README.md) has the short
version of the demo script.

The local setup swaps the CCIP Router for a mock and relays messages with an
off-chain process, so it runs offline and deterministically. Compatibility with
real CCIP is shown separately by the integration tests, which run against genuine
forked Sepolia and Arbitrum Sepolia CCIP contracts.

The hub runs on chain id **424242** rather than reusing Sepolia's. Pointing a
wallet at a local node under a real network's id makes it price gas in that
network's currency, which fails every transaction on a balance the account does
not have.

The lending pool address the backend expects is the `TransparentUpgradeableProxy`,
not the implementation. See [`backend/README.md`](backend/README.md) and
[`frontend/README.md`](frontend/README.md) for each piece on its own.

## Repository Structure
```
src/                  the protocol
├── Vault.sol
├── LendingPoolContract.sol
├── GSM/              global state manager, hub-side authority
├── StateMirror/      mirrored state, satellite-side
├── service/          collateral, liquidity and loan controllers
├── ccip/
├── interfaces/
├── errors/
├── events/
└── tokens/

script/               Foundry deploy and scenario scripts
test/                 unit, fuzz and cross-chain integration tests
patches/              required fixes to chainlink-local
backend/              REST API and chain indexer (Fastify, SQLite)
frontend/             web app (Next.js, wagmi)
tooling/              local two-chain harness and CCIP relayer
```

## Status

**Complete:**
- ✅ Core lending & borrowing logic
- ✅ Cross-chain collateral tracking
- ✅ CCIP messaging and state synchronization
- ✅ Chainlink Keepers automation
- ✅ Cross-chain integration tests against forked testnets
- ✅ REST API with a chain indexer (`backend/`)
- ✅ Web app (`frontend/`)
- ✅ Local two-chain demo harness (`tooling/`)

**In Progress:**
- 🔄 Gas optimization
- 🔄 Documentation improvements

**Future Scope:**
- Additional chain deployments
- Real-world asset collateral
- ZK proof integration

## About

Learning project exploring cross-chain protocol design, CCIP architecture, and the challenges of maintaining state consistency across chains.

Not audited. Not for production use.

## License

MIT
