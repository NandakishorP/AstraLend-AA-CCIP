# AstraLend-AA-CCIP

**AstraLend** is a modular, cross-chain money market protocol built by a single developer, enabling seamless borrowing and lending across multiple chains. It leverages **Chainlink CCIP** for secure cross-chain messaging and **Account Abstraction (AA)** for gas-abstracted UX and smart account compatibility.

> ⚙️ Built with modular contracts, tested flows, and state synchronization mechanisms. Over 4500+ lines of code and 3+ months of solo development effort.

---

## 🚀 Features

- 🏦 **Lending & Borrowing** across chains (ETH, Arbitrum Sepolia, etc.)
- 🔗 **Cross-Chain Collateral**: Deposit on one chain, borrow from another
- 🧠 **Global State Manager** on Ethereum
- 🪞 **State Mirroring** to maintain protocol-wide consistency
- 📩 **CCIP Messaging** for cross-chain communication
- 🧱 **Modular Architecture**: 50+ contracts including:
  - `Vault`
  - `CollateralManager`
  - `LoanManager`
  - `GlobalStateManager`
  - `StateMirror`
  - `CCIPRequestHandler`
- 👛 **ERC-677** token integrations (for token callback behavior)
- 🔐 **Security-first development** using custom errors, minimal external calls, and modular design
- 🧪 **Test-first Development** using Foundry (`forge`)

---

## 🧠 Architecture Overview

### 🌍 Ethereum (Main Chain)
- Holds **canonical state** (`GlobalStateManager`)
- Processes **cross-chain CCIP messages**
- Updates `CollateralManager`, `LoanManager`, and `Vault`

### 🌐 Satellite Chains
- Deployed versions of `LendingPoolContract`, `StateMirror`, etc.
- Read from Ethereum using CCIP message relays
- Act on **mirrored state** synced from Ethereum

### 🔁 Cross-Chain Messaging
- Implemented via **Chainlink CCIP**
- Custom `CrossChainPayload` structure for typed communication
- Messages contain `ActionType`, token IDs, amounts, and metadata

---

## 🔗 Technologies Used

- [Solidity ^0.8.x](https://soliditylang.org/)
- [Foundry](https://book.getfoundry.sh/) for testing & scripting
- [Chainlink CCIP](https://docs.chain.link/ccip)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [ERC-677](https://eips.ethereum.org/EIPS/eip-677)

---

## 🧪 Testing

> Local simulation includes forking `Sepolia` and `Arbitrum Sepolia` with full CCIP flow.

- Foundry unit tests (`forge test`)
- End-to-end cross-chain integration tests with `CCIPLocalSimulatorFork`
- Automated liquidation tests using Chainlink Keepers

---

## 📁 Repository Structure

```bash
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

---

## 📌 Status

- [x] Lending & borrowing logic
- [x] Collateral deposit & tracking
- [x] CCIP messaging and relaying
- [x] Chainlink Keepers automation
- [ ] Documentation (in progress)
- [ ] ZKP integration (planned)
- [ ] UI / Frontend (future scope)

---

## 📚 Developer

Built by [Nandakishor P](https://github.com/NandakishorP) — 20 y/o DeFi builder, entering 3rd year of Computer Science.  
Focused on deep protocol design, security-first coding, and full-stack smart contract development.

---

## 🤝 Contributions & Feedback

This is a solo-built learning + portfolio project.  
Looking for:
- Code reviews
- Protocol advice
- Internship/grant opportunities in DeFi

---

## 📄 License

[MIT](LICENSE)
