/-
Stage-1 authorization theorems over the compiled `programmable_logic_global`
bytecode — the "every PLB input's owner must consent" property (V4 /
seed S-16, Paolo Veronelli's PR-101 review, Batch 3a).

Paolo's sharp observation: every existing control on the owner-auth
kernel (`authorised_stake_cred`) is SINGLE-INPUT. A bug that authorizes
only the FIRST input's owner and skips the rest passes every one of
them. The load-bearing context therefore has TWO PLB inputs with
DISTINCT owners where only the first is authorized: the clean bytes must
REJECT it, and a seeded auth-first-input-only mutant must ACCEPT it.

FAMILY T2 (single registered policy, TransferAct, TWO PLB inputs with
DISTINCT owner stake credentials, one PLB output carrying the SUM):

  reference inputs : [ params UTxO (as T1), registry node UTxO (as T1) ]
  inputs           : [ UTxO at Address(plbCred, owner1 stake) (polP, T, q1)
                     , UTxO at Address(plbCred, owner2 stake) (polP, T, q2) ]
  outputs          : [ UTxO at Address(plbCred, stake) (polP, T, q1+q2) ]
  withdrawals      : [(own PLG cred, 0), (T, 0)]  (+ owner2 script wdrl in
                     the script-owner flavour)
  extra_signatories: parameterized (which owners are authorized)
  mint             : empty
  redeemer         : TransferAct [TokenExists {node_idx: 1}]

CRUCIAL AIKEN SEMANTICS (read from lib/assets.ak + transfer.ak, not
guessed):

  * Two PLB inputs of the SAME policy AGGREGATE. `collect_input_assets`
    folds inputs through `assets.collect`, whose `union`/`do_insert`
    (lib/assets.ak:161-167) SUMS token quantities when the policy id
    matches (`k1 == k2 -> tokens.union`). So `input_assets` carries ONE
    entry `(polP, q1+q2)`, and `verify_proofs` needs exactly ONE proof
    for `polP` — the redeemer proof list stays `[TokenExists {1}]`,
    unchanged from T1. Conservation then requires the single PLB output
    to carry `>= q1+q2`; we set it to `q1+q2` so conservation is
    satisfied and AUTH is the only thing that can fail.

  * Owner auth is checked PER INPUT, INSIDE the collect strategy closure
    (transfer.ak:91-104): for every input whose payment credential is
    the PLB, `expect _ = authorised_stake_cred(output.address,
    has_signatory, has_withdrawal)` runs before `select(output)`. The
    `expect` short-circuits the whole validator, so BOTH owners are
    checked regardless of the value-level aggregation that happens
    afterwards. vkey owner => `list.has_or_fail(extra_signatories, pkh)`;
    script owner => `has_withdrawal(script_cred)` (withdraw-0 present).

CONTROLS (concrete raw execs at budget 4400 — SHAPED discipline: these
are `cekExecuteProgram` on the imported PLG over a hand-built input
list, exactly as `exec_rejects_no_transfer_logic`/`execNoTL` in
PropsGlobal.lean; concrete raw execs never touch the prep memory cliff):

  exec_accepts_two_owners_both_authorized  — signatories [owner1, owner2]
                               => ACCEPT (the twin, R1).
  exec_rejects_second_owner_unauthorized   — signatories [owner1] only
                               => REJECT (the load-bearing V4 control;
                               delta vs the twin = one signatory). This
                               is the context the S-16 mutant must ACCEPT.
  exec_accepts_script_owner_withdrawal     — owner2 is a SCRIPT-staked
                               owner, its withdraw-0 entry PRESENT
                               => ACCEPT.
  exec_rejects_script_owner_no_withdrawal  — same, owner2's withdrawal
                               entry ABSENT (delta = one withdrawal entry)
                               => REJECT.

All four are KERNEL-PROVED (`native_decide`, fuel 4400, variant E).
-/
import Cip113Spike.PropsGlobal
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class.IsData (toData)
open CardanoLedgerApi.V2 (TxOut)
open CardanoLedgerApi.V3 (Credential ScriptContext TxOutRef)
open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Utils (isSuccessful)
open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (rewardingInputs)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)

set_option maxHeartbeats 0
set_option maxRecDepth 65536

