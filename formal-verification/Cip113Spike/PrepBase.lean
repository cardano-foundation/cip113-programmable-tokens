/-
Tier-1, step 2: apply the deployment parameter and prep the base
validator for symbolic execution (template: WSC/Prep/Base.lean from the
wsc-containment-proofs campaign).

Parameter evidence for `programmable_logic_base` — 1 parameter, then ctx:

1. `params_policy : PolicyId` (= ByteArray at the Data level) — the
   protocol-params NFT policy, the protocol's only permanent anchor.
   Aiken source: `validators/programmable_logic_base.ak` (`validator
   programmable_logic_base(params_policy: PolicyId)`); IsData: `Data.B
   bytes`. NOTE: this replaced the pre-#110 `stake_cred: Credential`
   parameter (a `Constr 0/1 [B bytes]`) when the delegates became
   swappable in place — a prep written against the old shape applies a
   `Constr`, not a `B`, and silently produces a script that can never
   halt.

Body: PLB no longer scans the withdrawal map. It reads the LIVE delegate
credential out of the protocol-params reference input addressed by the
redeemer's `params_idx`, resolves the withdrawal the redeemer's
`wdrl_idx` witnesses, and compares. The redeemer picks WHICH delegate
field is read — `SpendViaTransfer` (params field 2), `SpendViaThirdParty`
(field 3), `SpendViaUnfracking` (field 4). Any theorem about PLB is
therefore a statement about a three-arm dispatch over a datum, not about
a map scan.

SHAPED PREP — read this before changing the conversion function.
`#prep_uplc` symbolically unrolls the CEK machine `fuel` times; against a
FULLY SYMBOLIC `ScriptContext` no branch can be decided, so the residual
term forks at every step and elaboration blows up exponentially. Measured
on this 829-byte artifact (2026-08-25, this machine, unshaped
`toTerm p :: spendingInputs ctx` with both arguments symbolic):

    fuel  600 -> ~9 s,   ~1.0 GB   (elaborates)
    fuel 1200 -> killed at 10 min, 2.8 GB and still growing

and the fuel this validator actually NEEDS is ≥1168 (below), i.e. on the
far side of that cliff. The same cliff is why the pre-#110
`PrepGlobal.lean` carried no `#prep_uplc` at all and prepped inside its
shaped family instead (the wsc campaign measured 20-35 GB deaths on
unshaped prep of a comparable validator). So the skeleton below is
CONCRETE and only the witnessed withdrawal credential's hash is symbolic.
Shaped prep at fuel 1400 costs ~1 s and ~1.0 GB.

FUEL 1400 — how it was determined. Not guessed and not inherited: the
minimum halting step count K was measured by binary search over
`cekExecuteProgram` on concrete accepting contexts (reproduce with
`lake env lean scripts/fuel-probe.lean`, which prints exactly these
numbers):

    arm / shape                                   K
    SpendViaTransfer,    params_idx 0, wdrl_idx 0   1168   <- the family below
    SpendViaThirdParty,  params_idx 0, wdrl_idx 0   1210
    SpendViaUnfracking,  params_idx 0, wdrl_idx 0   1237
    SpendViaTransfer,    wdrl_idx 5  (6-entry map)  1349
    SpendViaTransfer,    wdrl_idx 10 (11-entry map) 1438
    SpendViaUnfracking,  wdrl_idx 10 (11-entry map) 1507

1400 is the smallest round value ≥1.2·K for the family prepped here
(K = 1168). It is NOT enough for every shape in the table: a family that
witnesses a deep withdrawal index or the unfracking arm must re-measure
and raise it (~25 CEK steps per withdrawal entry walked past). The old
600 in this file was tuned for the 141-byte pre-#110 PLB (K = 194) and is
less than half of what the current artifact needs — at 600 every
accepting run comes back `State.Error` (fuel exhausted), indistinguishable
from a rejection.

IDENTITY (commit + toolchain + BuiltinSemanticsVariant + fuel — a claim
naming fewer than all four is COULD-NOT-EVALUATE):
- Artifact: `flats/programmable_logic_base.flat`, pinned by
  `flats/MANIFEST.md` (compiler from the blueprint's own preamble,
  sha256; the source commit is the commit containing the manifest —
  sources, blueprint, and flats share this repo).
  `scripts/extract-flats.sh --check` must be green.
- Semantics: `#prep_uplc` evaluates via `cekExecuteProgram`, which pins
  `BuiltinSemanticsVariant := default = .defaultFunSemanticsVariantE`
  (PlutusCoreBlaster `PlutusCore/Default/Basic.lean:54`) — PlutusV3
  post-Conway, the mainnet deployment target. Every `.exec`/`.prop`
  result in this project is a claim under variant E and no other.
- Fuel: 1400, per the derivation above.

NO THEOREM LIVES HERE. This module exists so the artifact decodes, the
parameter is applied in the right shape, and the prep completes; the
property ladder is a later slice, and the skeleton below is PROVISIONAL —
the slice that writes the theorems owns the choice of family and may
replace it (re-measuring the fuel if it does).
-/
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.IsData.Class.IsData (toData)
open CardanoLedgerApi.V2 (TxOut)
open CardanoLedgerApi.V3 (Credential ScriptContext TxOutRef Withdrawals spendingInputs)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open PlutusCore.UPLC.Term (Term)

#import_uplc programmableLogicBase PlutusV3 single_cbor_hex "flats/programmable_logic_base.flat"

