/-
FALSIFICATION CONTROL (V4 / seed S-16) — this file must NEVER be part of
the default `lake build`. It is run only by
`scripts/falsification-control.sh` (the auth mutant leg), against a
MUTANT `programmable_logic_global` artifact that script builds through
the real Aiken pipeline (mutated `transfer.ak` → `aiken build` →
extracted `compiledCode`).

The mutation makes the per-input owner-authorisation `expect` in
`collect_input_assets` (transfer.ak) fire ONLY for the FIRST transaction
input: it gates `authorised_stake_cred(...)` on
`input.output_reference == list.head(tx.inputs).output_reference`. Every
subsequent PLB input's owner is therefore NOT checked — the
"auth-first-input-only" bug Paolo's V4 observation targets. It COMPILES
(uses only `list.head`, already in scope; `input.output_reference`, a
stdlib field) and reaches the executable semantics.

Expected outcome (anything else is a failure OF THE HARNESS): the exact
two-owner context the CLEAN PLG REJECTS
(`exec_rejects_second_owner_unauthorized`: two distinct vkey owners, only
owner 1 signed) must be ACCEPTED by the mutant — kernel-checked evidence
that the seeded first-input-only bug is a real hole the clean bytes
close, and that the single-input controls could not have caught it.

Identity: same toolchain + variant discipline as the clean build — the
driver script verifies `aiken --version` against the blueprint preamble
and asserts the mutant flat differs from the clean one before this file
runs. BuiltinSemanticsVariant: E (via `cekExecuteProgram`'s pinned
default). Fuel 4400 (PLG-shaped), variant E — the T2 identity coordinates.
-/
import Cip113Spike.PropsGlobalAuth
import Blaster

namespace CIP113.AuthControl

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (rewardingInputs)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open CIP113 (isHaltB mkT2 paramsPolicy vkeyStakeOwner vkeyStakeOwner2
  ownerKey owner2Key baseWdrl)

set_option warn.sorry false
set_option maxHeartbeats 0
set_option maxRecDepth 65536

#import_uplc programmableLogicGlobalMutant PlutusV3 single_cbor_hex "controls/flats/programmable_logic_global_mutant.flat"

/-- Concrete raw exec of the MUTANT PLG over the T2 input list — same
skeleton as `CIP113.execT2`, but against the mutant script. -/
def execMutantT2 (q1 q2 : Int) (sigs : List PlutusCore.ByteString.ByteString)
    (wdrl : CardanoLedgerApi.V3.Withdrawals) :
    PlutusCore.UPLC.CekMachine.State :=
  cekExecuteProgram programmableLogicGlobalMutant.script
    (toTerm paramsPolicy ::
      rewardingInputs (mkT2 vkeyStakeOwner vkeyStakeOwner2 q1 q2 sigs wdrl)) 4400

-- THE CONTROL: the exact context `exec_rejects_second_owner_unauthorized`
-- proves the CLEAN PLG REJECTS (two distinct vkey owners, only owner 1 in
-- the signatory set) is ACCEPTED by the first-input-only-auth mutant.
-- Kernel-checked (native_decide), proving the seeded bug reached the CEK
-- semantics and that the single-input controls are insufficient.
theorem mutant_accepts_second_owner_unauthorized :
    isHaltB (execMutantT2 3 4 [ownerKey] baseWdrl) = true := by
  native_decide

end CIP113.AuthControl
