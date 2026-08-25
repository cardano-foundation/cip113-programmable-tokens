/-
FALSIFICATION CONTROL — this file must NEVER be part of the default
`lake build`. It is run only by `scripts/falsification-control.sh`,
against a MUTANT artifact that script builds through the real Aiken
pipeline (mutated source → `aiken build` → extracted `compiledCode` →
`controls/flats/`, a gitignored directory that is normally absent).

WHY IT EXISTS. A green theorem in `Cip113Spike/PropsBase.lean` is not
evidence until the harness has been shown able to go RED. This tree has
already been green and meaningless once: `#prep_uplc` fuel of 600 was
carried against an artifact needing ≥1168, so every accepting run came
back `State.Error` — indistinguishable from a rejection — which made
every acceptance theorem unprovable and every rejection theorem
trivially true. Nothing in a passing build says so. Only a control does.

THE MUTATION. `programmable_logic_base`'s only acceptance test is the
witnessed-withdrawal equality shared by all three dispatch arms:

    let Pair(witnessed, _) = list.expect_at(self.withdrawals, wdrl_idx)
    (witnessed == cred_of(fields))?

The driver rewrites `witnessed == cred_of(fields)` to `True` and rebuilds.
The mutant therefore accepts whenever it gets THAT FAR — i.e. whenever
the params reference input authenticates AND carries an inline datum AND
`wdrl_idx` resolves — and its custody guarantee is gone.

EXPECTED OUTCOMES (anything else is a failure OF THE HARNESS):

 1. Every clean-artifact REJECTION that the equality is responsible for
    must FLIP to an acceptance here. That is nine of them: the six
    off-diagonal entries of the dispatch matrix, the foreign-withdrawal
    rejection, the vkey-tag rejection, and the wrong-`wdrl_idx`
    rejection. Each is stated below as a kernel-checked `= true`, so the
    corresponding `exec_rejects_*` theorem is demonstrably FALSE against
    this artifact.

 2. The mutant must still ACCEPT the contexts the clean artifact accepts
    — otherwise it is a brick rather than a broken validator, and the
    flips above would prove nothing about the equality in particular.

 3. The rejections the mutation does NOT reach must be UNCHANGED. Five
    of the clean theorems rest on other checks entirely — the params-NFT
    presence test, the inline-datum test, `list.expect_at`'s own bounds,
    and the ledger's purpose dispatch — and this mutant leaves all four
    standing. Asserting that here is what keeps the control honest: it
    says exactly which theorems this leg does and does not control.
    Their own mutants are a later slice, listed at the bottom.