/-- The deployment parameter: the protocol-params NFT policy. A tag, not
a 28-byte hash — PLB compares this policy by byte equality only. -/
def paramsPolicy : ByteString := ByteString.mk "PPCS"

/-- The shared payment credential every programmable-token UTxO lives at
(params datum field 1). -/
def plbCred : Credential := .ScriptCredential (ByteString.mk "BASE")

/-- Protocol-params datum: `ProgrammableLogicGlobalParams`, `Constr 0`
with SEVEN fields in declaration order (`programmable_logic/params.ak`):
registry_node_cs, prog_logic_cred, transfer_cred, third_party_cred,
unfracking_cred, upgrade_cred, max_inline_datum_bytes. PLB reads exactly
one of fields 2/3/4, chosen by its redeemer. -/
def paramsDatum : Data :=
  Data.Constr 0
    [ Data.B (ByteString.mk "RCS")
    , toData plbCred
    , toData (Credential.ScriptCredential (ByteString.mk "TRSF"))
    , toData (Credential.ScriptCredential (ByteString.mk "3RDP"))
    , toData (Credential.ScriptCredential (ByteString.mk "UNFR"))
    , toData (Credential.ScriptCredential (ByteString.mk "UPGR"))
    , Data.I 512 ]

/-- A value with an ada entry first (canonical) and one further policy. -/
def valueWith (pid name : ByteString) (q : Int) :
    CardanoLedgerApi.V1.Value.Value :=
  [ (Data.B (ByteString.mk ""), Data.Map [(Data.B (ByteString.mk ""), Data.I 2000000)])
  , (Data.B pid, Data.Map [(Data.B name, Data.I q)]) ]

/-- The protocol-params reference input. `with_protocol_params_fields`
authenticates it by mere PRESENCE of the params policy (it is a one-shot
NFT) and then reads its inline datum. -/
def paramsRefOut : TxOut :=
  { txOutAddress := ⟨.ScriptCredential (ByteString.mk "HOLD"), none⟩
  , txOutValue := valueWith paramsPolicy (ByteString.mk "ProtocolParams") 1
  , txOutDatum := .OutputDatum paramsDatum
  , txOutReferenceScript := none }

def outRef : TxOutRef := ⟨ByteString.mk "", 0⟩

/-- The spent programmable-token UTxO. PLB never inspects it (its datum
and own-ref arguments are both `_`), so it stays minimal. -/
def resolved : TxOut :=
  { txOutAddress := ⟨plbCred, none⟩
  , txOutValue :=
      [(Data.B (ByteString.mk ""), Data.Map [(Data.B (ByteString.mk ""), Data.I 100)])]
  , txOutDatum := .NoOutputDatum
  , txOutReferenceScript := none }

/-- Validity interval [0, 1], both bounds finite and closed. -/
def range : Data :=
  Data.Constr 0 [ Data.Constr 0 [Data.Constr 1 [Data.I 0], Data.Constr 1 []]
                , Data.Constr 0 [Data.Constr 1 [Data.I 1], Data.Constr 1 []] ]

/-- `SpendViaTransfer { params_idx, wdrl_idx }` — constructor 0 of
`BaseSpendRedeemer` (`lib/types.ak`). Constructors 1 and 2 are
`SpendViaThirdParty` and `SpendViaUnfracking`, same two fields. -/
def spendViaTransfer (paramsIdx wdrlIdx : Int) : Data :=
  Data.Constr 0 [Data.I paramsIdx, Data.I wdrlIdx]

/-- The prep skeleton: params NFT at reference-input index 0, one
withdrawal at index 0, `SpendViaTransfer { params_idx: 0, wdrl_idx: 0 }`.
Everything is concrete except the withdrawal credential's hash. -/
def mkCtx (wdrl : Withdrawals) : ScriptContext :=
  { scriptContextTxInfo :=
    { txInfoInputs := [⟨outRef, resolved⟩]
    , txInfoReferenceInputs := [⟨⟨ByteString.mk "", 1⟩, paramsRefOut⟩]
    , txInfoOutputs := []
    , txInfoFee := 100
    , txInfoMint := []
    , txInfoTxCerts := []
    , txInfoWdrl := wdrl
    , txInfoValidRange := range
    , txInfoSignatories := []
    , txInfoRedeemers := [(.Spending outRef, spendViaTransfer 0 0)]
    , txInfoData := []
    , txInfoId := ByteString.mk ""
    , txInfoVotes := []
    , txInfoProposalProcedures := []
    -- `Maybe Lovelace` fields: the V3 encoder maps `Nothing` to
    -- `Constr 1 []`; bare `Data.I 1` is outside the encoder image, so no
    -- ledger-produced context would carry it.
    , txInfoCurrentTreasuryAmount := Data.Constr 1 []
    , txInfoTreasuryDonation := Data.Constr 1 [] }
  , scriptContextRedeemer := spendViaTransfer 0 0
  , scriptContextScriptInfo := .SpendingScript outRef none }

/-- Input list for the SHAPED prep: the deployment parameter, then the
context. `h` — the script hash the single withdrawal is registered
under — is the only symbolic leaf, and it is the one the forwarding
property will quantify over. -/
def baseInputs (h : ByteString) : List Term :=
  toTerm paramsPolicy :: spendingInputs (mkCtx [(.ScriptCredential h, 0)])

#prep_uplc appliedBase programmableLogicBase baseInputs 1400

end CIP113
