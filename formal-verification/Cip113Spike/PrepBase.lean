/-
Tier-1, step 2: import `programmable_logic_base` and record its
compile-time parameter application (template: WSC/Prep/Base.lean from the
wsc-containment-proofs campaign).

Layout convention, shared with the other four artifacts: `PrepX.lean`
holds the `#import_uplc` and the parameter-application function ONLY. The
context family, the `#prep_uplc` that bakes the fuel, and the theorems
live in `PropsX.lean` next to the family they serve — for this artifact,
`Cip113Spike/PropsBase.lean`.

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
- Fuel: the fourth coordinate is NOT set here. It is baked by the
  `#prep_uplc` commands in `Cip113Spike/PropsBase.lean`, which also
  carries the measurement that justifies the number.

NO THEOREM LIVES HERE.
-/
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext spendingInputs)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Term (Term)

#import_uplc programmableLogicBase PlutusV3 single_cbor_hex "flats/programmable_logic_base.flat"

/-- Parameter application for `programmable_logic_base`: the
protocol-params NFT policy as `Data.B`, then the spending context. Every
family prepped in `PropsBase.lean` is this function with both arguments
pinned to concrete values. -/
def baseInputs (paramsPolicy : ByteString) (ctx : ScriptContext) : List Term :=
  toTerm paramsPolicy :: spendingInputs ctx

end CIP113