-- A second, DISTINCT owner (T1's `ownerKey` is owner 1). Vkey flavour.
def owner2Key : ByteString := ByteString.mk "OWNR2"

/-- Owner 2 as a vkey stake credential. -/
def vkeyStakeOwner2 : CardanoLedgerApi.V1.StakingCredential :=
  .StakingHash (.PubKeyCredential owner2Key)

-- Owner 2 as a SCRIPT stake credential (flavour 2). Distinct from every
-- other script hash in the T1 skeleton (BASE/PLGW/TLOG/…).
def owner2ScriptHash : ByteString := ByteString.mk "OWN2S"
def owner2ScriptCred : Credential := .ScriptCredential owner2ScriptHash
def scriptStakeOwner2 : CardanoLedgerApi.V1.StakingCredential :=
  .StakingHash owner2ScriptCred

def inRef2 : TxOutRef := ⟨ByteString.mk "", 3⟩

/-- The T2 family builder. Two PLB inputs with DISTINCT owner stake
credentials (`owner1Stake`, `owner2Stake`), each carrying `(polP, T, q1)`
and `(polP, T, q2)`; ONE PLB output carrying the SUM `q1+q2` (so
conservation holds and auth is the only remaining failure mode).
Authorization is fully parameterized: `sigs` is `txInfoSignatories` and
`wdrl` is `txInfoWdrl`, so every run shares one skeleton (R1). The
reference inputs, redeemer and the two mandatory withdrawals (own PLG +
transfer logic) live inside `wdrl` supplied by the caller. -/
def mkT2 (owner1Stake owner2Stake : CardanoLedgerApi.V1.StakingCredential)
    (q1 q2 : Int) (sigs : List ByteString)
    (wdrl : CardanoLedgerApi.V3.Withdrawals) : ScriptContext :=
  { scriptContextTxInfo :=
    { txInfoInputs :=
        [ ⟨inRef,
            { txOutAddress := ⟨plbCred, some owner1Stake⟩
            , txOutValue := valueWith polP tokenName q1
            , txOutDatum := .NoOutputDatum
            , txOutReferenceScript := none }⟩
        , ⟨inRef2,
            { txOutAddress := ⟨plbCred, some owner2Stake⟩
            , txOutValue := valueWith polP tokenName q2
            , txOutDatum := .NoOutputDatum
            , txOutReferenceScript := none }⟩ ]
    , txInfoReferenceInputs :=
        [ ⟨⟨ByteString.mk "", 1⟩, refOut paramsPolicy paramsDatum⟩
        , ⟨⟨ByteString.mk "", 2⟩, refOut registryCS nodeDatum⟩ ]
    , txInfoOutputs :=
        [ { txOutAddress := ⟨plbCred, some vkeyStakeOwner⟩
          , txOutValue := valueWith polP tokenName (q1 + q2)
          , txOutDatum := .NoOutputDatum
          , txOutReferenceScript := none } ]
    , txInfoFee := 500000
    , txInfoMint := []
    , txInfoTxCerts := []
    , txInfoWdrl := wdrl
    , txInfoValidRange := range
    , txInfoSignatories := sigs
    , txInfoRedeemers :=
        [ (.Spending inRef, Data.Constr 0 [])
        , (.Spending inRef2, Data.Constr 0 [])
        , (.Rewarding ownCred, transferRdmr)
        , (.Rewarding tlogCred, Data.I 0) ]
    , txInfoData := []
    , txInfoId := ByteString.mk ""
    , txInfoVotes := []
    , txInfoProposalProcedures := []
    , txInfoCurrentTreasuryAmount := Data.Constr 1 []
    , txInfoTreasuryDonation := Data.Constr 1 [] }
  , scriptContextRedeemer := transferRdmr
  , scriptContextScriptInfo := .RewardingScript ownCred }

/-- The two mandatory withdrawals shared by every T1/T2 accepting run:
the own PLG cred (withdraw-0 entry point) and the transfer-logic script
`tlogCred` (the substandard the registry node names). -/
def baseWdrl : CardanoLedgerApi.V3.Withdrawals := [(ownCred, 0), (tlogCred, 0)]

/-- Concrete raw exec of the imported PLG on the hand-built T2 input list
(no prep — this is `cekExecuteProgram` on the imported script, mirroring
`execNoTL`/`t1Inputs`). -/
def execT2 (owner1Stake owner2Stake : CardanoLedgerApi.V1.StakingCredential)
    (q1 q2 : Int) (sigs : List ByteString)
    (wdrl : CardanoLedgerApi.V3.Withdrawals) :
    PlutusCore.UPLC.CekMachine.State :=
  cekExecuteProgram programmableLogicGlobal.script
    (toTerm paramsPolicy ::
      rewardingInputs (mkT2 owner1Stake owner2Stake q1 q2 sigs wdrl)) 4400

-- ===================================================================
-- FLAVOUR 1 — both owners are VKEY-staked. Authorization signal is
-- membership in `extra_signatories`.
-- ===================================================================

-- Non-vacuity + the accepting twin (R1): two DISTINCT vkey owners, BOTH
-- present in the signatory set → ACCEPT. Owners differ in exactly the
-- signatory that the rejecting run drops.
theorem exec_accepts_two_owners_both_authorized :
    isSuccessful
      (execT2 vkeyStakeOwner vkeyStakeOwner2 3 4 [ownerKey, owner2Key] baseWdrl) :=
  isHaltB_sound _ (by native_decide)

-- THE LOAD-BEARING V4 / S-16 CONTROL. Same skeleton, ONE field changed:
-- owner 2's key is NOT in the signatory set (only owner 1 signed). The
-- clean PLG bytes REJECT — every PLB input's owner must consent, and
-- owner 2 did not. This is precisely the context a first-input-only auth
-- bug would wrongly accept; the S-16 mutant leg of
-- falsification-control.sh requires the mutant to ACCEPT this exact
-- context (delta vs the twin = the single `owner2Key` signatory).
theorem exec_rejects_second_owner_unauthorized :
    isHaltB
      (execT2 vkeyStakeOwner vkeyStakeOwner2 3 4 [ownerKey] baseWdrl) = false := by
  native_decide

-- ===================================================================
-- FLAVOUR 2 — owner 2 is SCRIPT-staked (smart-wallet pattern). The
-- authorization signal is owner 2's withdraw-0 entry in `txInfoWdrl`,
-- NOT a signatory. Owner 1 stays vkey-staked (and stays signed).
-- ===================================================================

-- Accepting: owner 2's script withdrawal entry is PRESENT (alongside the
-- two mandatory own/tlog entries). Owner 1 signs; owner 2 consents via
-- its withdraw-0. → ACCEPT.
theorem exec_accepts_script_owner_withdrawal :
    isSuccessful
      (execT2 vkeyStakeOwner scriptStakeOwner2 3 4 [ownerKey]
        [(ownCred, 0), (tlogCred, 0), (owner2ScriptCred, 0)]) :=
  isHaltB_sound _ (by native_decide)

