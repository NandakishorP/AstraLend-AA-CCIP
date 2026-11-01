# AstraLend — RWA Track: Status and Forward Plan

Last updated: 2026-10-20 · Branch `main` · 24/24 RWA unit tests passing

This document is the planning baseline for the real-world-asset track. It covers
how we got here, what exists, what is verified, what is not, and what the live
options are.

---

## 1. Where we are right now

| | |
|---|---|
| Active branch | `main` — contains the full RWA track, 1 commit ahead of origin |
| Revert points | `stage1-complete` (pre-RWA), `rwa-token-based` (superseded design) |
| Stage-1 branch | `stage1-review` — pushed, carries the panel deck and restart script |
| RWA unit tests | 24 passing |
| Pool contract size | 16,254 of 24,576 bytes (8,322 free) |
| Last verified end-to-end | Full lifecycle ran clean on freshly built chains |

**Uncommitted working-tree changes:** `src/GSM/GlobalStateManager.sol` carries a
`forge fmt` pass (SPDX header restored, blank lines collapsed, one signature
reflowed) — verified to contain no logic change. `tooling/restart-demo.sh` has an
uncommitted extension that drives the RWA lifecycle. Both are safe to commit.

---

## 2. How we got here

### Stage 1 — cross-chain money market (complete)

A lending protocol spread across two chains. A hub chain holds authoritative
state; satellites hold read-only mirrors. Cross-chain messages carry state
changes, never tokens. Collateral deposited on one chain can back a loan drawn
on another.

26 contracts, ~4,100 lines. Backend API with a SQLite indexer, Next.js web app,
and a one-command local two-chain harness. Tagged `stage1-complete`.

### RWA attempt 1 — we issued the token (abandoned)

The first design had us mint our own security token with an `encumbered` mapping
so collateral could be pledged without being transferred. It worked and was
tested.

**Why it was abandoned.** Minting a representation of an off-chain holding is the
same lock-and-mint shape as the bridging the whole project exists to avoid, and
it made us a tokenisation project rather than a lending one. It also required
standing up an SPV, a custody arrangement and a redemption reserve to model an
asset that institutions have already tokenised.

Preserved at tag `rwa-token-based`.

### RWA attempt 2 — lend against someone else's token (current)

Real tokenised securities are **ERC-3643** (Ondo, Tokeny issuances, most
permissioned RWA). That standard already carries the primitive we need:

```
a transfer requires   amount <= balanceOf(from) - frozenTokens(from)
```

`freezePartialTokens` immobilises a holding in place. `forcedTransfer` moves it
on enforcement. Both are `onlyAgent`. Our own token was a partial
reimplementation of a deployed, audited standard, so it was deleted.

**The insight worth keeping:** that freeze capability exists because regulators
require issuers to be able to restrict transfers. It was built for compliance.
Nobody had used it as a lending primitive.

---

## 3. How the mechanism works

### The enforcement rule

Lives in the issuer's token, not ours. Freeze part of a holder's balance and
neither they nor anyone else can move that part — including a rival protocol
holding a full ERC-20 approval.

### What gives us the right to operate it

```solidity
security.addAgent(address(lienRegistry))
```

One call from the issuer. **This is the on-chain half of a tri-party
agreement** and the real dependency of the design — a business relationship
before it is a transaction. `LienRegistry.assertIsAgent()` exists so a
misconfigured deployment fails at setup rather than at a borrower's first pledge.

### Pledging

`pool.depositRwaCollateral(tokenId, amount)` — guarded on asset type and
hub-only — routes to `CollateralController.depositRwaCollateral`, which is the
crypto path **minus the line `vault.depositCollateral(...)`**. Nothing transfers.

```
lienRegistry.createLien / increaseLien
  └─ security.freezePartialTokens(borrower, amount)
GSM.updateDepositCollateralOfUser(...)      ← identical to crypto collateral
GSM.mirrorUpdateOfTheUserCollateral(...)    ← message to the satellite
```

