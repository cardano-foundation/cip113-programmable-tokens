#!/usr/bin/env bash
# End-to-end falsification control for the CIP-113 Lean verification
# pipeline — "falsify every gate before you trust its green"
# (paolino's aiken-blaster-verification skill; Lean-blaster's own
# Vesting "bugged" example is the in-tree precedent).
#
# Legs, in order (any failure = RED, and RED here means the HARNESS is
# broken, not the validator):
#
#  0. Toolchain identity: installed `aiken` must byte-match the
#     blueprint preamble's compiler. Anything else is
#     COULD-NOT-EVALUATE — a rebuild with a different compiler proves
#     nothing about the committed artifact.
#  1. Flats freshness: `extract-flats.sh --check` green.
#  2. REPRODUCIBILITY (clean leg): rebuild the blueprint from HEAD in a
#     throwaway git worktree; every tracked `compiledCode` must match
#     the committed blueprint byte-for-byte.
#  3. MUTANT leg: in the same worktree, gut the base validator's only
#     check (withdrawal scan -> True), rebuild through the REAL
#     pipeline, extract the mutant flat, assert it differs from the
#     clean flat (the mutation reached the artifact under test).
#  4. Lean control: `controls/MutantControl.lean` must show the clean
#     artifact's Valid theorem FALSIFIED on the mutant (solve-result: 1)
#     and the mutant accepting the context the clean artifact rejects.
#  5. Restore + baseline re-verification: worktree removed (main tree
#     was never touched), `--check` re-run, clean `lake build` green.
#
# The working tree is NEVER mutated — all builds happen in a temp git
# worktree at HEAD.
set -euo pipefail

# Non-interactive shells may lack the elan (lake/lean) and local-z3 paths.
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$PATH"

FV="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$FV/.." && pwd)"
BLUEPRINT="$REPO/plutus.json"
WORKTREE="$(mktemp -d /tmp/cip113-falsification-XXXXXX)"
BASE_TITLE="programmable_logic_base.programmable_logic_base.spend"
MUTANT_FLAT="$FV/controls/flats/programmable_logic_base_mutant.flat"

cleanup() {
  git -C "$REPO" worktree remove --force "$WORKTREE" 2>/dev/null || true
  rm -rf "$WORKTREE"
}
trap cleanup EXIT

red() { echo "RED: $*" >&2; exit 1; }

echo "== Leg 0: toolchain identity (mechanical, not prose) =="
BP_COMPILER="$(jq -er '.preamble.compiler.version' "$BLUEPRINT")"
INSTALLED="$(aiken --version | awk '{print $2}')"
[ "aiken $INSTALLED" = "aiken $BP_COMPILER" ] \
  || red "installed aiken '$INSTALLED' != blueprint compiler '$BP_COMPILER' — COULD-NOT-EVALUATE (aikup install ${BP_COMPILER%%+*})"
echo "   aiken $INSTALLED == blueprint preamble"

echo "== Leg 1: flats freshness =="
"$FV/scripts/extract-flats.sh" --check || red "flats/manifest stale"

echo "== Leg 2: reproducibility — clean rebuild must reproduce the committed blueprint =="
git -C "$REPO" worktree add --detach "$WORKTREE" HEAD >/dev/null
(cd "$WORKTREE" && aiken build 2>/dev/null) || red "clean 'aiken build' failed in worktree"
CLEAN_CODE="$(jq -er --arg t "$BASE_TITLE" \
  '.validators[] | select(.title == $t) | .compiledCode' "$WORKTREE/plutus.json")"
COMMITTED_CODE="$(jq -er --arg t "$BASE_TITLE" \
  '.validators[] | select(.title == $t) | .compiledCode' "$BLUEPRINT")"
[ "$CLEAN_CODE" = "$COMMITTED_CODE" ] \
  || red "clean rebuild does NOT reproduce committed compiledCode — committed blueprint is stale or toolchain drifted"
echo "   clean rebuild reproduces committed compiledCode byte-for-byte"

echo "== Leg 3: mutant build through the real pipeline =="
VALIDATOR="$WORKTREE/validators/programmable_logic_base.ak"
grep -q 'pairs.has_key_or_fail(stake_cred)' "$VALIDATOR" \
  || red "mutation anchor not found in $VALIDATOR — validator changed; update this control"
perl -0pi -e 's/self\.withdrawals \|> pairs\.has_key_or_fail\(stake_cred\)/True/' "$VALIDATOR"
grep -q 'pairs.has_key_or_fail(stake_cred)' "$VALIDATOR" \
  && red "mutation did not apply"
(cd "$WORKTREE" && aiken build 2>/dev/null) || red "mutant 'aiken build' failed"
MUTANT_CODE="$(jq -er --arg t "$BASE_TITLE" \
  '.validators[] | select(.title == $t) | .compiledCode' "$WORKTREE/plutus.json")"
[ "$MUTANT_CODE" != "$CLEAN_CODE" ] \
  || red "mutant compiledCode identical to clean — mutation never reached the artifact under test"
mkdir -p "$(dirname "$MUTANT_FLAT")"
printf '%s' "$MUTANT_CODE" > "$MUTANT_FLAT"
echo "   mutant differs from clean ($((${#MUTANT_CODE} / 2)) vs $((${#CLEAN_CODE} / 2)) bytes)"

echo "== Leg 4: Lean control — theorem must be FALSIFIED on the mutant =="
(cd "$FV" && lake build >/dev/null && lake env lean controls/MutantControl.lean) \
  || red "MutantControl failed — either the theorem was NOT falsified (harness cannot distinguish broken code) or the control could not evaluate"
echo "   Falsified as expected + mutant accepts the rejected context (kernel-checked)"

echo "== Leg 5: restore + baseline re-verification =="
cleanup
trap - EXIT
"$FV/scripts/extract-flats.sh" --check || red "baseline flats no longer fresh after control"
(cd "$FV" && lake build >/dev/null) || red "clean lake build broken after control"
echo "   baseline green"

echo "ALL LEGS GREEN — the pipeline has been shown able to fail."
