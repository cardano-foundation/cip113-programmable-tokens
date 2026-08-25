/-
Tier-1: import the `third_party` withdraw-0 artifact (seize / clawback /
freeze enforcement) and record its parameter application.

Parameter evidence for `third_party` — 1 parameter, then ctx:

1. `params_policy : PolicyId` (= ByteArray at the Data level). Aiken
   source: `validators/third_party.ak` (`validator
   third_party(params_policy: PolicyId)`); IsData: `Data.B bytes`.

Same handler shape as `transfer` — `withdraw` / `publish` / `else` in one
script, dispatched on the script purpose. The hot handler is `withdraw`,
invoked by the ledger with a Rewarding purpose, so contexts carry
`scriptContextScriptInfo := .RewardingScript ownCred` and are applied via
`rewardingInputs`.

Reached ONLY through a `SpendViaThirdParty` base spend, which names this
script by the live `third_party_cred` field of the protocol-params datum
(`programmable_logic_base.ak`). A theorem about the seize path therefore
composes THIS artifact with `programmable_logic_base` — the params datum
is the join.

NO `#prep_uplc` HERE — same reason as `PrepTransfer.lean`, which carries
the measurements: unshaped symbolic prep of a ~2 KB artifact blows up
exponentially in the fuel long before the fuel reaches this validator's
accepting step count, so any fuel that elaborates would certify nothing.
A concrete accepting context (to measure K) and a shaped prep built on
its skeleton are prerequisites, and both belong to the slice that writes
the theorems.

IDENTITY: `flats/third_party.flat` (2025 B), pinned by
`flats/MANIFEST.md`; semantics variant E (PlutusV3 post-Conway) via
PlutusCoreBlaster's `cekExecuteProgram` default — see `PrepBase.lean`.
The fuel coordinate is NOT yet established for this artifact.
-/
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext rewardingInputs)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Term (Term)

#import_uplc thirdPartyWithdraw PlutusV3 single_cbor_hex "flats/third_party.flat"

/-- Parameter application for `third_party`: the protocol-params NFT
policy as `Data.B`, then the rewarding context. Recorded here so the
theorem slice inherits the checked shape; not yet passed to
`#prep_uplc` (see the module comment). -/
def thirdPartyInputs (paramsPolicy : ByteString) (ctx : ScriptContext) : List Term :=
  toTerm paramsPolicy :: rewardingInputs ctx

end CIP113
