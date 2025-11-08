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
- OpenZeppelin Contracts
- ERC-677

## Testing

Local simulation using forked Sepolia and Arbitrum Sepolia networks with full CCIP flow.
```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/GlobalStateManager.t.sol
```

## Repository Structure
```
src/
├── Vault.sol
├── LendingPoolContract.sol
├── GlobalStateManager/
├── CollateralManager/
├── LoanManager/
├── StateMirror/
├── ccip/
├── interfaces/
├── errors/
├── events/
└── tokens/
```

## Status

**Complete:**
- ✅ Core lending & borrowing logic
- ✅ Cross-chain collateral tracking
- ✅ CCIP messaging and state synchronization
- ✅ Chainlink Keepers automation
- ✅ Comprehensive test coverage

**In Progress:**
- 🔄 Gas optimization
- 🔄 Documentation improvements

**Future Scope:**
- Frontend UI
- Additional chain deployments
- ZK proof integration

## About

Learning project exploring cross-chain protocol design, CCIP architecture, and the challenges of maintaining state consistency across chains.

Not audited. Not for production use.

## License

MIT
