#!/usr/bin/env bash
#
# Re-applies local fixes to the vendored chainlink-local simulator.
#
# Run this after a fresh clone, or any time `git submodule update` resets
# lib/chainlink-local. Safe to run repeatedly — it detects an already-patched
# tree and exits without touching anything.
#
#   ./patches/apply.sh
#
# See patches/README.md for what each fix does and why it is needed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE="$REPO_ROOT/lib/chainlink-local"
PATCH="$REPO_ROOT/patches/chainlink-local-v0.2.9-ccip-fork-fixes.patch"
TARGET="src/ccip/CCIPLocalSimulatorFork.sol"
EXPECTED_TAG="v0.2.9"

if [ ! -d "$SUBMODULE" ]; then
  echo "error: $SUBMODULE not found. Run: git submodule update --init --recursive" >&2
  exit 1
fi

cd "$SUBMODULE"

# The patch is written against a specific upstream release; applying it to a
# different one would either fail loudly or, worse, land in the wrong place.
ACTUAL_TAG="$(git describe --tags --exact-match 2>/dev/null || echo "unknown")"
if [ "$ACTUAL_TAG" != "$EXPECTED_TAG" ]; then
  echo "warning: chainlink-local is at '$ACTUAL_TAG', patch was written for $EXPECTED_TAG." >&2
  echo "         Re-check the fixes against the new version before trusting this." >&2
fi

if git apply --reverse --check "$PATCH" 2>/dev/null; then
  echo "Already patched — nothing to do."
  exit 0
fi

if ! git apply --check "$PATCH" 2>/dev/null; then
  echo "error: patch does not apply cleanly to $TARGET." >&2
  echo "       Upstream may have fixed these bugs; see patches/README.md." >&2
  exit 1
fi

git apply "$PATCH"
echo "Applied $(basename "$PATCH") to $TARGET"
echo "Run 'forge test --match-path test/unit/CrossChainLending.t.sol' to verify."
