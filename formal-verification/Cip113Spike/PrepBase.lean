/-
Tier-1, step 2: apply the deployment parameter and prep the base
validator for symbolic execution (template: WSC/Prep/Base.lean from the
wsc-containment-proofs campaign).

Parameter evidence for `programmable_logic_base` — 1 parameter, then ctx:

1. `stake_cred : Credential` — the PLG withdraw-0 credential. Aiken
   source: `validators/programmable_logic_base.ak` (`validator
   programmable_logic_base(stake_cred: Credential)`); all Aiken custom
   types are Data-represented at runtime, so the Lean-side type is
   `Credential` (IsData: Constr 0/1 [B bytes]).

Body (17 lines of Aiken): `self.withdrawals |> pairs.has_key_or_fail(stake_cred)`
— the forwarding pattern. The P3-analogue theorem this enables: base
accepts ⟹ the withdrawal map contains `stake_cred`.

Prep budget 600 — same rung Phil used for his (slightly larger, 192 B
vs our 141 B) base validator, whose accepting runs measured K = 194.

IDENTITY (commit + toolchain + BuiltinSemanticsVariant — a claim naming
fewer than all three is COULD-NOT-EVALUATE):
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
-/
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext Credential spendingInputs)
open PlutusCore.UPLC.Term (Term)

#import_uplc programmableLogicBase PlutusV3 single_cbor_hex "flats/programmable_logic_base.flat"

def baseInputs (stakeCred : Credential) (ctx : ScriptContext) : List Term :=
  toTerm stakeCred :: spendingInputs ctx

#prep_uplc appliedBase programmableLogicBase baseInputs 600

end CIP113
