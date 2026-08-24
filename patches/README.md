# Local patches to `chainlink-local`

The cross-chain tests fork live testnets and route CCIP messages with
`CCIPLocalSimulatorFork`. Two bugs in that simulator stop messages from being
delivered. Both are in the library, not in this protocol.

Apply after a fresh clone, or any time `git submodule update` resets the
submodule:

```bash
./patches/apply.sh
```

The script is idempotent and refuses to apply against an unexpected upstream
version.

## Why these exist

### 1. `sender` is delivered as 20 bytes instead of 32

`CCIPLocalSimulatorFork` built the destination message with
`sender: abi.encodePacked(message.sender)` — a packed 20-byte address.
Production OffRamps deliver `abi.encode(address)`, a 32-byte word; Chainlink's
own `NonceManager.sol` decodes this exact field with
`abi.decode(sender, (address))`.

Any receiver following the documented pattern —

```solidity
abi.decode(message.sender, (address))
```

— therefore reverts with **no error data** on a 20-byte input, which is what
`CrossChainMessageReceiver._ccipReceive` does. The OffRamp swallows the revert
and emits `MessageExecuted`, so the test sees unchanged destination state and
fails later with a misleading error such as "not enough collateral".

Upstream v0.2.9 fixed this same class of bug for `receiver`, `destTokenAddress`
and `sourcePoolAddress`, but missed `sender`.

### 2. `switchChainAndRouteMessage(uint256)` no longer switches the fork

Through v0.2.4 this overload unconditionally called `vm.selectFork(forkId)`, and
its docstring still promises it "switches to a destination network fork". Since
the v0.2.5 routing rewrite, the fork is only selected inside the message-match
loop — so a call that finds no unprocessed message leaves the *source* fork
active. Tests that use the call to change chains then touch contracts that do
not exist on the active fork.

The patch restores the unconditional switch for the single-fork overload only.
The multi-fork overload keeps upstream behaviour, since it has no single
unambiguous destination.

## Context: why the tests broke without any code change

The suite forks at *latest*, so it follows whatever Chainlink has deployed.
Chainlink migrated the Sepolia ↔ Arbitrum Sepolia lane to **CCIP 1.6**, whose
OnRamp emits `CCIPMessageSent` rather than the v1.5 `CCIPSendRequested`. The
pinned simulator (v0.2.4) only listened for the v1.5 event, found nothing, and
silently routed no messages at all.

Verify the live lane version with:

```bash
cast call 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 \
  "getOnRamp(uint64)(address)" 3478487238524512106 --rpc-url "$ETH_SEPOLIA_RPC"
cast call <that address> "typeAndVersion()(string)" --rpc-url "$ETH_SEPOLIA_RPC"
```

Upgrading the submodule to **v0.2.9** handles the 1.6 event and OffRamp
selection; these two patches cover what v0.2.9 still gets wrong.

## Removing these patches

If a future release fixes both, drop the submodule bump in, delete this
directory, and confirm with:

```bash
forge test --match-path test/unit/CrossChainLending.t.sol
```