-- Rejecting twin (R1, delta = one withdrawal entry): owner 2's script
-- withdrawal entry is ABSENT. Owner 2 is script-staked, so signing does
-- nothing for it; without its withdraw-0 the PLG REJECTS — a script
-- owner that does not invoke its own withdraw-0 has not consented.
theorem exec_rejects_script_owner_no_withdrawal :
    isHaltB
      (execT2 vkeyStakeOwner scriptStakeOwner2 3 4 [ownerKey] baseWdrl) = false := by
  native_decide

-- Claim-integrity gate (C12/V20): pin each theorem's axiom set so the
-- build reddens on drift. Whitespace normalized (single-line compare).
--   KERNEL-PROVED (native_decide): ofReduceBool + trustCompiler present.
/-- info: 'CIP113.exec_accepts_two_owners_both_authorized' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in
  #print axioms exec_accepts_two_owners_both_authorized
/-- info: 'CIP113.exec_rejects_second_owner_unauthorized' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in
  #print axioms exec_rejects_second_owner_unauthorized
/-- info: 'CIP113.exec_accepts_script_owner_withdrawal' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in
  #print axioms exec_accepts_script_owner_withdrawal
/-- info: 'CIP113.exec_rejects_script_owner_no_withdrawal' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in
  #print axioms exec_rejects_script_owner_no_withdrawal

end CIP113
