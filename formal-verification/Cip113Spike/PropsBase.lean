/-
Tier-1, step 3: first theorems over the compiled Aiken bytecode of
`programmable_logic_base` (template: WSC/Props/P3_Base.lean).

The Aiken base validator IGNORES its redeemer and scans the withdrawal
map for the `stake_cred` parameter (`pairs.has_key_or_fail`) — the same
forwarding shape as wsc-poc's PRE-#112 base, so unlike Phil's post-#112
campaign there is no redeemer-index residual here at all.

Three layers, per the wsc methodology:
 1. `exec_accepts` — concrete accepting witness (non-vacuity, real CEK,
    kernel-checked via `native_decide`).
 2. `exec_rejects_foreign_withdrawal` — concrete rejecting witness
    (polarity control, also kernel-checked).
 3. `base_forces_plg_withdrawal_one_entry` — the P3-analogue, SYMBOLIC
    over the withdrawal entry: for a one-entry withdrawal map with a
    symbolic script-credential hash and a symbolic amount, acceptance
    FORCES the hash to be the deployment parameter's. Discharged
    `by blaster` (Z3) — subject to the known `admit` caveat, printed by
    `#print axioms` at the bottom.
-/
import Cip113Spike.PrepBase
import Blaster

namespace CIP113

open CardanoLedgerApi.V2 (TxOut)
open CardanoLedgerApi.V3 (Credential ScriptContext TxOutRef Withdrawals)
open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Utils (isSuccessful isUnsuccessful)

set_option maxHeartbeats 0

/-- The PLG withdraw-0 credential the script is parameterised with. -/
def stakeCred : Credential := .ScriptCredential (ByteString.mk "PLG")

def outRef : TxOutRef := ⟨ByteString.mk "", 0⟩

/-- Ada-only canonical value (lovelace-first, positive): 100 lovelace. -/
def value : CardanoLedgerApi.V1.Value.Value :=
  [(Data.B (ByteString.mk ""), Data.Map [(Data.B (ByteString.mk ""), Data.I 100)])]

/-- The spent PLB UTxO (script payment credential, no datum). -/
def resolved : TxOut :=
  { txOutAddress := ⟨.ScriptCredential (ByteString.mk "BASE"), none⟩
  , txOutValue := value
  , txOutDatum := .NoOutputDatum
  , txOutReferenceScript := none }

/-- Validity interval [0, 1], both bounds finite and closed. -/
def range : Data :=
  Data.Constr 0 [ Data.Constr 0 [Data.Constr 1 [Data.I 0], Data.Constr 1 []]
                , Data.Constr 0 [Data.Constr 1 [Data.I 1], Data.Constr 1 []] ]

/-- Our base validator never reads its redeemer; a unit-like constr. -/
def rdmr : Data := Data.Constr 0 []

/-- Concrete spending context parameterised by its withdrawal map:
spends `resolved`, burns the 100 lovelace as fee (balanced). -/
def mkCtx (wdrl : Withdrawals) : ScriptContext :=
  { scriptContextTxInfo :=
    { txInfoInputs := [⟨outRef, resolved⟩]
    , txInfoReferenceInputs := []
    , txInfoOutputs := []
    , txInfoFee := 100
    , txInfoMint := []
    , txInfoTxCerts := []
    , txInfoWdrl := wdrl
    , txInfoValidRange := range
    , txInfoSignatories := []
    , txInfoRedeemers := [(.Spending outRef, rdmr)]
    , txInfoData := []
    , txInfoId := ByteString.mk ""
    , txInfoVotes := []
    , txInfoProposalProcedures := []
    -- C4: `Maybe Lovelace` fields — the V3 encoder maps `Nothing` to
    -- `Constr 1 []`; bare `Data.I 1` is outside the encoder image, so no
    -- ledger-produced context would carry it. Use the encodable `Nothing`.
    , txInfoCurrentTreasuryAmount := Data.Constr 1 []
    , txInfoTreasuryDonation := Data.Constr 1 [] }
  , scriptContextRedeemer := rdmr
  , scriptContextScriptInfo := .SpendingScript outRef none }

/-- Accepting witness: the withdrawal map holds exactly the parameter
credential (the withdraw-zero pattern). -/
def ctx : ScriptContext := mkCtx [(stakeCred, 0)]

/-- A foreign credential for the rejecting control. -/
def eveCred : Credential := .ScriptCredential (ByteString.mk "EVE")