From the state manager's perspective RWA and crypto collateral are
indistinguishable. Only *how it is held* differs. That is why borrowing needed no
new machinery.

Double-pledging is blocked by the token: `freezePartialTokens` requires
`balance >= frozen + amount`, and every agent increments the same counter.

### Valuation

`s_priceFeed[10]` points at `TBillNavOracle`, which implements
`AggregatorV3Interface` — so `getUsdValue`, health factors, liquidation and the
keeper work untouched. It computes rather than reports: linear accretion from
issue price to par. No feed, no staleness window.

The satellite runs an identical oracle from the same four constants, so both
chains derive the same value with no cross-chain quote. They differ by clock
skew only (~3e3 of 9.5e9 measured — a few seconds of a 364-day discount).

### Release and foreclosure

Withdrawal branches on `isRwaAsset` → `decreaseLien` → `unfreezePartialTokens`.
Nothing comes back, because nothing left.

Foreclosure **unfreezes the exact charge, then forces the transfer** — in that
order. ERC-3643's `forcedTransfer` unfreezes only the shortfall, spending free
balance first, so calling it directly on an 800 charge against a holder with 200
free would consume their 200 unpledged tokens and strand a 200 freeze against a
lien that no longer exists.

---

## 4. Complete inventory

### Contracts (`src/rwa/`)

