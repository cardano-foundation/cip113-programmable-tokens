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

-- Blaster closes Valid goals via `admit`; the warning is expected.
set_option warn.sorry false
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
    , txInfoCurrentTreasuryAmount := Data.I 1
    , txInfoTreasuryDonation := Data.I 1 }
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

-- 3. THE P3-ANALOGUE, symbolic — and universally quantified over the
-- DEPLOYMENT PARAMETER itself (the cardano-mpfs-onchain PR #51 idiom):
-- for EVERY parameterisation of the script and every one-entry
-- withdrawal map (symbolic credential hash, symbolic amount),
-- acceptance forces the entry's hash to equal the parameter's. This is
-- the forwarding guarantee of the whole PLB, proven for all
-- deployments at once: no PLG withdrawal, no spend.
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

theorem base_forces_plg_withdrawal_two_entries :
    ∀ (param h1 h2 : ByteString) (a1 a2 : Int),
      isSuccessful
        (appliedBase.prop (.ScriptCredential param)
          (mkCtx
            [(.ScriptCredential h1, a1), (.ScriptCredential h2, a2)])) →
      (h1 = param ∨ h2 = param) := by
  blaster (timeout: 900)

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

#print axioms exec_accepts
#print axioms base_forces_plg_withdrawal_one_entry
#print axioms base_forces_plg_withdrawal_four_entries

end CIP113