/-- Boolean reflection of CEK success, so concrete runs are decidable
(`isSuccessful` itself is a Prop with no Decidable instance) — the
wsc-poc `isHaltB` idiom. -/
def isHaltB : PlutusCore.UPLC.CekMachine.State → Bool
  | .Halt _ => true
  | _ => false

theorem isHaltB_sound (s : PlutusCore.UPLC.CekMachine.State) :
    isHaltB s = true → isSuccessful s := by
  intro h; cases s <;> simp [isHaltB] at h <;> trivial

-- 1. Non-vacuity: the real CEK accepts the witness (kernel-checked).
theorem exec_accepts : isSuccessful (appliedBase.exec stakeCred ctx) :=
  isHaltB_sound _ (by native_decide)

-- 2. Polarity control: a withdrawal map holding only a FOREIGN
-- credential does NOT reach the success state (kernel-checked).
theorem exec_rejects_foreign_withdrawal :
    isHaltB (appliedBase.exec stakeCred (mkCtx [(eveCred, 0)])) = false := by
  native_decide

-- ===================================================================
-- Batch-2 PLB witnesses / controls (all kernel-checked, native_decide,
-- budget 600). Each rejecting run has an accepting twin one field away
-- (R1); each ∀-family gets a last-slot witness (R2); redeemer/range
-- independence is witness-set, never an implication (R2b).
-- ===================================================================

-- C11 / V5 / S-2 — NON-SPEND PURPOSE REJECTED. Same accepting skeleton
-- as `ctx`, one field changed: the script purpose is Rewarding, not
-- Spending. The PLB is a spend validator; the ledger never invokes it
-- under a rewarding purpose, and the harness models exactly that — the
-- purpose-gated `spendingInputs` feeds the spend-shaped application
-- `Term.Error` for any non-spending `scriptContextScriptInfo`, so the
-- run cannot reach Halt. Honest scope per R1: this pins the ledger
-- DISPATCH gate (a spend script is unreachable under a reward purpose),
-- not an in-body `else`-arm; the localisation is the one-field delta
-- against `exec_accepts` (the twin), which DOES reach Halt.
def ctxRewarding : ScriptContext :=
  { mkCtx [(stakeCred, 0)] with
    scriptContextScriptInfo := .RewardingScript stakeCred }

theorem exec_rejects_nonspend_purpose :
    isHaltB (appliedBase.exec stakeCred ctxRewarding) = false := by
  native_decide

-- C9 / V5b / S-3 — CREDENTIAL-TAG CONFUSION REJECTED. The sole
-- withdrawal entry keys a VerificationKeyCredential whose 28 bytes are
-- the SAME as the script param ("PLG"), only the constructor tag
-- differs. Pins that the compiled credential equality is tag-sensitive:
-- a vkey-tagged entry with the right bytes is NOT the script param.
-- Twin = `exec_accepts` (same bytes, ScriptCredential tag → accepts).
def vkeyTaggedParam : Credential := .PubKeyCredential (ByteString.mk "PLG")

theorem exec_rejects_vkey_tagged_param :
    isHaltB (appliedBase.exec stakeCred (mkCtx [(vkeyTaggedParam, 0)])) = false := by
  native_decide

-- C10 / R2 — PER-RUNG NON-VACUITY WITNESSES for the 2- and 4-entry
-- ladder rungs, with the param credential in the LAST slot (exercises
-- full scan depth, not a first-hit short-circuit). These inhabit the
-- families that `base_forces_plg_withdrawal_{two,four}_entries` quantify.
theorem exec_accepts_two_entries :
    isSuccessful
      (appliedBase.exec stakeCred (mkCtx [(eveCred, 0), (stakeCred, 0)])) :=
  isHaltB_sound _ (by native_decide)

theorem exec_accepts_four_entries :
    isSuccessful
      (appliedBase.exec stakeCred
        (mkCtx
          [ (eveCred, 0)
          , (.ScriptCredential (ByteString.mk "A"), 0)
          , (.ScriptCredential (ByteString.mk "B"), 0)
          , (stakeCred, 0) ])) :=
  isHaltB_sound _ (by native_decide)

