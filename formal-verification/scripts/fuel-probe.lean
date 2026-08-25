/-
Prep-fuel probe — how the `#prep_uplc` fuel number in `Cip113Spike/` was
determined, in runnable form. NOT part of `lake build` (it is outside the
`lean_lib` globs and nothing imports it); run it by hand:

    cd formal-verification && lake env lean scripts/fuel-probe.lean

Method. `#prep_uplc <name> <script> <inputs> N` bakes N as the CEK step
budget: `cekExecuteProgram` runs at most N steps and returns `State.Error`
if it has not halted by then — indistinguishable from a validator that
rejected. So a fuel BELOW the accepting step count silently turns every
acceptance into a rejection, and a fuel far above it costs prep time and
memory for nothing. The right number is the minimum K at which a CONCRETE
ACCEPTING context reaches `State.Halt`, plus headroom.

`minFuel` binary-searches K over [1, 100000] for a given context: it
first checks the context halts at the ceiling (otherwise the context is
not accepting, or the ceiling is too low, and it answers `none`), then
bisects. Each probe is one concrete CEK run, so this is cheap — no
symbolic execution and no SMT. The bisection is sound because halting is
MONOTONE in the fuel for a fixed context; `haltGapsBelow` below re-checks
that by linear scan rather than assuming it.

Output when this file was written (2026-08-25, Aiken v1.1.23 blueprint,
`flats/programmable_logic_base.flat`, 829 B):

  -- the eight accepting families prepped in Cip113Spike/PropsBase.lean
    some 1241   SpendViaTransfer    params_idx 0, wdrl_idx 1, 3-entry map
    some 1210   SpendViaThirdParty  params_idx 0, wdrl_idx 0, 3-entry map
    some 1291   SpendViaUnfracking  params_idx 0, wdrl_idx 2, 3-entry map
    some 1168   SpendViaTransfer    params_idx 0, wdrl_idx 0, 1-entry map
    some 1241   SpendViaTransfer    params_idx 0, wdrl_idx 1, 4-entry map
    some 1314   SpendViaTransfer    params_idx 1, wdrl_idx 1, 3-entry map
    some 1241   as row 1, two PLB spend inputs
    some 1241   as row 1, a structurally different validity range
  -- delegate walked to at withdrawal index 0..5, transfer arm
    [some 1168, some 1241, some 1222, some 1295, some 1276, some 1349]
  -- monotonicity check: fuels in [1150, 1350) that do NOT halt but sit
  -- above one that does
    ([], [])

max K = 1314, so `PropsBase.lean` preps every family at 1600 (≥ 1.2 · K).

Two readings that matter for the slices still to come:

 1. The step count is NOT monotone in the index walked — the row above
    runs +73, −19, +73, −19, +73, a sawtooth averaging ~27 steps per
    index. Fuel cannot be extrapolated from a neighbouring family; each
    one must be measured. (Halting IS monotone in the fuel for a fixed
    context, which is what makes `minFuel` sound; that is the separate
    check.)
 2. The other four artifacts under verification (`transfer`,
    `third_party`, `unfracking`, `registry_mint`) still have NO row here:
    probing them needs a concrete ACCEPTING context for each, which does
    not exist yet — see the module comment in
    `Cip113Spike/PrepTransfer.lean`. The blocker is the context, not the
    prep: `PropsBase.lean` shows that a fully pinned context preps in a
    fraction of a second even where a symbolic one cannot be prepped at
    all.
-/
import Cip113Spike.PropsBase

namespace CIP113.FuelProbe

open CardanoLedgerApi.V3 (Credential ScriptContext Withdrawals)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram State)

-- NOTE: `#import_uplc` and `#prep_uplc` declare their names at the ROOT
-- namespace, ignoring the enclosing `namespace` — so the script imported
-- inside `namespace CIP113` in PrepBase.lean is `programmableLogicBase`,
-- not `CIP113.programmableLogicBase`.
def run (ctx : ScriptContext) (n : Nat) : State :=
  cekExecuteProgram programmableLogicBase.script
    (CIP113.baseInputs CIP113.paramsPolicy ctx) n

/-- Minimum fuel at which `ctx` reaches `State.Halt`, or `none` if it
never does within `hi` steps (context rejects, or `hi` is too low). -/
partial def minFuel (ctx : ScriptContext) (lo hi : Nat) : Option Nat :=
  if !(CIP113.isHaltB (run ctx hi)) then none
  else
    let rec go (lo hi : Nat) : Nat :=
      if lo >= hi then lo
      else
        let mid := (lo + hi) / 2
        if CIP113.isHaltB (run ctx mid) then go lo mid else go (mid + 1) hi
    some (go lo hi)

/-- Soundness check for the bisection: the fuels in `[lo, hi)` at which
`ctx` does NOT halt, restricted to those above a fuel at which it does.
Must be `[]` — otherwise halting is not monotone in the fuel and
`minFuel` means nothing. -/
def haltGapsBelow (ctx : ScriptContext) (lo hi : Nat) : List Nat :=
  match (List.range (hi - lo)).find? (fun i => CIP113.isHaltB (run ctx (lo + i))) with
  | none => []
  | some first =>
    (List.range (hi - lo - first)).filterMap fun i =>
      if CIP113.isHaltB (run ctx (lo + first + i)) then none else some (lo + first + i)

-- The eight accepting families `Cip113Spike/PropsBase.lean` preps. Fuel
-- 1600 there must be ≥ 1.2 × the largest number printed here.
#eval minFuel CIP113.ctxTransferAt1 1 100000
#eval minFuel CIP113.ctxThirdPartyAt0 1 100000
#eval minFuel CIP113.ctxUnfrackingAt2 1 100000
#eval minFuel CIP113.ctxSoloDelegate 1 100000
#eval minFuel CIP113.ctxFourEntryAt1 1 100000
#eval minFuel CIP113.ctxParamsIdx1 1 100000
#eval minFuel CIP113.ctxTwoInputs 1 100000
#eval minFuel CIP113.ctxRangeVariant 1 100000

/-- `n` padding withdrawals sorted AHEAD of the transfer delegate (`0…`
< `TRSF`), so the delegate lands at index `n` and the map is still in
ledger order. -/
def delegateAt (n : Nat) : Withdrawals :=
  (List.range n).map
      (fun i => (Credential.ScriptCredential (ByteString.mk s!"0{i}AA"), (0 : Int)))
    ++ [(CIP113.transferCred, 0)]

def probeAt (n : Nat) : ScriptContext :=
  CIP113.mkCtx [CIP113.paramsRefIn] (delegateAt n)
    (CIP113.viaTransfer 0 n) CIP113.spendInfo

-- The sawtooth: cost vs the withdrawal index walked to.
#eval (List.range 6).map (fun n => minFuel (probeAt n) 1 100000)

-- Monotonicity of halting in the fuel, on two families with different
-- accepting step counts. Both must print `[]`.
#eval (haltGapsBelow CIP113.ctxTransferAt1 1150 1350,
       haltGapsBelow CIP113.ctxUnfrackingAt2 1150 1350)

end CIP113.FuelProbe