WHY CONCRETE AND NOT `#blaster (solve-result: 1)`. The pre-#110 version
of this file falsified SMT-quantified forwarding lemmas. `PropsBase.lean`
discharges no quantified claim yet (its preps are concrete — see that
module's header for why), so there is nothing for Z3 to falsify. A
kernel-checked polarity flip on the exact context a clean theorem names
is stronger evidence anyway, and it costs seconds rather than minutes.

IDENTITY: same toolchain + variant discipline as the clean build — the
driver script verifies `aiken --version` against the blueprint preamble
and that the mutant flat differs from the clean one before this file
runs. BuiltinSemanticsVariant E via `cekExecuteProgram`'s pinned default
(see `Cip113Spike/PrepBase.lean`). FUEL 1600, the same budget
`PropsBase.lean` uses, so the two artifacts are compared under identical
conditions; the mutant's own largest accepting step count is 1188
(measured the same way as the clean one, `scripts/fuel-probe.lean`), so
1600 is ample for it.
-/
import Cip113Spike.PropsBase
import Blaster

namespace CIP113.Control

open PlutusCore.UPLC.Term (Term)
open CIP113

set_option maxHeartbeats 0
set_option maxRecDepth 8000

#import_uplc programmableLogicBaseMutant PlutusV3 single_cbor_hex "controls/flats/programmable_logic_base_mutant.flat"

-- The SAME contexts `Cip113Spike/PropsBase.lean` names, re-prepped
-- against the mutant artifact. Nothing about the transaction changes;
-- only the bytes under test do.
def mutTransferAt0 : List Term := baseInputs paramsPolicy ctxTransferAt0
def mutTransferAt1 : List Term := baseInputs paramsPolicy ctxTransferAt1
def mutTransferAt2 : List Term := baseInputs paramsPolicy ctxTransferAt2
def mutThirdPartyAt0 : List Term := baseInputs paramsPolicy ctxThirdPartyAt0
def mutThirdPartyAt1 : List Term := baseInputs paramsPolicy ctxThirdPartyAt1
def mutThirdPartyAt2 : List Term := baseInputs paramsPolicy ctxThirdPartyAt2
def mutUnfrackingAt0 : List Term := baseInputs paramsPolicy ctxUnfrackingAt0
def mutUnfrackingAt1 : List Term := baseInputs paramsPolicy ctxUnfrackingAt1
def mutUnfrackingAt2 : List Term := baseInputs paramsPolicy ctxUnfrackingAt2
def mutForeignOnly : List Term := baseInputs paramsPolicy ctxForeignOnly
def mutVkeyTaggedDelegate : List Term := baseInputs paramsPolicy ctxVkeyTaggedDelegate
def mutFourEntryAt3 : List Term := baseInputs paramsPolicy ctxFourEntryAt3
def mutWdrlIdxOutOfRange : List Term := baseInputs paramsPolicy ctxWdrlIdxOutOfRange
def mutUnauthenticatedParams : List Term := baseInputs paramsPolicy ctxUnauthenticatedParams
def mutParamsWithoutDatum : List Term := baseInputs paramsPolicy ctxParamsWithoutDatum
def mutParamsIdx0 : List Term := baseInputs paramsPolicy ctxParamsIdx0
def mutRewardingPurpose : List Term := baseInputs paramsPolicy ctxRewardingPurpose

#prep_uplc mTransferAt0 programmableLogicBaseMutant mutTransferAt0 1600
#prep_uplc mTransferAt1 programmableLogicBaseMutant mutTransferAt1 1600
#prep_uplc mTransferAt2 programmableLogicBaseMutant mutTransferAt2 1600
#prep_uplc mThirdPartyAt0 programmableLogicBaseMutant mutThirdPartyAt0 1600
#prep_uplc mThirdPartyAt1 programmableLogicBaseMutant mutThirdPartyAt1 1600
#prep_uplc mThirdPartyAt2 programmableLogicBaseMutant mutThirdPartyAt2 1600
#prep_uplc mUnfrackingAt0 programmableLogicBaseMutant mutUnfrackingAt0 1600
#prep_uplc mUnfrackingAt1 programmableLogicBaseMutant mutUnfrackingAt1 1600
#prep_uplc mUnfrackingAt2 programmableLogicBaseMutant mutUnfrackingAt2 1600
#prep_uplc mForeignOnly programmableLogicBaseMutant mutForeignOnly 1600
#prep_uplc mVkeyTaggedDelegate programmableLogicBaseMutant mutVkeyTaggedDelegate 1600
#prep_uplc mFourEntryAt3 programmableLogicBaseMutant mutFourEntryAt3 1600
#prep_uplc mWdrlIdxOutOfRange programmableLogicBaseMutant mutWdrlIdxOutOfRange 1600
#prep_uplc mUnauthenticatedParams programmableLogicBaseMutant mutUnauthenticatedParams 1600
#prep_uplc mParamsWithoutDatum programmableLogicBaseMutant mutParamsWithoutDatum 1600
#prep_uplc mParamsIdx0 programmableLogicBaseMutant mutParamsIdx0 1600
#prep_uplc mRewardingPurpose programmableLogicBaseMutant mutRewardingPurpose 1600

-- ===================================================================
-- Control 1 — THE NINE FLIPS. Each line below is the negation of a
-- theorem that is green in `Cip113Spike/PropsBase.lean`, on the very
-- same context. If any of these failed to compile, the harness could
-- not tell PLB from a PLB with its custody check deleted, and every
-- `exec_rejects_*` claim in this tree would be worthless.
-- ===================================================================

-- 1a. The dispatch matrix collapses: with the equality gone, the arm and
-- the witnessed withdrawal no longer have to agree, so all six
-- mismatches spend. Falsifies exec_rejects_{transfer,third_party,
-- unfracking}_arm_at_*.
theorem mutant_accepts_transfer_arm_at_third_party_delegate :
    isHaltB mTransferAt0.exec = true := by native_decide

theorem mutant_accepts_transfer_arm_at_unfracking_delegate :
    isHaltB mTransferAt2.exec = true := by native_decide

theorem mutant_accepts_third_party_arm_at_transfer_delegate :
    isHaltB mThirdPartyAt1.exec = true := by native_decide

theorem mutant_accepts_third_party_arm_at_unfracking_delegate :
    isHaltB mThirdPartyAt2.exec = true := by native_decide

theorem mutant_accepts_unfracking_arm_at_third_party_delegate :
    isHaltB mUnfrackingAt0.exec = true := by native_decide

theorem mutant_accepts_unfracking_arm_at_transfer_delegate :
    isHaltB mUnfrackingAt1.exec = true := by native_decide

-- 1b. Custody escapes the protocol entirely: a transaction in which NO
-- delegate withdraws at all now spends a programmable-token UTxO.
-- Falsifies exec_rejects_foreign_withdrawal.
theorem mutant_accepts_foreign_withdrawal :
    isHaltB mForeignOnly.exec = true := by native_decide

-- 1c. Tag sensitivity is gone: the delegate's 28 bytes under a
-- verification-key credential now pass. Falsifies
-- exec_rejects_vkey_tagged_delegate.
theorem mutant_accepts_vkey_tagged_delegate :
    isHaltB mVkeyTaggedDelegate.exec = true := by native_decide

-- 1d. `wdrl_idx` stops being self-validating: an index addressing an
-- unrelated withdrawal of the same transaction now spends. Falsifies
-- exec_rejects_wdrl_idx_at_foreign_withdrawal.
theorem mutant_accepts_wdrl_idx_at_foreign_withdrawal :
    isHaltB mFourEntryAt3.exec = true := by native_decide

-- ===================================================================
-- Control 2 — the mutant is BROKEN, not BRICKED. It still accepts the
-- three contexts the clean artifact accepts, so the flips above isolate
-- the deleted equality rather than reflecting an artifact that halts on
-- everything for some unrelated reason.
-- ===================================================================

theorem mutant_still_accepts_transfer_arm :
    isHaltB mTransferAt1.exec = true := by native_decide

theorem mutant_still_accepts_third_party_arm :
    isHaltB mThirdPartyAt0.exec = true := by native_decide

theorem mutant_still_accepts_unfracking_arm :
    isHaltB mUnfrackingAt2.exec = true := by native_decide

-- ===================================================================
-- Control 3 — SCOPE. The five clean rejections below do NOT rest on the
-- equality, and this mutant leaves them exactly as they were. Stating it
-- keeps the control from being read as covering more than it does: this
-- leg falsifies the nine theorems above and no others. Each of these
-- needs its own seeded bug before its clean theorem counts as
-- controlled — see the note at the bottom of this file.
-- ===================================================================

/-- `list.expect_at` still runs off the end of the map. -/
theorem mutant_still_rejects_out_of_range_wdrl_idx :
    isHaltB mWdrlIdxOutOfRange.exec = false := by native_decide

/-- The params-NFT presence test is a separate `expect`. -/
theorem mutant_still_rejects_unauthenticated_params_input :
    isHaltB mUnauthenticatedParams.exec = false := by native_decide

/-- So is the inline-datum test. -/
theorem mutant_still_rejects_params_input_without_inline_datum :
    isHaltB mParamsWithoutDatum.exec = false := by native_decide

/-- A wrong `params_idx` still fails the NFT test at the decoy. -/
theorem mutant_still_rejects_params_idx_at_non_params_reference_input :
    isHaltB mParamsIdx0.exec = false := by native_decide

/-- The purpose gate is the ledger's, not the validator's. -/
theorem mutant_still_rejects_nonspend_purpose :
    isHaltB mRewardingPurpose.exec = false := by native_decide

-- ===================================================================
-- Axiom pins, same discipline as the theorems this control falsifies:
-- every line is KERNEL-PROVED by `native_decide` over a concrete CEK
-- run of the MUTANT artifact.
-- ===================================================================

/-- info: 'CIP113.Control.mutant_accepts_transfer_arm_at_third_party_delegate' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms mutant_accepts_transfer_arm_at_third_party_delegate
/-- info: 'CIP113.Control.mutant_accepts_foreign_withdrawal' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms mutant_accepts_foreign_withdrawal
/-- info: 'CIP113.Control.mutant_still_accepts_transfer_arm' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms mutant_still_accepts_transfer_arm
/-- info: 'CIP113.Control.mutant_still_rejects_unauthenticated_params_input' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms mutant_still_rejects_unauthenticated_params_input

-- ===================================================================
-- STILL UNCONTROLLED, and therefore still unearned:
--
--  * the params-NFT presence check (mutate the `expect !dict.is_empty
--    (value.tokens …)` in `programmable_logic/params.ak` to `True`);
--  * the inline-datum check in the same function;
--  * `list.expect_at`'s bounds on `wdrl_idx`;
--  * the ledger purpose gate, which is not ours to mutate at all — a
--    control for `exec_rejects_nonspend_purpose` has to falsify the
--    HARNESS's dispatch (`spendingInputs`), not the validator.
--
-- `controls/AuthMutantControl.lean` is a different matter: it targets a
-- two-owner authorisation property that lived in the dissolved
-- `programmable_logic_global`, and its logic now compiles into the
-- standalone `transfer` withdraw-0 validator. It stays EXCLUDED from the
-- build and untouched until the `transfer` theorems exist for it to
-- falsify; `scripts/falsification-control.sh` skips its leg with the
-- same reason.
-- ===================================================================

end CIP113.Control