-- C1 — MULTI-INPUT FORWARDING (witness form, R2b-safe). Two PLB spend
-- inputs, everything else = accepting skeleton → accepts. The PLB reads
-- only `self.withdrawals` (ignores `_own_ref`/`_datum`), so the input
-- count is irrelevant; this is the inhabitant that shows the family with
-- N>1 inputs is non-empty (not an implication that a narrowing mutant
-- would survive).
def ctxTwoInputs : ScriptContext :=
  { mkCtx [(stakeCred, 0)] with
    scriptContextTxInfo :=
      { (mkCtx [(stakeCred, 0)]).scriptContextTxInfo with
        txInfoInputs := [⟨outRef, resolved⟩, ⟨⟨ByteString.mk "", 1⟩, resolved⟩] } }

theorem exec_accepts_two_inputs :
    isSuccessful (appliedBase.exec stakeCred ctxTwoInputs) :=
  isHaltB_sound _ (by native_decide)

-- C6 / S-22 — REDEEMER INDEPENDENCE (witness-set form, R2b). The PLB
-- ignores its redeemer; stating that as `∀ r, accepts → P` is vacuously
-- satisfiable by a narrowing mutant (R2b), so instead we exhibit
-- accepting witnesses at three DISCRIMINATING redeemer shapes. The
-- redeemer sits in three ctx slots (scriptContextRedeemer + the Spending
-- entry of txInfoRedeemers); we vary all consistently.
def mkCtxRdmr (r : Data) : ScriptContext :=
  { mkCtx [(stakeCred, 0)] with
    scriptContextRedeemer := r
    scriptContextTxInfo :=
      { (mkCtx [(stakeCred, 0)]).scriptContextTxInfo with
        txInfoRedeemers := [(.Spending outRef, r)] } }

theorem exec_accepts_redeemer_constr1 :
    isSuccessful (appliedBase.exec stakeCred (mkCtxRdmr (Data.Constr 1 [Data.I 0]))) :=
  isHaltB_sound _ (by native_decide)

theorem exec_accepts_redeemer_bytes :
    isSuccessful (appliedBase.exec stakeCred (mkCtxRdmr (Data.B (ByteString.mk "")))) :=
  isHaltB_sound _ (by native_decide)

theorem exec_accepts_redeemer_nested :
    isSuccessful
      (appliedBase.exec stakeCred
        (mkCtxRdmr
          (Data.Constr 0
            [Data.List [Data.Constr 2 [Data.I 7, Data.B (ByteString.mk "z")]],
             Data.Map [(Data.I 1, Data.Constr 3 [])]]))) :=
  isHaltB_sound _ (by native_decide)

-- V10 / S-24 — VALIDITY-RANGE INDEPENDENCE (witness-pair form, R2b).
-- `mkCtx` bakes a fixed `range`; here a structurally different validity
-- range (an open-below, unbounded-above interval — different bounds AND
-- different finiteness) still accepts. Together with `exec_accepts` this
-- is the witness-pair form of range-independence at the concrete tier.
-- The base prep does NOT expose range as a leaf argument, so the full
-- relational SMT rung `accepts(ctx,r1) ↔ accepts(ctx,r2)` is DEFERRED
-- (would require reshaping the base prep — out of scope for this batch).
def rangeVariant : Data :=
  Data.Constr 0 [ Data.Constr 0 [Data.Constr 0 [], Data.Constr 1 []]
                , Data.Constr 0 [Data.Constr 2 [], Data.Constr 1 []] ]

def ctxRangeVariant : ScriptContext :=
  { mkCtx [(stakeCred, 0)] with
    scriptContextTxInfo :=
      { (mkCtx [(stakeCred, 0)]).scriptContextTxInfo with
        txInfoValidRange := rangeVariant } }

theorem exec_accepts_range_variant :
    isSuccessful (appliedBase.exec stakeCred ctxRangeVariant) :=
  isHaltB_sound _ (by native_decide)

-- C14(iii) — HALT VALUE IS UNIT. The v1.1.22 PlutusV3 wrapper returns
-- the unit constant on acceptance (confirmed by `fromHaltState`:
-- `some (.VCon .Unit)`), matching the CIP-117 requirement. `isHaltB`
-- alone accepts ANY `.Halt _`; this pins the actual returned value.
-- `CekValue` derives only `Repr` (no `DecidableEq`), so we reflect
-- "the Halt value is the unit constant" through a Bool matcher — the
-- same reflection idiom as `isHaltB` — and prove it `= true` by
-- `native_decide`, then discharge the propositional equality.
def haltIsUnitB : PlutusCore.UPLC.CekMachine.State → Bool
  | .Halt (.VCon .Unit) => true
  | _ => false

