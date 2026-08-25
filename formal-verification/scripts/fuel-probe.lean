/-
Prep-fuel probe — how the `#prep_uplc` fuel numbers in `Cip113Spike/`
were determined, in runnable form. NOT part of `lake build` (it is
outside the `lean_lib` globs and nothing imports it); run it by hand:

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
symbolic execution and no SMT.

Output when this file was written (2026-08-25, Aiken v1.1.23 blueprint,
`flats/programmable_logic_base.flat`, 829 B):

    some 1168   SpendViaTransfer    params_idx 0, wdrl_idx 0  (1-entry map)
    some 1210   SpendViaThirdParty  params_idx 0, wdrl_idx 0
    some 1237   SpendViaUnfracking  params_idx 0, wdrl_idx 0
    some 1349   SpendViaTransfer    wdrl_idx 5   (6-entry map)
    some 1438   SpendViaTransfer    wdrl_idx 10  (11-entry map)
    some 1507   SpendViaUnfracking  wdrl_idx 10  (11-entry map)

Reading: the three dispatch arms differ by ~70 steps (the params-datum
field they walk to), and each extra withdrawal entry walked past costs
~25 steps. `PrepBase.lean` preps the first row's family and takes fuel
1400 (≈1.2·K).

The other four artifacts under verification (`transfer`, `third_party`,
`unfracking`, `registry_mint`) have NO row here: probing them needs a
concrete ACCEPTING context for each, which does not exist yet — see the
module comment in `Cip113Spike/PrepTransfer.lean`.
-/
import Cip113Spike.PrepBase

namespace CIP113.FuelProbe

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (Credential ScriptContext Withdrawals spendingInputs)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram State)

/-- `BaseSpendRedeemer` constructors 0/1/2, both fields witnessed. -/
def viaTransfer (p w : Int) : Data := Data.Constr 0 [Data.I p, Data.I w]
def viaThirdParty (p w : Int) : Data := Data.Constr 1 [Data.I p, Data.I w]
def viaUnfracking (p w : Int) : Data := Data.Constr 2 [Data.I p, Data.I w]

/-- `CIP113.mkCtx` with the redeemer opened up as well (it pins
`SpendViaTransfer { params_idx: 0, wdrl_idx: 0 }`, which is the family it
preps, not the family we want to probe). -/
def mkProbeCtx (rdmr : Data) (wdrl : Withdrawals) : ScriptContext :=
  { CIP113.mkCtx wdrl with
    scriptContextTxInfo :=
      { (CIP113.mkCtx wdrl).scriptContextTxInfo with
        txInfoRedeemers := [(.Spending CIP113.outRef, rdmr)] }
    scriptContextRedeemer := rdmr }

def isHaltB : State → Bool
  | .Halt _ => true
  | _ => false

-- NOTE: `#import_uplc` and `#prep_uplc` declare their names at the ROOT
-- namespace, ignoring the enclosing `namespace` — so the script imported
-- inside `namespace CIP113` in PrepBase.lean is `programmableLogicBase`,
-- not `CIP113.programmableLogicBase`.
def run (ctx : ScriptContext) (n : Nat) : State :=
  cekExecuteProgram programmableLogicBase.script
    (toTerm CIP113.paramsPolicy :: spendingInputs ctx) n

/-- Minimum fuel at which `ctx` reaches `State.Halt`, or `none` if it
never does within `hi` steps (context rejects, or `hi` is too low). -/
partial def minFuel (ctx : ScriptContext) (lo hi : Nat) : Option Nat :=
  if !(isHaltB (run ctx hi)) then none
  else
    let rec go (lo hi : Nat) : Nat :=
      if lo >= hi then lo
      else
        let mid := (lo + hi) / 2
        if isHaltB (run ctx mid) then go lo mid else go (mid + 1) hi
    some (go lo hi)

/-- `n` decoy withdrawal entries, then the delegate at index `n`. -/
def wdrlBehind (n : Nat) (delegate : Credential) : Withdrawals :=
  (List.range n).map
      (fun i => (Credential.ScriptCredential (ByteString.mk s!"F{i}"), (0 : Int)))
    ++ [(delegate, 0)]

def transferCred : Credential := .ScriptCredential (ByteString.mk "TRSF")
def thirdPartyCred : Credential := .ScriptCredential (ByteString.mk "3RDP")
def unfrackingCred : Credential := .ScriptCredential (ByteString.mk "UNFR")

#eval minFuel (mkProbeCtx (viaTransfer 0 0) (wdrlBehind 0 transferCred)) 1 100000
#eval minFuel (mkProbeCtx (viaThirdParty 0 0) (wdrlBehind 0 thirdPartyCred)) 1 100000
#eval minFuel (mkProbeCtx (viaUnfracking 0 0) (wdrlBehind 0 unfrackingCred)) 1 100000
#eval minFuel (mkProbeCtx (viaTransfer 0 5) (wdrlBehind 5 transferCred)) 1 100000
#eval minFuel (mkProbeCtx (viaTransfer 0 10) (wdrlBehind 10 transferCred)) 1 100000
#eval minFuel (mkProbeCtx (viaUnfracking 0 10) (wdrlBehind 10 unfrackingCred)) 1 100000

end CIP113.FuelProbe
