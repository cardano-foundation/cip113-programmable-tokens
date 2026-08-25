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
#     acceptance check — the witnessed-withdrawal equality shared by all
#     three dispatch arms, `(witnessed == cred_of(fields))?` -> `True` —
#     rebuild through the REAL pipeline, extract the mutant flat, assert
#     it differs from the clean flat (the mutation reached the artifact
#     under test).
#  4. Lean control: `controls/MutantControl.lean` must show NINE theorems
#     that are green in `Cip113Spike/PropsBase.lean` come back FALSE on
#     the mutant (the six dispatch mismatches, the foreign withdrawal,
#     the vkey-tagged delegate, the wrong `wdrl_idx`), the mutant still
#     ACCEPTING the three contexts the clean artifact accepts, and the
#     five rejections the mutation does not reach unchanged. All
#     kernel-checked.
#  4b. AUTH mutant (V4/S-16): DECLARED SKIP — the theorem it falsified
#     was removed by the PLG dissolution (#110) and the `transfer`
#     artifact has no theorems yet. The mutation anchor in transfer.ak is
#     still checked so drift surfaces now; see the leg for the recipe.
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
# Post-#110/#114 PLB has no `stake_cred`/`has_key_or_fail` forwarding check
# left (that shape belonged to the dissolved programmable_logic_global
# coordinator) — its only acceptance test is now the witnessed-withdrawal
# equality shared by all three dispatch arms (SpendViaTransfer /
# SpendViaThirdParty / SpendViaUnfracking): `(witnessed == cred_of(fields))?`.
# Gutting that one comparison to `True` is the same strategy as before
# (blank out the base validator's only check) against the current body.
grep -q 'witnessed == cred_of(fields)' "$VALIDATOR" \
  || red "mutation anchor not found in $VALIDATOR — validator changed; update this control"
perl -0pi -e 's/witnessed == cred_of\(fields\)/True/' "$VALIDATOR"
grep -q 'witnessed == cred_of(fields)' "$VALIDATOR" \
  && red "mutation did not apply"
(cd "$WORKTREE" && aiken build 2>/dev/null) || red "mutant 'aiken build' failed"
MUTANT_CODE="$(jq -er --arg t "$BASE_TITLE" \
  '.validators[] | select(.title == $t) | .compiledCode' "$WORKTREE/plutus.json")"
[ "$MUTANT_CODE" != "$CLEAN_CODE" ] \
  || red "mutant compiledCode identical to clean — mutation never reached the artifact under test"
mkdir -p "$(dirname "$MUTANT_FLAT")"
printf '%s' "$MUTANT_CODE" > "$MUTANT_FLAT"
echo "   mutant differs from clean ($((${#MUTANT_CODE} / 2)) vs $((${#CLEAN_CODE} / 2)) bytes)"

echo "== Leg 4: Lean control — theorems must be FALSIFIED on the mutant =="
(cd "$FV" && lake build >/dev/null && lake env lean controls/MutantControl.lean) \
  || red "MutantControl failed — either the theorems were NOT falsified (harness cannot distinguish broken code) or the control could not evaluate"
echo "   9 PropsBase rejections flip to acceptances on the mutant; the 3 acceptances survive; the 5 rejections the mutation does not reach are unchanged (all kernel-checked)"

echo "== Leg 4b: AUTH mutant (V4/S-16) — DECLARED SKIP =="
# A SECOND, independent seeded bug on a DISTINCT invariant: the per-input
# owner-authorisation `expect` in transfer.ak's `collect_input_assets`
# gated to fire ONLY for the first transaction input — the
# "auth-first-input-only" hole Paolo's V4 observation targets, which every
# SINGLE-input control passes.
#
# THIS LEG IS SKIPPED, and the skip is declared rather than silent. A
# falsification control can only falsify a theorem that EXISTS, and the
# theorem this one falsified (`PropsGlobalAuth.lean`, two-owner
# authorisation on the compiled coordinator) was removed by the PLG
# dissolution (#110). The logic it targets is unchanged and now compiles
# into the standalone `transfer` withdraw-0 validator, but that artifact
# has no accepting context, no `#prep_uplc`, and no theorems yet — see
# `Cip113Spike/PrepTransfer.lean`. `controls/AuthMutantControl.lean` is
# preserved verbatim and stays outside the `lean_lib` globs until the
# `transfer` slice gives it something to falsify; restoring this leg is
# that slice's job, using the recipe below and the pattern of leg 3/4.
#
# What IS still checked here: that the mutation anchor is where the
# recipe expects it. If `transfer.ak` drifts, that must surface now
# rather than when the leg is restored.
TRANSFER="$REPO/validators/programmable_logic/transfer.ak"
grep -q 'expect _stake_cred = authorised_stake_cred(' "$TRANSFER" \
  || red "auth mutation anchor not found in $TRANSFER — validator changed; update controls/AuthMutantControl.lean and this recipe"
# Recipe, for the slice that restores the leg: in a FRESH worktree,
#   perl -0pi -e 's/expect _stake_cred = authorised_stake_cred\(\s*output\.address,\s*has_signatory,\s*has_withdrawal,\s*\)/if input.output_reference == list.head(tx.inputs).output_reference {\n          expect _stake_cred = authorised_stake_cred(\n            output.address,\n            has_signatory,\n            has_withdrawal,\n          )\n        } else {\n          Void\n        }/'
# then `aiken build`, extract title `transfer.transfer.withdraw` into
# `controls/flats/transfer_mutant.flat`, assert it differs from
# `flats/transfer.flat`, and require the CLEAN-rejected two-owner context
# to be ACCEPTED by the mutant.
echo "   SKIPPED — no transfer theorem to falsify yet (see comment); anchor still present"

echo "== Leg 5: restore + baseline re-verification =="
cleanup
trap - EXIT
"$FV/scripts/extract-flats.sh" --check || red "baseline flats no longer fresh after control"
(cd "$FV" && lake build >/dev/null) || red "clean lake build broken after control"
echo "   baseline green"

echo "ALL LEGS GREEN — the pipeline has been shown able to fail."