theorem haltIsUnitB_sound (s : PlutusCore.UPLC.CekMachine.State) :
    haltIsUnitB s = true →
    PlutusCore.UPLC.Utils.fromHaltState s = some (.VCon .Unit) := by
  intro h
  cases s with
  | Halt cv =>
    cases cv with
    | VCon c => cases c <;> simp_all [haltIsUnitB, PlutusCore.UPLC.Utils.fromHaltState]
    | _ => simp [haltIsUnitB] at h
  | _ => simp [haltIsUnitB] at h

theorem exec_accepts_unit :
    PlutusCore.UPLC.Utils.fromHaltState (appliedBase.exec stakeCred ctx)
      = some (.VCon .Unit) :=
  haltIsUnitB_sound _ (by native_decide)

-- 3. THE P3-ANALOGUE, symbolic — and universally quantified over the
-- DEPLOYMENT PARAMETER itself (the cardano-mpfs-onchain PR #51 idiom):
-- for EVERY parameterisation of the script and every one-entry
-- withdrawal map (symbolic credential hash, symbolic amount),
-- acceptance forces the entry's hash to equal the parameter's. This is
-- the forwarding guarantee of the whole PLB, proven for all
-- deployments at once: no PLG withdrawal, no spend.
set_option warn.sorry false in
theorem base_forces_plg_withdrawal_one_entry :
    ∀ (param h : ByteString) (amt : Int),
      isSuccessful
        (appliedBase.prop (.ScriptCredential param)
          (mkCtx [(.ScriptCredential h, amt)])) →
      h = param := by
  blaster (timeout: 900)

-- 4. THE ENTRY-COUNT LADDER — probing the wsc `WdrlPairShaped` cliff on
-- our bytecode. Phil's post-#112 base validator INDEXES the withdrawal
-- map (`pdropList` on a symbolic index): 1- and 2-entry maps prove, 3+
-- do not. Our base validator SCANS (`pairs.has_key_or_fail`), a
-- Blaster-friendlier shape; these rungs measure how far it climbs. Our
-- unfracking composition carries FOUR withdrawals, so rung 4 is the one
-- that matters.

set_option warn.sorry false in
theorem base_forces_plg_withdrawal_two_entries :
    ∀ (param h1 h2 : ByteString) (a1 a2 : Int),
      isSuccessful
        (appliedBase.prop (.ScriptCredential param)
          (mkCtx
            [(.ScriptCredential h1, a1), (.ScriptCredential h2, a2)])) →
      (h1 = param ∨ h2 = param) := by
  blaster (timeout: 900)

set_option warn.sorry false in
theorem base_forces_plg_withdrawal_four_entries :
    ∀ (param h1 h2 h3 h4 : ByteString) (a1 a2 a3 a4 : Int),
      isSuccessful
        (appliedBase.prop (.ScriptCredential param)
          (mkCtx
            [ (.ScriptCredential h1, a1), (.ScriptCredential h2, a2)
            , (.ScriptCredential h3, a3), (.ScriptCredential h4, a4)
            ])) →
      (h1 = param ∨ h2 = param ∨ h3 = param ∨ h4 = param) := by
  blaster (timeout: 1800)

-- Claim-integrity gate (C12/V20): pin the axiom set of each disposition
-- class so `lake build` goes RED on drift (a stray `sorry` surfaces
-- `sorryAx`; an accidental `native_decide`/`blaster` swap changes the
-- axiom list). Whitespace is normalized, so the wrapped pretty-printer
-- output is compared as a single line.
--   KERNEL-PROVED (native_decide): ofReduceBool + trustCompiler present.
/-- info: 'CIP113.exec_accepts' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts
--   SMT-VALID (blaster): blasterProven present, no reduce/compiler axioms.
/-- info: 'CIP113.base_forces_plg_withdrawal_one_entry' depends on axioms: [propext, Classical.choice, Quot.sound, Blaster.Tactic.blasterProven] -/
#guard_msgs(whitespace := lax) in #print axioms base_forces_plg_withdrawal_one_entry
/-- info: 'CIP113.base_forces_plg_withdrawal_four_entries' depends on axioms: [propext, Classical.choice, Quot.sound, Blaster.Tactic.blasterProven] -/
#guard_msgs(whitespace := lax) in #print axioms base_forces_plg_withdrawal_four_entries

end CIP113
