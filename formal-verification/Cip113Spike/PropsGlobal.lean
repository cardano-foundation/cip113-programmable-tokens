/-
Stage-1 containment theorems over the compiled `programmable_logic_global`
bytecode — the "programmable tokens cannot escape the PLB jail" property,
TransferAct path, shaped (template: WSC/Props/Shaped/P1ShapedR.lean,
Phil DiSarro's P1 transfer-containment family).

FAMILY T1 (single registered policy, TransferAct, one PLB input, one
token-carrying output — the minimal shape that reaches the conservation
check in `validate_transfer`):

  reference inputs : [ protocol-params UTxO (NFT `paramsPolicy`,
                       datum Constr 0 [registryCS, plbCred, unfrCred]),
                       registry node UTxO (NFT `registryCS`, datum =
                       RegistryNode with key = the acted policy and
                       transfer_logic_script = T at field 3) ]
  inputs           : [ UTxO at Address(plbCred, owner vkey stake)
                       carrying (polP, tokenName, qIn) ]
  outputs          : [ UTxO at Address(SYMBOLIC C, stake) carrying
                       (polP, tokenName, qOut) ]
  withdrawals      : [(own PLG cred, 0), (T, 0)]  -- ledger order
  extra_signatories: [owner]
  mint             : empty
  redeemer         : TransferAct [TokenExists {node_idx: 1}]

Theorems (labels per the methodology doc):
  T1-escape       : acceptance forces C = the PLB payment credential —
                    the tokens' only exit is back into the jail.
  T1-conservation : with C = PLB, acceptance forces qOut ≥ qIn — the
                    `tokens.contains` guarantee on the compiled bytes.

Controls (the wsc four-point bar, minus realizability — tracked):
  exec_accepts_transfer      — concrete accepting witness, kernel-checked.
                               Doubles as the non-vacuity witness for
                               T1-conservation (accepting run at C = PLB).
  exec_rejects_escape        — tokens routed to a foreign payment
                               credential are rejected, kernel-checked.
  exec_rejects_shortfall     — qOut < qIn is rejected, kernel-checked.
  anonymous #blaster probe   — vacuity probe for T1-escape: its negation
                               is Expected-Falsified (an accepting run
                               exists inside the family).
TODO (tracked in FORMAL_VERIFICATION_STATUS.md): an
  exec_rejects_no_transfer_logic control (drop T's withdrawal — the
  substandard-invocation guarantee) and a symbolic non-vacuity probe
  for T1-conservation.
-/
import Cip113Spike.PrepGlobal
import Cip113Spike.PropsBase
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class.IsData (toData)
open CardanoLedgerApi.V2 (TxOut)
open CardanoLedgerApi.V3 (Credential ScriptContext TxOutRef)
open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Utils (isSuccessful)

set_option warn.sorry false
set_option maxHeartbeats 0
set_option maxRecDepth 65536

-- Cast of the T1 family (tags, not 28-byte hashes: the transfer path
-- compares by byte equality only; registration-time length checks are
-- registry_mint's job, out of scope here).
def plbHash : ByteString := ByteString.mk "BASE"
def plbCred : Credential := .ScriptCredential plbHash
def ownCred : Credential := .ScriptCredential (ByteString.mk "PLGW")
def tlogHash : ByteString := ByteString.mk "TLOG"
def tlogCred : Credential := .ScriptCredential tlogHash
def ownerKey : ByteString := ByteString.mk "OWNER"
def paramsPolicy : ByteString := ByteString.mk "PPCS"
def registryCS : ByteString := ByteString.mk "RCS"
def polP : ByteString := ByteString.mk "PTOK"
def tokenName : ByteString := ByteString.mk "T"

/-- Aiken `Some(Inline(cred))` and ledger `StakingHash cred` share the
Data encoding (Constr 0 [cred]) — the CLAB type is faithful as-is. -/
def vkeyStakeOwner : CardanoLedgerApi.V1.StakingCredential :=
  .StakingHash (.PubKeyCredential ownerKey)

/-- Value with an ada entry first (canonical) and one further policy. -/
def valueWith (pid name : ByteString) (q : Int) :
    CardanoLedgerApi.V1.Value.Value :=
  [ (Data.B (ByteString.mk ""), Data.Map [(Data.B (ByteString.mk ""), Data.I 2000000)])
  , (Data.B pid, Data.Map [(Data.B name, Data.I q)]) ]

/-- Protocol-params datum: Constr 0 [registry_node_cs, prog_logic_cred,
unfracking_cred] (golden_protocol_params_layout). -/
def paramsDatum : Data :=
  Data.Constr 0
    [ Data.B registryCS
    , toData plbCred
    , toData (Credential.ScriptCredential (ByteString.mk "UNFR")) ]

/-- RegistryNode datum: Constr 0, SEVEN fields in declaration order
(golden_registry_node_layout); the transfer path reads key (0) and
transfer_logic_script (3). -/
def nodeDatum : Data :=
  Data.Constr 0
    [ Data.B polP
    , Data.B (ByteString.mk "ZZZZ")
    , toData (Credential.ScriptCredential (ByteString.mk "MINT"))
    , toData tlogCred
    , toData (Credential.ScriptCredential (ByteString.mk "3RDP"))
    , toData (Credential.PubKeyCredential (ByteString.mk ""))
    , Data.B (ByteString.mk "") ]

/-- A reference-input TxOut carrying an authenticating NFT (`peek_first`
reads the FIRST non-ada policy) and an inline datum. -/
def refOut (nftPolicy : ByteString) (datum : Data) : TxOut :=
  { txOutAddress := ⟨.ScriptCredential (ByteString.mk "HOLD"), none⟩
  , txOutValue := valueWith nftPolicy (ByteString.mk "x") 1
  , txOutDatum := .OutputDatum datum
  , txOutReferenceScript := none }

def inRef : TxOutRef := ⟨ByteString.mk "", 0⟩

/-- TransferAct [TokenExists {node_idx: 1}] — node_idx indexes ALL
reference inputs; the params UTxO occupies index 0. -/
def transferRdmr : Data :=
  Data.Constr 0 [Data.List [Data.Constr 0 [Data.I 1]]]

/-- The T1 family: symbolic output payment credential + symbolic
in/out token quantities; everything else concrete. -/
def mkT1 (outPay : Credential) (qIn qOut : Int) : ScriptContext :=
  { scriptContextTxInfo :=
    { txInfoInputs :=
        [⟨inRef,
          { txOutAddress := ⟨plbCred, some vkeyStakeOwner⟩
          , txOutValue := valueWith polP tokenName qIn
          , txOutDatum := .NoOutputDatum
          , txOutReferenceScript := none }⟩]
    , txInfoReferenceInputs :=
        [ ⟨⟨ByteString.mk "", 1⟩, refOut paramsPolicy paramsDatum⟩
        , ⟨⟨ByteString.mk "", 2⟩, refOut registryCS nodeDatum⟩ ]
    , txInfoOutputs :=
        [ { txOutAddress := ⟨outPay, some vkeyStakeOwner⟩
          , txOutValue := valueWith polP tokenName qOut
          , txOutDatum := .NoOutputDatum
          , txOutReferenceScript := none } ]
    , txInfoFee := 500000
    , txInfoMint := []
    , txInfoTxCerts := []
    , txInfoWdrl := [(ownCred, 0), (tlogCred, 0)]
    , txInfoValidRange := range
    , txInfoSignatories := [ownerKey]
    , txInfoRedeemers :=
        [ (.Spending inRef, Data.Constr 0 [])
        , (.Rewarding ownCred, transferRdmr)
        , (.Rewarding tlogCred, Data.I 0) ]
    , txInfoData := []
    , txInfoId := ByteString.mk ""
    , txInfoVotes := []
    , txInfoProposalProcedures := []
    , txInfoCurrentTreasuryAmount := Data.I 1
    , txInfoTreasuryDonation := Data.I 1 }
  , scriptContextRedeemer := transferRdmr
  , scriptContextScriptInfo := .RewardingScript ownCred }

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (rewardingInputs)
open PlutusCore.UPLC.Term (Term)

/-- SHAPED prep (the wsc statement-level-skeleton discipline): the T1
family's three leaves are the ONLY symbolic surface at prep time; the
skeleton is applied before the CEK unroller runs. Unshaped prep of this
validator is the known 20-35 GB memory cliff -- never do it. -/
def t1Inputs (c : ByteString) (qIn qOut : Int) : List Term :=
  toTerm paramsPolicy :: rewardingInputs (mkT1 (.ScriptCredential c) qIn qOut)

#prep_uplc appliedT1 programmableLogicGlobal t1Inputs 4400

-- 1. Non-vacuity: the real CEK accepts the honest transfer
-- (tokens return to the PLB, quantity conserved), kernel-checked.
theorem exec_accepts_transfer :
    isSuccessful (appliedT1.exec plbHash 5 5) :=
  isHaltB_sound _ (by native_decide)

-- 2. Polarity: routing the tokens to a FOREIGN payment credential is
-- rejected (the escape attempt), kernel-checked.
theorem exec_rejects_escape :
    isHaltB (appliedT1.exec (ByteString.mk "EVE") 5 5) = false := by
  native_decide

-- 3. Polarity: shrinking the returned quantity is rejected
-- (partial escape / burn-without-mint), kernel-checked.
theorem exec_rejects_shortfall :
    isHaltB (appliedT1.exec plbHash 5 4) = false := by
  native_decide

-- T1-ESCAPE: for EVERY script payment credential C the output may carry
-- the tokens to, acceptance of the compiled PLG FORCES C to be the PLB
-- credential — inside this family, the jail is the only destination.
theorem t1_escape :
    ∀ (c : ByteString) (qIn qOut : Int),
      isSuccessful
        (appliedT1.prop c qIn qOut) →
      c = plbHash := by
  blaster (timeout: 900)

-- Vacuity probe (wsc four-point bar, point b): the NEGATION must be
-- Falsified — the family does contain accepting runs with C = PLB.
#blaster (timeout: 900) (solve-result: 1)
  [∀ (c : ByteString) (qIn qOut : Int),
    isSuccessful
      (appliedT1.prop c qIn qOut) →
    c ≠ plbHash]

-- T1-CONSERVATION: with the output pinned at the PLB, acceptance FORCES
-- qOut ≥ qIn — the compiled `tokens.contains` guarantee: nothing leaks
-- on the way back into the jail.
theorem t1_conservation :
    ∀ (qIn qOut : Int),
      isSuccessful
        (appliedT1.prop plbHash qIn qOut) →
      qIn ≤ qOut := by
  blaster (timeout: 900)

#print axioms exec_accepts_transfer
#print axioms t1_escape
#print axioms t1_conservation

end CIP113
