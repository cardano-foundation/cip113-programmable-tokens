/-
FALSIFICATION CONTROL — this file must NEVER be part of the default
`lake build`. It is run only by `scripts/falsification-control.sh`,
against a MUTANT artifact that script builds through the real Aiken
pipeline (mutated source → `aiken build` → extracted `compiledCode`).

The mutation replaces the base validator's only check
(`self.withdrawals |> pairs.has_key_or_fail(stake_cred)`) with `True`.

Expected outcomes (anything else is a failure OF THE HARNESS):
 1. The forwarding theorem that is Valid on the clean artifact must come
    back **Falsified** here (`solve-result: 1` — the Vesting "bugged"
    idiom from Lean-blaster's own examples). If it ever came back Valid,
    the pipeline could no longer tell working code from broken code.
 2. The concrete foreign-withdrawal context that the clean artifact
    REJECTS must be ACCEPTED by the mutant (kernel-checked), proving the
    mutation reached the executable semantics, not just the bytes.

Identity: same toolchain + variant discipline as the clean build — the
driver script verifies `aiken --version` against the blueprint preamble
and the mutant flat differs from the clean one before this file runs.
BuiltinSemanticsVariant: E (via `cekExecuteProgram`'s pinned default,
see Cip113Spike/PrepBase.lean).
-/
import Cip113Spike.PropsBase
import Blaster

namespace CIP113.Control

open CardanoLedgerApi.V3 (Credential ScriptContext)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Utils (isSuccessful)
open CIP113 (mkCtx stakeCred eveCred isHaltB)

set_option warn.sorry false
set_option maxHeartbeats 0

#import_uplc programmableLogicBaseMutant PlutusV3 single_cbor_hex "controls/flats/programmable_logic_base_mutant.flat"

def mutantInputs (stakeCred : Credential) (ctx : ScriptContext) : List PlutusCore.UPLC.Term.Term :=
  CIP113.baseInputs stakeCred ctx

#prep_uplc appliedMutant programmableLogicBaseMutant mutantInputs 600

-- Control 1: the clean artifact's Valid forwarding theorem must be
-- FALSIFIED on the mutant (solve-result: 1 = expect Falsified; the
-- command fails if Z3 says anything else).
#blaster (timeout: 900) (solve-result: 1)
  [∀ (param h : ByteString) (amt : Int),
    isSuccessful
      (appliedMutant.prop (.ScriptCredential param)
        (CIP113.mkCtx [(.ScriptCredential h, amt)])) →
    h = param]

-- Control 1b (C10 leg 2): the FOUR-entry forwarding rung
-- (`base_forces_plg_withdrawal_four_entries`, Valid on the clean
-- artifact) must ALSO come back Falsified on the mutant — the mutant
-- accepts regardless of whether the param is anywhere in the map, so
-- the deeper-scan rung is not spuriously preserved. Extends the mutant
-- control beyond the 1-entry rung.
#blaster (timeout: 1800) (solve-result: 1)
  [∀ (param h1 h2 h3 h4 : ByteString) (a1 a2 a3 a4 : Int),
    isSuccessful
      (appliedMutant.prop (.ScriptCredential param)
        (CIP113.mkCtx
          [ (.ScriptCredential h1, a1), (.ScriptCredential h2, a2)
          , (.ScriptCredential h3, a3), (.ScriptCredential h4, a4)
          ])) →
    (h1 = param ∨ h2 = param ∨ h3 = param ∨ h4 = param)]

-- Control 2: the exact context the CLEAN artifact rejects
-- (exec_rejects_foreign_withdrawal) is ACCEPTED by the mutant —
-- kernel-checked evidence the mutation reached the CEK semantics.
theorem mutant_accepts_foreign_withdrawal :
    isHaltB (appliedMutant.exec stakeCred (mkCtx [(eveCred, 0)])) = true := by
  native_decide

end CIP113.Control
