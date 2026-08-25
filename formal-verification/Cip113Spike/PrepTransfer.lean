/-
Tier-1: import the `transfer` withdraw-0 artifact and record its
parameter application.

Parameter evidence for `transfer` — 1 parameter, then ctx:

1. `params_policy : PolicyId` (= ByteArray at the Data level). Aiken
   source: `validators/transfer.ak` (`validator transfer(params_policy:
   PolicyId)`); IsData: `Data.B bytes`.

The validator has THREE handlers — `withdraw(redeemer, _account, self)`,
`publish(_r, c, _s)` and `else(_) { fail }` — compiled into one script
that dispatches on the script purpose. The hot path is `withdraw`: the
ledger invokes it with a Rewarding purpose, so contexts are built with
`scriptContextScriptInfo := .RewardingScript ownCred` and applied via
`rewardingInputs` (stock upstream CLAB helper) — hence the shape of
`transferInputs` below.

NO `#prep_uplc` HERE — deliberately, and this is the finding of the
slice that created this file rather than an omission.

`#prep_uplc` symbolically unrolls the CEK machine `fuel` times. Against a
symbolic `ScriptContext` no branch can be decided and the residual term
forks at every step. Measured on THIS artifact (2283 B, 2026-08-25, this
machine, `transferInputs` with both arguments symbolic):

    fuel  100 ->   4.3 s
    fuel  200 ->   4.2 s
    fuel  400 ->   5.4 s
    fuel  800 ->  84.4 s
    fuel 1600 ->  killed at 2 min

For comparison the 829-byte `programmable_logic_base` needs ≥1168 CEK
steps just to reach its halt state on the SIMPLEST accepting context it
has (see `PrepBase.lean`); this validator walks the protocol-params
datum, a registry-node proof per policy, the substandard withdraw-0
check and every transaction output, so its accepting K is far larger
again. Every fuel that elaborates here is far below it, and a prep whose
fuel cannot reach a halt state can only ever witness rejection — the
manifest would be recording a number that certifies nothing.

Two things are therefore needed before this artifact can carry a
`#prep_uplc`, and both belong to the slice that writes the theorems:

  1. a CONCRETE accepting context for `transfer`, from which the minimum
     halting step count K is measured by binary search (the method
     `scripts/fuel-probe.lean` applies to PLB); and
  2. a SHAPED prep built on that context's skeleton, leaving only the
     family's leaves symbolic — the discipline the pre-#110
     `PrepGlobal.lean` used for the dissolved 2996-byte coordinator, and
     the one `PrepBase.lean` uses here. Shaped prep collapses the
     branching: on PLB it turned a 10-minute / 2.8 GB non-completion at
     fuel 1200 into ~1 s at fuel 1400.

IDENTITY: `flats/transfer.flat`, pinned by `flats/MANIFEST.md`; semantics
variant E (PlutusV3 post-Conway) via PlutusCoreBlaster's
`cekExecuteProgram` default — see `PrepBase.lean` for the evidence chain.
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

#import_uplc transferWithdraw PlutusV3 single_cbor_hex "flats/transfer.flat"

/-- Parameter application for `transfer`: the protocol-params NFT policy
as `Data.B`, then the rewarding context. Recorded here so the theorem
slice inherits the checked shape; it is NOT passed to `#prep_uplc` yet
(see the module comment). -/
def transferInputs (paramsPolicy : ByteString) (ctx : ScriptContext) : List Term :=
  toTerm paramsPolicy :: rewardingInputs ctx

end CIP113
