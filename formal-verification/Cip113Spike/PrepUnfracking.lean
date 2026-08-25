/-
Tier-1: import the `unfracking` withdraw-0 artifact (holder-driven
same-owner restructuring, v2 registry-gated) and record its parameter
application.

Parameter evidence for `unfracking` — 1 parameter, then ctx:

1. `params_policy : PolicyId` (= ByteArray at the Data level). Aiken
   source: `validators/unfracking.ak` (`validator
   unfracking(params_policy: PolicyId)`); IsData: `Data.B bytes`.

Same handler shape as `transfer` and `third_party` — `withdraw` /
`publish` / `else` in one script, dispatched on the script purpose; the
hot handler is `withdraw`, invoked with a Rewarding purpose, so contexts
carry `scriptContextScriptInfo := .RewardingScript ownCred` and are
applied via `rewardingInputs`.

Reached ONLY through a `SpendViaUnfracking` base spend, which names this
script by the live `unfracking_cred` field of the protocol-params datum.
Note the extra gate the theorems will have to reach: this validator
additionally requires the acted-on policy's issuer-declared
`unfracking_logic_script` withdraw-0 (registry-node field 5) — an unset
hook forbids unfracking for that policy outright (default deny).

NO `#prep_uplc` HERE — same reason as `PrepTransfer.lean`, which carries
the measurements: unshaped symbolic prep of a ~2 KB artifact blows up
exponentially in the fuel long before the fuel reaches this validator's
accepting step count, so any fuel that elaborates would certify nothing.
A concrete accepting context (to measure K) and a shaped prep built on
its skeleton are prerequisites, and both belong to the slice that writes
the theorems.

IDENTITY: `flats/unfracking.flat` (1956 B), pinned by
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

#import_uplc unfrackingWithdraw PlutusV3 single_cbor_hex "flats/unfracking.flat"

/-- Parameter application for `unfracking`: the protocol-params NFT
policy as `Data.B`, then the rewarding context. Recorded here so the
theorem slice inherits the checked shape; not yet passed to
`#prep_uplc` (see the module comment). -/
def unfrackingInputs (paramsPolicy : ByteString) (ctx : ScriptContext) : List Term :=
  toTerm paramsPolicy :: rewardingInputs ctx

end CIP113
