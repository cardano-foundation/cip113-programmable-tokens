/-
Stage-1 containment spike, step 1: apply the deployment parameter and
prep the GLOBAL validator (PLG) for symbolic execution.

Parameter evidence for `programmable_logic_global` — 1 parameter, then ctx:

1. `params_policy : PolicyId` (= ByteArray at the Data level). Aiken
   source: `validators/programmable_logic_global.ak`
   (`validator programmable_logic_global(params_policy: PolicyId)`).
   IsData: `Data.B bytes`.

The validator is a withdraw-0 script: the ledger invokes it with a
Rewarding script purpose, so contexts are built with
`scriptContextScriptInfo := .RewardingScript ownCred` and applied via
`rewardingInputs` (stock upstream CLAB helper).

Prep budget 4400 — the rung Phil DiSarro's wsc campaign used for his
(larger) Plutarch global validator's shaped transfer contexts, whose
accepting Ks measured 2288–2777. Shaped prep at this budget completed in
~1.5 s there (the #prep_uplc memory cliff bites UNSHAPED prep only —
WSC/PREP-MEMORY-CLIFF.md).

IDENTITY: `flats/programmable_logic_global.flat`, pinned by
`flats/MANIFEST.md` (compiler from the blueprint's own preamble, sha256;
the source commit is the commit containing the manifest). Semantics:
variant E (PlutusV3 post-Conway) via PlutusCoreBlaster's
`cekExecuteProgram` default — see PrepBase.lean for the evidence chain.
-/
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext rewardingInputs)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Term (Term)

-- NOTE: no unshaped `#prep_uplc` here, deliberately. Prepping the
-- global validator against a fully symbolic ScriptContext is exactly
-- the #prep_uplc memory cliff Phil's campaign measured (20–35 GB
-- deaths at budgets ≥2300 — WSC/PREP-MEMORY-CLIFF.md). Prep happens in
-- PropsGlobal.lean against the SHAPED T1 family (statement-level
-- skeleton: only the family's leaves are symbolic at prep time).
#import_uplc programmableLogicGlobal PlutusV3 single_cbor_hex "flats/programmable_logic_global.flat"

end CIP113