| File | Lines | Role |
|---|---|---|
| `LienRegistry.sol` | 286 | The register of charges; drives the token's freeze |
| `TBillNavOracle.sol` | 122 | Accretion-based valuation, Chainlink-interface compatible |
| `EligibilityRegistry.sol` | 103 | Holder verification (stands in for the issuer's identity registry) |
| `interfaces/IERC3643.sol` | 84 | The subset of the standard we depend on |
| `interfaces/ILienRegistry.sol` | 40 | |
| `interfaces/IRWAValuation.sol` | 30 | Extends `AggregatorV3Interface` with maturity |
| `interfaces/IEligibilityRegistry.sol` | 14 | |

### Pool integration (`src/LendingPoolContract.sol`)

`RiskParams` struct and `s_riskParams` mapping · `addRwaAsset()` ·
`depositRwaCollateral()` · `getLtv()` · `getLiquidationThreshold()` ·
`getAssetMaturity()` · `isRwaAsset()` · `setLienRegistry()` ·
`ActionType.LIEN_CREATED` / `LIEN_RELEASED`

Also touched: `CollateralController` (no-custody deposit path, withdraw branch),
`LoanController` (per-asset LTV, maturity guard), `GlobalStateManager` and
`StateAggregator` (`setInitialBorrowerIndex`).

### Test scaffolding (`test/`)

| File | Lines | Role |
|---|---|---|
| `unit/RWACollateral.t.sol` | 405 | 24 tests |
| `mocks/MockERC3643.sol` | 184 | Stands in for a third-party issuance; copies T-REX behaviour |
| `mocks/MockRedemptionDesk.sol` | 105 | Models turning foreclosed collateral into cash |

### Deployment and demo

`script/DeployRwa.s.sol` (130) · `script/DeployRwaSatellite.s.sol` (81) ·
`tooling/deploy-rwa.mjs` (134) · `tooling/rwa-scenario.mjs` (433)

### Off-chain

**Backend** — `services/rwa.service.ts` (293), `routes/rwa.route.ts` (143).
Endpoints: `/rwa/status`, `/agency`, `/nav`, `/holding/:address`,
`/lien/:address`. Three DB tables: `liens`, `eligibility`, `nav_history`.
Indexer decodes `TokensFrozen` / `TokensUnfrozen` plus our own lien events.

**Frontend** — `app/app/collateral/page.tsx`, five `useRwa*` hooks. Shows a
custody panel (security, issuer, our agency status), the frozen-vs-free split as
one bar, accretion progress, and the register of charges.

---

## 5. What is verified, and what is assumed

### Verified on freshly built chains

```
✓ the issuer has appointed our registry an agent on the security
✓ balance unchanged after pledging — the bill never left the wallet
✓ holder sends 900 → refused, InsufficientFreeBalance
✓ a rival protocol pulls it with a full approval → refused
✓ holder tries to unfreeze their own collateral → refused, NotAgent
✓ the charge crossed as a message; the security stayed on the hub
✓ borrowed 50,000 SC on a chain where the collateral does not exist
✓ debt discharged on the chain it was drawn from
✓ withdrawal lifted the charge; the same tokens move freely again
✓ enforcement took exactly what was pledged, no orphaned freeze
✓ collateral realised back into stablecoin
```

### Simulated, and labelled as such

- **The security** is a mock standing in for a third-party issuance. It copies
  T-REX reference behaviour rather than inventing it, so protocol code would
  work against a real issuance given agent rights.
- **The redemption desk** models a secondary sale. In reality the trustee sells
  through a broker and remits — off-chain, and not makeable trustless.
- **CCIP** locally is a mock router plus an off-chain relayer standing in for
  the DON. Protocol contracts are unchanged; only the router address differs.
- **The institutions** — SPV, custodian, security trustee — are addresses, not
  parties.

---

## 6. Known gaps

Ordered by what would hurt most under scrutiny.

### P0 — the automated and enforcement paths are disconnected

`GlobalStateManager.liquidate()` calls `liquidityManager.addLiquidity(...)` —
bookkeeping that assumes the collateral already sits in the Vault. **For an RWA
loan nothing is in the Vault**; the security is frozen in the borrower's wallet.

So an overdue RWA loan escalates two penalties, is "liquidated" into liquidity
that does not exist, the lien stays standing, the freeze never lifts, and the
trustee is never involved. The demo does not catch this because foreclosure is
driven manually by the trustee.

*Fix:* branch `liquidate()` on `isRwaAsset(tokenId)`; for RWA emit an event the
trustee's keeper watches and route enforcement through `LienRegistry.foreclose`.

### P0 — CCIP integration tests unrun since Stage 2

Last passed 9/9 during Stage 1. They fork live testnets and are the only
evidence real CCIP still works. Every RWA change has landed since, so the claim
is older than the code.

*Fix:* `./patches/apply.sh` then
`forge test --match-path test/unit/CrossChainLending.t.sol`.

### P1 — eligibility is not checked at pledge time

Holder restriction is enforced only in the security's `_update`, on transfers.
Attestations expire, so a holder whose eligibility lapsed after receiving tokens
can still pledge and borrow. Roughly two lines in `depositRwaCollateral`.

### P1 — loan tenor is hardcoded at 180 days

`LoanController.sol:97`. Combined with the maturity guard this makes RBI's
91-day and 182-day bills unusable; only 364-day works, which is why the demo
deploys that tenor. Make tenor a borrow parameter bounded by collateral maturity.

### P1 — NAV is computed by us, not published by the issuer

Correct if we were valuing a bare bill ourselves, wrong for a third-party
security — OUSG and BUIDL publish their own NAV, and taking theirs is the point
of not being the issuer. Keep the current oracle as the demo stand-in and add an
adapter behind the same interface.

### P2 — pre-existing protocol gaps, deliberately unfixed

Aggregate borrows never increment on the protocol-wide counter. Crypto
liquidation does not set `isLiquidated`/`isClosed`. Interest accrues only on
interaction. `initialize` is front-runnable, `setReceiverAddress` is
unauthenticated, there is no oracle staleness check, `Vault.paused` is a dead
switch.

### P3 — operational and documentation

- `main` compiles with `via_ir`, so a cold `restart-demo.sh` takes **~25
  minutes**, not the 68 seconds the stage-1 branch takes. Warm the build cache
  before any live demo.
- The legal write-up does not exist. The trust-deed framing, party structure and
  statutory mapping live only in commit messages and code comments.
- SPDX identifiers and NatSpec were stripped from 39 of 40 `src/` files before
  this work. 28 of those had zero functional change, so
  `git checkout 702170b -- <file>` restores them cleanly.

---

## 7. Decisions already settled

Recorded so they are not re-argued.

| Decision | Rationale |
|---|---|
| We do not issue the collateral | Minting a representation is the lock-and-mint shape we reject; also makes us a tokenisation project |
| ERC-3643, not a custom token | The freeze primitive already exists, deployed and audited |
| Agent appointment is the dependency | Accepted as a commercial relationship, surfaced via `/rwa/agency` and `assertIsAgent` |
| Encumbrance, not custody | A pool holding a security becomes holder of record and inherits licensing it cannot discharge |
| Hub-only for the security | The instrument exists on one chain; only messages about the charge cross |
| Enforcement agent is the registry, not the trustee's address | A pledged balance can only move with both a legal person deciding and a lien record justifying it |
| Running-account charge per (borrower, asset) | Matches how the pool aggregates collateral |
| Foreclosure discharges before transferring | Avoids consuming unpledged tokens and orphaning a freeze |
| Jurisdiction framing | Indian law: Depositories Act 1996 s.12 recorded pledge; Contract Act 1872 s.176 sale on default; Trusts Act 1882 for the beneficial-interest framing |

---

## 8. Open decisions

1. **Jurisdiction to design against.** IFSCA / GIFT City was proposed — it has a
   regulatory sandbox and is treated as offshore for FEMA — but never confirmed.
2. **Who carries the legal write-up.** It runs parallel to the build and is
   roughly a third of what a reviewer reads.
3. **Whether ZK eligibility stays in scope.** Designed, never built. Only
   required if the borrower must prove accreditation without revealing identity;
   if the issuer's identity registry is accepted as the gate, it is unnecessary.
4. **Which real issuance to target.** Determines whose agent rights we would
   need, and therefore the whole commercial conversation.

---

## 9. Forward options

### A. Close the P0 gaps (smallest, highest value)

Wire the keeper into RWA foreclosure, and run the CCIP fork tests. Makes the
existing demo defensible under questioning. Low effort, removes the two things
that would most damage a review.

### B. Harden for a credible prototype

A, plus eligibility at pledge time, configurable loan tenor, and an
issuer-published NAV adapter. Takes the system from "demonstrates the idea" to
"would survive a technical review".

### C. Extend the asset classes

Per-asset valuation strategies for money-market funds (continuous NAV, no
maturity), private credit (attested NAV, staleness-prone, higher haircut),
invoices (binary outcome). The scaling axis is *how NAV is determined* and
*whether the instrument matures* — which makes the expansion principled rather
than a list.

### D. Write the legal track

Instrument, party structure, security interest creation and perfection,
compliance, enforcement path, jurisdiction mapping, limitations. Does not need
engineering time and can run in parallel.

### E. Quantitative evaluation

Gas benchmark of message-based versus bridge-based cross-chain borrowing. A
third satellite chain to show the topology generalises beyond a pair. Latency
measurement under load. This is what turns the project into a paper with
results rather than a description.

---

## 10. Running it

```bash
# full teardown, rebuild, seed crypto position, run RWA lifecycle
./tooling/restart-demo.sh 1        # or 4; 2 and 3 are the RWA holder and trustee

# RWA lifecycle alone, against an already-running stack
source tooling/rwa.env && node tooling/rwa-scenario.mjs

# unit tests
forge test --match-path test/unit/RWACollateral.t.sol
```

| | |
|---|---|
| Web app | http://localhost:3000 |
| RWA collateral page | http://localhost:3000/app/collateral |
| API docs | http://localhost:3001/docs |
| Relayer | http://localhost:8547/messages |
| RWA holder | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` (anvil #2) |
| Security trustee | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` (anvil #3) |

**Warm the build cache with `forge build` before any live demo on `main`.**
