/-
Tier-1, step 3: theorems over the compiled Aiken bytecode of
`programmable_logic_base` (template: WSC/Props/P3_Base.lean from the
wsc-containment-proofs campaign; the pre-#110 tree kept the same
`PrepX`/`PropsX` split).

WHAT PLB DOES, and therefore what is worth proving. On every spend it
  1. locates the protocol-params UTxO at `reference_inputs[params_idx]`
     and authenticates it by mere PRESENCE of the one-shot params NFT
     policy it is parameterised with;
  2. reads ONE delegate credential out of that datum — field 2, 3 or 4,
     chosen by which of `SpendViaTransfer` / `SpendViaThirdParty` /
     `SpendViaUnfracking` the redeemer carries;
  3. resolves `withdrawals[wdrl_idx]` with `list.expect_at` — trusted
     blindly, O(wdrl_idx), no scan;
  4. requires the witnessed withdrawal credential to EQUAL the delegate
     credential.
Step 4 is the whole security property: PLB forwards custody to exactly
the delegate the LIVE protocol params name, and to no one else. The
theorems below pin that, arm by arm.

LEDGER ORDER IS PART OF THE SPECIFICATION. Because step 3 indexes rather
than scans, the order of `self.withdrawals` is load-bearing, and that
order is the LEDGER's to choose, not the transaction author's: every
Script credential before every VerificationKey, then bytewise on the
hash. The Aiken suite already shipped a bug from ignoring this (commit
5ad457a: 41 tests were green against a withdrawal order no node can
produce). The fixtures here are therefore built in ledger order —
`3RDP` < `TRSF` < `UNFR` bytewise, so the three delegates land at
indices 0, 1, 2 — and each accepting context additionally carries a
kernel-checked `validSpendingContext` witness, so "a node could have
produced this" is asserted, not asserted-in-prose.

FUEL 1600 — a correctness coordinate, not a performance knob.
`#prep_uplc … N` bakes N as the CEK step budget and `cekExecuteProgram`
returns `State.Error` when it runs out — INDISTINGUISHABLE from a
rejection. Fuel below a family's accepting step count therefore turns
every acceptance into a silent rejection and makes every rejection
theorem trivially true. N was measured, not guessed: `minFuel` binary
search over concrete accepting contexts (`scripts/fuel-probe.lean`,
which prints exactly the table below and now probes THESE families).

    family (all params_idx 0 unless stated)                  K
    SpendViaTransfer,   wdrl_idx 1, 3-entry delegate map   1241
    SpendViaThirdParty, wdrl_idx 0, 3-entry delegate map   1210
    SpendViaUnfracking, wdrl_idx 2, 3-entry delegate map   1291
    SpendViaTransfer,   wdrl_idx 0, 1-entry map            1168
    SpendViaTransfer,   wdrl_idx 1, 4-entry map            1241
    SpendViaTransfer,   params_idx 1, wdrl_idx 1           1314
    as row 1, but with TWO PLB spend inputs                1241
    as row 1, but a different validity range               1241

Reading, and a trap for the slices that follow: cost grows with the
indices walked but NOT monotonically. Measured on the transfer arm with
the delegate at withdrawal index 0..5 (padding credentials sorted ahead
of it, so every map is still ledger-ordered), the accepting step count
runs 1168, 1241, 1222, 1295, 1276, 1349 — a +73/−19 sawtooth, ~27 steps
per index on average. A reference input walked past costs a flat +73
(1241 → 1314 when params_idx goes 0 → 1). Halting IS monotone in the
FUEL for a fixed context (checked by linear scan, no gaps above the
first halting budget), which is what makes the binary search sound; it
is the step count ACROSS contexts that is not. Never extrapolate a
family's fuel from a neighbouring family — measure it.

1600 is the smallest round value ≥ 1.2 · max K (max K = 1314, 1.2 · K =
1577) over EVERY family prepped in this module, so one number is honest
for all of them — which matters because `flats/MANIFEST.md` reads a
single fuel per artifact, mechanically, off the first `#prep_uplc`.
Every `#prep_uplc` below must therefore carry 1600; a family that needs
more must raise all of them and re-measure. (The predecessor of this
module carried 1400, sized for the transfer arm at wdrl_idx 0 alone;
before that, 600, inherited from the 141-byte pre-#110 PLB — at which
every accepting run came back `State.Error`.)

WHY EVERY PREP HERE IS FULLY CONCRETE. `#prep_uplc` symbolically unrolls
the CEK machine `fuel` times, so any argument PLB BRANCHES on forks the
residual term at every step. Measured on this 829-byte artifact
(2026-08-25, this machine): with the `ScriptContext` left symbolic and
only the deployment parameter pinned, prep elaborates at fuel 600 in
~9 s / ~1.0 GB, and at the fuel this module actually needs (1500 probed)
it was still growing — 3.6 GB resident, no result — when killed at 15
minutes. Since PLB branches on the redeemer constructor, on `params_idx`,
on `wdrl_idx` and on the datum fields, there is no useful "one symbolic
leaf" family that covers the dispatch matrix either. So each family below
pins its context completely; `#prep_uplc` then constant-folds and all
twenty-two preps together cost ~7 s. Nothing is lost: `.exec` is identical
under both shapes — it is literally `cekExecuteProgram script (f args)
fuel`, with no optimisation applied (PlutusCoreBlaster
`PlutusCore/UPLC/PreProcess.lean`, `mkUplcApply`; only `.prop` goes
through `Optimize.main`) — so every theorem below is a real CEK run of
the real artifact. The price is that `.prop` here is a single concrete
run, so this module discharges no SMT-quantified claim; the
universally-quantified forwarding property is a later rung and will need
a shaped family built for it.

ELABORATION TRAP, paid for once. The acceptance theorems lift a decided
`isHaltB … = true` through `isHaltB_sound`, and elaborating that lift
unfolds a 1600-step CEK state — past Lean's default recursion depth. When
it blew, the theorem was still ADDED, and `#print axioms` reported it as
depending on NO axioms: a broken elaboration reads CLEANER than a sound
one, and a `#guard_msgs` pinned against that state would have locked the
breakage in. Hence `maxRecDepth` below, and hence the rule: an
`exec_accepts_*` line whose axiom pin is anything other than the full
`native_decide` set is a RED flag, not a clean bill of health.

IDENTITY: `flats/programmable_logic_base.flat` pinned by
`flats/MANIFEST.md` (`scripts/extract-flats.sh --check` must be green);
BuiltinSemanticsVariant E via `cekExecuteProgram`'s pinned default; fuel
1600. See `Cip113Spike/PrepBase.lean` for the evidence chain.

FALSIFICATION: a green theorem here is not evidence on its own. The
control that makes it evidence is `controls/MutantControl.lean`, driven
by `scripts/falsification-control.sh`, which rebuilds PLB through the
real Aiken pipeline with the step-4 equality gutted to `True` and
requires the accepting/rejecting pairs below to flip.
-/
import Cip113Spike.PrepBase
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.IsData.Class.IsData (toData)
open CardanoLedgerApi.V2 (TxOut)
open CardanoLedgerApi.V3 (Credential ScriptContext ScriptInfo TxInInfo TxOutRef Withdrawals
  validRewardingContext validSpendingContext)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Data (Data)
open PlutusCore.UPLC.CekMachine (State)
open PlutusCore.UPLC.Term (Term)
open PlutusCore.UPLC.Utils (isSuccessful)

set_option maxHeartbeats 0

-- The acceptance theorems lift a decided `isHaltB … = true` through
-- `isHaltB_sound`, and elaborating that lift unfolds a 1600-step CEK
-- state; the default recursion depth is not enough for it.
set_option maxRecDepth 8000

-- ===================================================================
-- Fixtures
-- ===================================================================

/-- The deployment parameter: the protocol-params NFT policy. A tag, not
a 28-byte hash — PLB compares this policy by byte equality only. -/
def paramsPolicy : ByteString := ByteString.mk "PPCS"

/-- The shared payment credential every programmable-token UTxO lives at
(params datum field 1). -/
def plbCred : Credential := .ScriptCredential (ByteString.mk "BASE")

/-- The three delegate credentials the params datum names, in fields 2,
3 and 4. Their four-byte tags are chosen so that BYTEWISE they sort
`3RDP` (0x33…) < `TRSF` (0x54…) < `UNFR` (0x55…) — i.e. the ledger
presents them to PLB at withdrawal indices 0, 1 and 2 respectively, and
the fixtures never have to invent an order the ledger would not produce.
-/
def transferCred : Credential := .ScriptCredential (ByteString.mk "TRSF")

def thirdPartyCred : Credential := .ScriptCredential (ByteString.mk "3RDP")

def unfrackingCred : Credential := .ScriptCredential (ByteString.mk "UNFR")

/-- A credential belonging to nobody in the protocol — an issuer's own
logic script, an unrelated staking script. Sorts LAST (`ZZZZ`, 0x5A…),
so appending it to the delegate map keeps the map in ledger order. -/
def foreignCred : Credential := .ScriptCredential (ByteString.mk "ZZZZ")

/-- Protocol-params datum: `ProgrammableLogicGlobalParams`, `Constr 0`
with SEVEN fields in declaration order (`programmable_logic/params.ak`):
registry_node_cs, prog_logic_cred, transfer_cred, third_party_cred,
unfracking_cred, upgrade_cred, max_inline_datum_bytes. PLB reads exactly
one of fields 2/3/4, chosen by its redeemer. -/
def paramsDatum : Data :=
  Data.Constr 0
    [ Data.B (ByteString.mk "RCS")
    , toData plbCred
    , toData transferCred
    , toData thirdPartyCred
    , toData unfrackingCred
    , toData (Credential.ScriptCredential (ByteString.mk "UPGR"))
    , Data.I 512 ]

/-- A value with an ada entry first (canonical) and one further policy. -/
def valueWith (pid name : ByteString) (q : Int) :
    CardanoLedgerApi.V1.Value.Value :=
  [ (Data.B (ByteString.mk ""), Data.Map [(Data.B (ByteString.mk ""), Data.I 2000000)])
  , (Data.B pid, Data.Map [(Data.B name, Data.I q)]) ]

/-- Ada-only value. -/
def adaOnly (q : Int) : CardanoLedgerApi.V1.Value.Value :=
  [(Data.B (ByteString.mk ""), Data.Map [(Data.B (ByteString.mk ""), Data.I q)])]

/-- The protocol-params reference output. `with_protocol_params_fields`
authenticates it by mere PRESENCE of the params policy (it is a one-shot
NFT) and then reads its inline datum. -/
def paramsRefOut : TxOut :=
  { txOutAddress := ⟨.ScriptCredential (ByteString.mk "HOLD"), none⟩
  , txOutValue := valueWith paramsPolicy (ByteString.mk "ProtocolParams") 1
  , txOutDatum := .OutputDatum paramsDatum
  , txOutReferenceScript := none }

/-- Same UTxO, same datum, WITHOUT the params NFT — the impersonation
attempt the presence check exists to stop. -/
def unauthRefOut : TxOut := { paramsRefOut with txOutValue := adaOnly 2000000 }

/-- Same UTxO, params NFT present, but no inline datum. -/
def noDatumRefOut : TxOut := { paramsRefOut with txOutDatum := .NoOutputDatum }

def outRef : TxOutRef := ⟨ByteString.mk "", 0⟩

/-- The protocol-params reference input, and the two spoiled variants.
Reference inputs are presented by the ledger sorted by `TxOutRef`, so
where two appear below they ascend. -/
def paramsRefIn : TxInInfo := ⟨⟨ByteString.mk "", 2⟩, paramsRefOut⟩

def unauthRefIn : TxInInfo := ⟨⟨ByteString.mk "", 2⟩, unauthRefOut⟩

def noDatumRefIn : TxInInfo := ⟨⟨ByteString.mk "", 2⟩, noDatumRefOut⟩

/-- A reference input that is NOT the params UTxO and sorts BEFORE it —
a reference script, say. Present so `params_idx` has something wrong to
point at. -/
def decoyRefIn : TxInInfo := ⟨⟨ByteString.mk "", 1⟩, unauthRefOut⟩

/-- The spent programmable-token UTxO. PLB never inspects it (its datum
and own-ref arguments are both `_`), so it stays minimal: ada-only, and
exactly the fee, which keeps `isBalanced` true with no outputs. -/
def resolved : TxOut :=
  { txOutAddress := ⟨plbCred, none⟩
  , txOutValue := adaOnly 100
  , txOutDatum := .NoOutputDatum
  , txOutReferenceScript := none }

/-- Validity interval [0, 1], both bounds finite and closed. -/
def range : Data :=
  Data.Constr 0 [ Data.Constr 0 [Data.Constr 1 [Data.I 0], Data.Constr 1 []]
                , Data.Constr 0 [Data.Constr 1 [Data.I 1], Data.Constr 1 []] ]

/-- `BaseSpendRedeemer` (`lib/types.ak`): three constructors, each
carrying `{ params_idx, wdrl_idx }`. -/
def viaTransfer (paramsIdx wdrlIdx : Int) : Data :=
  Data.Constr 0 [Data.I paramsIdx, Data.I wdrlIdx]

def viaThirdParty (paramsIdx wdrlIdx : Int) : Data :=
  Data.Constr 1 [Data.I paramsIdx, Data.I wdrlIdx]

def viaUnfracking (paramsIdx wdrlIdx : Int) : Data :=
  Data.Constr 2 [Data.I paramsIdx, Data.I wdrlIdx]

/-- The script info of an ordinary PLB spend. -/
def spendInfo : ScriptInfo := .SpendingScript outRef none

/-- THE shared context builder. Everything the theorems vary is an
argument; everything else is fixed, so any two contexts below differ by
exactly what their names say. The redeemer is threaded into BOTH slots
the ledger fills (`scriptContextRedeemer` and the `txInfoRedeemers`
entry for this script's purpose), and the purpose is derived from
`info`, so the pair cannot fall out of step. -/
def mkCtx (refIns : List TxInInfo) (wdrl : Withdrawals) (rdmr : Data)
    (info : ScriptInfo) : ScriptContext :=
  { scriptContextTxInfo :=
    { txInfoInputs := [⟨outRef, resolved⟩]
    , txInfoReferenceInputs := refIns
    , txInfoOutputs := []
    , txInfoFee := 100
    , txInfoMint := []
    , txInfoTxCerts := []
    , txInfoWdrl := wdrl
    , txInfoValidRange := range
    , txInfoSignatories := []
    , txInfoRedeemers := [(info.toScriptPurpose, rdmr)]
    , txInfoData := []
    , txInfoId := ByteString.mk ""
    , txInfoVotes := []
    , txInfoProposalProcedures := []
    -- `Maybe Lovelace` fields: the V3 encoder maps `Nothing` to
    -- `Constr 1 []`; bare `Data.I 1` is outside the encoder image, so no
    -- ledger-produced context would carry it.
    , txInfoCurrentTreasuryAmount := Data.Constr 1 []
    , txInfoTreasuryDonation := Data.Constr 1 [] }
  , scriptContextRedeemer := rdmr
  , scriptContextScriptInfo := info }

/-- The withdrawal map of a live protocol: all three delegates
registered, IN LEDGER ORDER (see `transferCred` above) — third_party at
0, transfer at 1, unfracking at 2. Withdraw-zero, so every amount is 0.
-/
def delegateWdrls : Withdrawals :=
  [(thirdPartyCred, 0), (transferCred, 0), (unfrackingCred, 0)]

/-- The same map with one unrelated script's withdrawal appended —
still ledger-ordered, since `ZZZZ` sorts after `UNFR`. -/
def delegateWdrlsPlusForeign : Withdrawals :=
  delegateWdrls ++ [(foreignCred, 0)]

/-- Boolean reflection of CEK success, so concrete runs are decidable
(`isSuccessful` itself is a Prop with no Decidable instance) — the
wsc-poc `isHaltB` idiom. -/
def isHaltB : State → Bool
  | .Halt _ => true
  | _ => false

theorem isHaltB_sound (s : State) : isHaltB s = true → isSuccessful s := by
  intro h; cases s <;> simp [isHaltB] at h <;> trivial

/-- Same reflection for the accepting HALT VALUE. `isHaltB` accepts any
`.Halt _`; the PlutusV3 wrapper is required to return the unit constant
(CIP-117), and `CekValue` derives only `Repr`, so the check goes through
a Bool matcher. -/
def haltIsUnitB : State → Bool
  | .Halt (.VCon .Unit) => true
  | _ => false

theorem haltIsUnitB_sound (s : State) :
    haltIsUnitB s = true →
    PlutusCore.UPLC.Utils.fromHaltState s = some (.VCon .Unit) := by
  intro h
  cases s with
  | Halt cv =>
    cases cv with
    | VCon c => cases c <;> simp_all [haltIsUnitB, PlutusCore.UPLC.Utils.fromHaltState]
    | _ => simp [haltIsUnitB] at h
  | _ => simp [haltIsUnitB] at h

-- ===================================================================
-- Contexts
--
-- Every context below is `mkCtx` with at most a couple of arguments
-- changed against `ctxTransferAt1`, the accepting transfer-arm case, so
-- each theorem's delta against an accepting run is visible in one line.
-- ===================================================================

-- Dispatch matrix: ONE live protocol (all three delegates withdrawing,
-- in ledger order), NINE redeemers. The arm chooses the params-datum
-- field; `wdrl_idx` chooses the withdrawal. Only the three where the two
-- agree may spend.
def ctxTransferAt0 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaTransfer 0 0) spendInfo

def ctxTransferAt1 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaTransfer 0 1) spendInfo

def ctxTransferAt2 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaTransfer 0 2) spendInfo

def ctxThirdPartyAt0 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaThirdParty 0 0) spendInfo

def ctxThirdPartyAt1 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaThirdParty 0 1) spendInfo

def ctxThirdPartyAt2 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaThirdParty 0 2) spendInfo

def ctxUnfrackingAt0 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaUnfracking 0 0) spendInfo

def ctxUnfrackingAt1 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaUnfracking 0 1) spendInfo

def ctxUnfrackingAt2 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaUnfracking 0 2) spendInfo

/-- A minimal protocol: only the transfer delegate withdraws. The twin
for the two one-entry rejections below. -/
def ctxSoloDelegate : ScriptContext :=
  mkCtx [paramsRefIn] [(transferCred, 0)] (viaTransfer 0 0) spendInfo

/-- One delta from `ctxSoloDelegate`: the single withdrawal belongs to
somebody else entirely. -/
def ctxForeignOnly : ScriptContext :=
  mkCtx [paramsRefIn] [(foreignCred, 0)] (viaTransfer 0 0) spendInfo

/-- One delta from `ctxSoloDelegate`: the same 28 bytes as the transfer
delegate, keyed under a VERIFICATION-KEY credential instead of a script
one. Kept to a one-entry map deliberately: a mixed map would have to
take a position on where the ledger sorts a vkey entry relative to a
script one, and the harness's own `validWithdrawals` disagrees with the
node on exactly that (see the FINDINGS note at the bottom). -/
def ctxVkeyTaggedDelegate : ScriptContext :=
  mkCtx [paramsRefIn] [(.PubKeyCredential (ByteString.mk "TRSF"), 0)]
    (viaTransfer 0 0) spendInfo

/-- The live protocol plus one unrelated script's withdrawal. Ledger
order is preserved (`ZZZZ` sorts after `UNFR`), so the delegate is still
at index 1 — the accepting twin for `ctxFourEntryAt3`. -/
def ctxFourEntryAt1 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrlsPlusForeign (viaTransfer 0 1) spendInfo

/-- One delta: `wdrl_idx` points at a REAL withdrawal in the same
transaction that simply is not the transfer delegate's. -/
def ctxFourEntryAt3 : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrlsPlusForeign (viaTransfer 0 3) spendInfo

/-- One delta from `ctxTransferAt1`: `wdrl_idx` runs off the end of the
map, so `list.expect_at` never returns. -/
def ctxWdrlIdxOutOfRange : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaTransfer 0 7) spendInfo

/-- One delta from `ctxTransferAt1`: the addressed reference input still
carries the genuine params datum but NOT the params NFT — the
impersonation the presence check exists to stop. -/
def ctxUnauthenticatedParams : ScriptContext :=
  mkCtx [unauthRefIn] delegateWdrls (viaTransfer 0 1) spendInfo

/-- One delta from `ctxTransferAt1`: the params NFT is there, the inline
datum is not. -/
def ctxParamsWithoutDatum : ScriptContext :=
  mkCtx [noDatumRefIn] delegateWdrls (viaTransfer 0 1) spendInfo

/-- Two reference inputs, ledger-ordered: a decoy at 0, the genuine
params UTxO at 1. `params_idx: 1` addresses the real one — the accepting
twin that shows the params UTxO need not be first. -/
def ctxParamsIdx1 : ScriptContext :=
  mkCtx [decoyRefIn, paramsRefIn] delegateWdrls (viaTransfer 1 1) spendInfo

/-- One delta: `params_idx: 0` addresses the decoy instead. -/
def ctxParamsIdx0 : ScriptContext :=
  mkCtx [decoyRefIn, paramsRefIn] delegateWdrls (viaTransfer 0 1) spendInfo

/-- PLB runs once per programmable input, so a real transfer spends
several of them at once. Two PLB inputs, everything else as
`ctxTransferAt1` (fee raised to keep the transaction balanced). PLB
reads neither `_datum` nor `_own_ref`, so this must still accept — a
WITNESS that the family with N>1 inputs is inhabited, not an implication
a narrowing mutant could satisfy vacuously (standing rule R2b). -/
def ctxTwoInputs : ScriptContext :=
  { ctxTransferAt1 with
    scriptContextTxInfo :=
      { ctxTransferAt1.scriptContextTxInfo with
        txInfoInputs :=
          [⟨outRef, resolved⟩, ⟨⟨ByteString.mk "", 3⟩, resolved⟩]
        txInfoFee := 200 } }

/-- A structurally different validity interval — open below, unbounded
above, so both the bounds AND their finiteness differ from `range`. PLB
never inspects the range; the accepting pair (this and
`ctxTransferAt1`) is the witness-set form of that independence. The
relational rung — `accepts(ctx, r₁) ↔ accepts(ctx, r₂)` for symbolic
`r` — needs a family with the range as a symbolic leaf, and is deferred
with the rest of the quantified tier. -/
def rangeVariant : Data :=
  Data.Constr 0 [ Data.Constr 0 [Data.Constr 0 [], Data.Constr 1 []]
                , Data.Constr 0 [Data.Constr 2 [], Data.Constr 1 []] ]

def ctxRangeVariant : ScriptContext :=
  { ctxTransferAt1 with
    scriptContextTxInfo :=
      { ctxTransferAt1.scriptContextTxInfo with
        txInfoValidRange := rangeVariant } }

/-- The accepting transfer context under a REWARDING purpose. PLB is a
spend validator; no node invokes it this way. This is a ledger-valid
REWARDING context (asserted below), so the rejection is not an artefact
of a malformed fixture. -/
def ctxRewardingPurpose : ScriptContext :=
  mkCtx [paramsRefIn] delegateWdrls (viaTransfer 0 1) (.RewardingScript transferCred)

-- ===================================================================
-- Ledger realism
--
-- R2/R1 in the tree's standing rules, and the lesson of commit 5ad457a:
-- a rejection on a context no node could produce proves nothing. Every
-- spend-purpose fixture above satisfies the CardanoLedgerApiBlaster
-- ledger rules for a spending script context (ascending outrefs, canonical
-- values, ledger-ordered withdrawals, redeemer map agreeing with the
-- purpose, balanced), and the rewarding one satisfies the rewarding rules.
-- ===================================================================

def spendFixtures : List ScriptContext :=
  [ ctxTransferAt0, ctxTransferAt1, ctxTransferAt2
  , ctxThirdPartyAt0, ctxThirdPartyAt1, ctxThirdPartyAt2
  , ctxUnfrackingAt0, ctxUnfrackingAt1, ctxUnfrackingAt2
  , ctxSoloDelegate, ctxForeignOnly, ctxVkeyTaggedDelegate
  , ctxFourEntryAt1, ctxFourEntryAt3, ctxWdrlIdxOutOfRange
  , ctxUnauthenticatedParams, ctxParamsWithoutDatum
  , ctxParamsIdx1, ctxParamsIdx0
  , ctxTwoInputs, ctxRangeVariant ]

theorem spend_fixtures_are_ledger_shaped :
    spendFixtures.all validSpendingContext = true := by native_decide

theorem rewarding_fixture_is_ledger_shaped :
    validRewardingContext ctxRewardingPurpose = true := by native_decide

-- ===================================================================
-- Preps — one per context, all at fuel 1600 (see the module header for
-- why the families are concrete and why 1600).
-- ===================================================================

def inTransferAt0 : List Term := baseInputs paramsPolicy ctxTransferAt0
def inTransferAt1 : List Term := baseInputs paramsPolicy ctxTransferAt1
def inTransferAt2 : List Term := baseInputs paramsPolicy ctxTransferAt2
def inThirdPartyAt0 : List Term := baseInputs paramsPolicy ctxThirdPartyAt0
def inThirdPartyAt1 : List Term := baseInputs paramsPolicy ctxThirdPartyAt1
def inThirdPartyAt2 : List Term := baseInputs paramsPolicy ctxThirdPartyAt2
def inUnfrackingAt0 : List Term := baseInputs paramsPolicy ctxUnfrackingAt0
def inUnfrackingAt1 : List Term := baseInputs paramsPolicy ctxUnfrackingAt1
def inUnfrackingAt2 : List Term := baseInputs paramsPolicy ctxUnfrackingAt2
def inSoloDelegate : List Term := baseInputs paramsPolicy ctxSoloDelegate
def inForeignOnly : List Term := baseInputs paramsPolicy ctxForeignOnly
def inVkeyTaggedDelegate : List Term := baseInputs paramsPolicy ctxVkeyTaggedDelegate
def inFourEntryAt1 : List Term := baseInputs paramsPolicy ctxFourEntryAt1
def inFourEntryAt3 : List Term := baseInputs paramsPolicy ctxFourEntryAt3
def inWdrlIdxOutOfRange : List Term := baseInputs paramsPolicy ctxWdrlIdxOutOfRange
def inUnauthenticatedParams : List Term := baseInputs paramsPolicy ctxUnauthenticatedParams
def inParamsWithoutDatum : List Term := baseInputs paramsPolicy ctxParamsWithoutDatum
def inParamsIdx1 : List Term := baseInputs paramsPolicy ctxParamsIdx1
def inParamsIdx0 : List Term := baseInputs paramsPolicy ctxParamsIdx0
def inTwoInputs : List Term := baseInputs paramsPolicy ctxTwoInputs
def inRangeVariant : List Term := baseInputs paramsPolicy ctxRangeVariant
def inRewardingPurpose : List Term := baseInputs paramsPolicy ctxRewardingPurpose

#prep_uplc appliedTransferAt0 programmableLogicBase inTransferAt0 1600
#prep_uplc appliedTransferAt1 programmableLogicBase inTransferAt1 1600
#prep_uplc appliedTransferAt2 programmableLogicBase inTransferAt2 1600
#prep_uplc appliedThirdPartyAt0 programmableLogicBase inThirdPartyAt0 1600
#prep_uplc appliedThirdPartyAt1 programmableLogicBase inThirdPartyAt1 1600
#prep_uplc appliedThirdPartyAt2 programmableLogicBase inThirdPartyAt2 1600
#prep_uplc appliedUnfrackingAt0 programmableLogicBase inUnfrackingAt0 1600
#prep_uplc appliedUnfrackingAt1 programmableLogicBase inUnfrackingAt1 1600
#prep_uplc appliedUnfrackingAt2 programmableLogicBase inUnfrackingAt2 1600
#prep_uplc appliedSoloDelegate programmableLogicBase inSoloDelegate 1600
#prep_uplc appliedForeignOnly programmableLogicBase inForeignOnly 1600
#prep_uplc appliedVkeyTaggedDelegate programmableLogicBase inVkeyTaggedDelegate 1600
#prep_uplc appliedFourEntryAt1 programmableLogicBase inFourEntryAt1 1600
#prep_uplc appliedFourEntryAt3 programmableLogicBase inFourEntryAt3 1600
#prep_uplc appliedWdrlIdxOutOfRange programmableLogicBase inWdrlIdxOutOfRange 1600
#prep_uplc appliedUnauthenticatedParams programmableLogicBase inUnauthenticatedParams 1600
#prep_uplc appliedParamsWithoutDatum programmableLogicBase inParamsWithoutDatum 1600
#prep_uplc appliedParamsIdx1 programmableLogicBase inParamsIdx1 1600
#prep_uplc appliedParamsIdx0 programmableLogicBase inParamsIdx0 1600
#prep_uplc appliedTwoInputs programmableLogicBase inTwoInputs 1600
#prep_uplc appliedRangeVariant programmableLogicBase inRangeVariant 1600
#prep_uplc appliedRewardingPurpose programmableLogicBase inRewardingPurpose 1600

-- ===================================================================
-- 1. The dispatch matrix — the theorem set that makes the three arms
--    meaningfully distinct.
--
-- One live protocol, one ledger-ordered withdrawal map holding all three
-- delegates, nine redeemers. PLB accepts exactly the three where the
-- arm's params-datum field and the witnessed withdrawal agree, and
-- rejects all six mismatches. Read as a table:
--
--                    wdrl_idx 0     wdrl_idx 1     wdrl_idx 2
--                    (3RDP)         (TRSF)         (UNFR)
--   SpendViaTransfer     reject        ACCEPT         reject
--   SpendViaThirdParty   ACCEPT        reject         reject
--   SpendViaUnfracking   reject        reject         ACCEPT
--
-- Every off-diagonal entry is one delta (the redeemer) away from a
-- diagonal one, so each rejection is localised to the dispatch, not to
-- some incidental difference in the transaction.
-- ===================================================================

theorem exec_accepts_transfer_arm :
    isSuccessful appliedTransferAt1.exec :=
  isHaltB_sound _ (by native_decide)

theorem exec_accepts_third_party_arm :
    isSuccessful appliedThirdPartyAt0.exec :=
  isHaltB_sound _ (by native_decide)

theorem exec_accepts_unfracking_arm :
    isSuccessful appliedUnfrackingAt2.exec :=
  isHaltB_sound _ (by native_decide)

theorem exec_rejects_transfer_arm_at_third_party_delegate :
    isHaltB appliedTransferAt0.exec = false := by native_decide

theorem exec_rejects_transfer_arm_at_unfracking_delegate :
    isHaltB appliedTransferAt2.exec = false := by native_decide

theorem exec_rejects_third_party_arm_at_transfer_delegate :
    isHaltB appliedThirdPartyAt1.exec = false := by native_decide

theorem exec_rejects_third_party_arm_at_unfracking_delegate :
    isHaltB appliedThirdPartyAt2.exec = false := by native_decide

theorem exec_rejects_unfracking_arm_at_third_party_delegate :
    isHaltB appliedUnfrackingAt0.exec = false := by native_decide

theorem exec_rejects_unfracking_arm_at_transfer_delegate :
    isHaltB appliedUnfrackingAt1.exec = false := by native_decide

-- ===================================================================
-- 2. The witnessed credential must BE the delegate's.
-- ===================================================================

/-- Non-vacuity twin for the two rejections below: with the delegate
alone in the map, the same redeemer accepts. -/
theorem exec_accepts_sole_delegate_withdrawal :
    isSuccessful appliedSoloDelegate.exec :=
  isHaltB_sound _ (by native_decide)

/-- No delegate withdrawal in the transaction at all: the witnessed
entry belongs to an unrelated script. -/
theorem exec_rejects_foreign_withdrawal :
    isHaltB appliedForeignOnly.exec = false := by native_decide

/-- The compiled credential equality is TAG-sensitive: the delegate's 28
bytes under a verification-key credential are not the delegate. -/
theorem exec_rejects_vkey_tagged_delegate :
    isHaltB appliedVkeyTaggedDelegate.exec = false := by native_decide

-- ===================================================================
-- 3. `wdrl_idx` is trusted blindly, and is therefore self-validating:
--    a wrong index resolves to a credential that fails the equality.
-- ===================================================================

/-- Twin: an extra, unrelated withdrawal in the transaction does not
disturb the delegate's ledger position, and the spend still goes
through. -/
theorem exec_accepts_four_entry_map :
    isSuccessful appliedFourEntryAt1.exec :=
  isHaltB_sound _ (by native_decide)

/-- One delta from the twin: the index addresses a REAL withdrawal of
the same transaction that is not the delegate's. -/
theorem exec_rejects_wdrl_idx_at_foreign_withdrawal :
    isHaltB appliedFourEntryAt3.exec = false := by native_decide

/-- An index past the end of the map cannot resolve at all. -/
theorem exec_rejects_out_of_range_wdrl_idx :
    isHaltB appliedWdrlIdxOutOfRange.exec = false := by native_decide

-- ===================================================================
-- 4. The delegate credentials must come from the AUTHENTICATED params
--    UTxO — the whole point of parameterising PLB by the NFT policy
--    rather than by a credential.
-- ===================================================================

/-- A UTxO carrying a forged params datum but no params NFT cannot name
the delegate. Twin: `exec_accepts_transfer_arm`, which is this context
with the NFT restored. -/
theorem exec_rejects_unauthenticated_params_input :
    isHaltB appliedUnauthenticatedParams.exec = false := by native_decide

/-- The authenticated UTxO must carry an INLINE datum; a datum-less one
is not a params UTxO. -/
theorem exec_rejects_params_input_without_inline_datum :
    isHaltB appliedParamsWithoutDatum.exec = false := by native_decide

/-- Twin: the params UTxO need not be the first reference input —
`params_idx` addresses it wherever the ledger's outref order puts it. -/
theorem exec_accepts_params_at_reference_index_one :
    isSuccessful appliedParamsIdx1.exec :=
  isHaltB_sound _ (by native_decide)

/-- One delta: the same transaction, `params_idx` addressing the decoy
reference input instead. A wrong index fails the NFT check rather than
silently reading another UTxO's datum. -/
theorem exec_rejects_params_idx_at_non_params_reference_input :
    isHaltB appliedParamsIdx0.exec = false := by native_decide

-- ===================================================================
-- 5. Independence witnesses (R2b: witness-set form, never an
--    implication a narrowing mutant would satisfy for free).
-- ===================================================================

/-- Several programmable inputs in one transaction still spend. -/
theorem exec_accepts_two_plb_inputs :
    isSuccessful appliedTwoInputs.exec :=
  isHaltB_sound _ (by native_decide)

/-- A structurally different validity interval still spends. -/
theorem exec_accepts_range_variant :
    isSuccessful appliedRangeVariant.exec :=
  isHaltB_sound _ (by native_decide)

-- ===================================================================
-- 6. Dispatch gate and halt value.
-- ===================================================================

/-- PLB is a spend validator. Under a rewarding purpose the ledger never
reaches its body: the purpose-gated `spendingInputs` feeds the
spend-shaped application `Term.Error`, so the run cannot reach Halt.
Honest scope: this pins the LEDGER dispatch gate (the `else(_) { fail }`
arm is unreachable from a reward purpose), not an in-body branch. The
one-field twin is `exec_accepts_transfer_arm`, which does reach Halt. -/
theorem exec_rejects_nonspend_purpose :
    isHaltB appliedRewardingPurpose.exec = false := by native_decide

/-- The accepting run returns the unit constant, as CIP-117 requires of
a PlutusV3 validator — `isHaltB` alone would accept any `.Halt _`. -/
theorem exec_accepts_unit :
    PlutusCore.UPLC.Utils.fromHaltState appliedTransferAt1.exec = some (.VCon .Unit) :=
  haltIsUnitB_sound _ (by native_decide)

-- ===================================================================
-- Claim-integrity gate (C12/V20): pin the axiom set of every theorem so
-- `lake build` goes RED on drift — a stray `sorry` surfaces `sorryAx`, a
-- `native_decide` swapped for `blaster` swaps `ofReduceBool` +
-- `trustCompiler` for `blasterProven`. Whitespace is normalized, so the
-- wrapped pretty-printer output compares as a single line.
--
-- Every theorem in this module is KERNEL-PROVED by `native_decide` over
-- a concrete CEK run, so every line below must show exactly
-- [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound].
-- ===================================================================

-- The two reflection lemmas first: they are ordinary Lean proofs, and
-- their axiom sets are what tells the reader that the `native_decide`
-- axioms in every line below come from the CEK runs and from nowhere
-- else.
/-- info: 'CIP113.isHaltB_sound' depends on axioms: [propext] -/
#guard_msgs(whitespace := lax) in #print axioms isHaltB_sound
/-- info: 'CIP113.haltIsUnitB_sound' depends on axioms: [propext] -/
#guard_msgs(whitespace := lax) in #print axioms haltIsUnitB_sound
/-- info: 'CIP113.spend_fixtures_are_ledger_shaped' depends on axioms: [propext, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms spend_fixtures_are_ledger_shaped
/-- info: 'CIP113.rewarding_fixture_is_ledger_shaped' depends on axioms: [propext, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms rewarding_fixture_is_ledger_shaped
/-- info: 'CIP113.exec_accepts_transfer_arm' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_transfer_arm
/-- info: 'CIP113.exec_accepts_third_party_arm' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_third_party_arm
/-- info: 'CIP113.exec_accepts_unfracking_arm' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_unfracking_arm
/-- info: 'CIP113.exec_rejects_transfer_arm_at_third_party_delegate' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_transfer_arm_at_third_party_delegate
/-- info: 'CIP113.exec_rejects_transfer_arm_at_unfracking_delegate' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_transfer_arm_at_unfracking_delegate
/-- info: 'CIP113.exec_rejects_third_party_arm_at_transfer_delegate' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_third_party_arm_at_transfer_delegate
/-- info: 'CIP113.exec_rejects_third_party_arm_at_unfracking_delegate' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_third_party_arm_at_unfracking_delegate
/-- info: 'CIP113.exec_rejects_unfracking_arm_at_third_party_delegate' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_unfracking_arm_at_third_party_delegate
/-- info: 'CIP113.exec_rejects_unfracking_arm_at_transfer_delegate' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_unfracking_arm_at_transfer_delegate
/-- info: 'CIP113.exec_accepts_sole_delegate_withdrawal' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_sole_delegate_withdrawal
/-- info: 'CIP113.exec_rejects_foreign_withdrawal' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_foreign_withdrawal
/-- info: 'CIP113.exec_rejects_vkey_tagged_delegate' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_vkey_tagged_delegate
/-- info: 'CIP113.exec_accepts_four_entry_map' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_four_entry_map
/-- info: 'CIP113.exec_rejects_wdrl_idx_at_foreign_withdrawal' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_wdrl_idx_at_foreign_withdrawal
/-- info: 'CIP113.exec_rejects_out_of_range_wdrl_idx' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_out_of_range_wdrl_idx
/-- info: 'CIP113.exec_rejects_unauthenticated_params_input' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_unauthenticated_params_input
/-- info: 'CIP113.exec_rejects_params_input_without_inline_datum' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_params_input_without_inline_datum
/-- info: 'CIP113.exec_accepts_params_at_reference_index_one' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_params_at_reference_index_one
/-- info: 'CIP113.exec_rejects_params_idx_at_non_params_reference_input' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_params_idx_at_non_params_reference_input
/-- info: 'CIP113.exec_accepts_two_plb_inputs' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_two_plb_inputs
/-- info: 'CIP113.exec_accepts_range_variant' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_range_variant
/-- info: 'CIP113.exec_rejects_nonspend_purpose' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_rejects_nonspend_purpose
/-- info: 'CIP113.exec_accepts_unit' depends on axioms: [propext, Classical.choice, Lean.ofReduceBool, Lean.trustCompiler, Quot.sound] -/
#guard_msgs(whitespace := lax) in #print axioms exec_accepts_unit

-- ===================================================================
-- FINDINGS for the slices that follow this one.
--
-- (1) THE HARNESS AND THE NODE DISAGREE ON WITHDRAWAL ORDER when a map
--     mixes credential kinds. `validWithdrawals` sorts by
--     CardanoLedgerApiBlaster's `ltCredential`
--     (`CardanoLedgerApi/V1/Credential.lean`), which puts
--     `PubKeyCredential` BEFORE `ScriptCredential` — the constructor
--     order of the PLUTUS `Credential`. The node sorts reward accounts
--     by the LEDGER's `Credential`, whose first constructor is
--     `ScriptHashObj`, i.e. Script before Key, and hands Plutus that
--     order verbatim. So for a mixed map the harness would bless an
--     order no node can produce and reject the order every node does
--     produce. Every fixture above stays inside the region where the two
--     agree: script-only maps (both then compare bytewise on the hash),
--     and a ONE-entry map for the vkey-tag case. A slice that needs a
--     mixed map must not take `validSpendingContext` as authority on its
--     ordering — this is the same class of mistake as commit 5ad457a,
--     one layer up.
--
-- (2) STEP COUNT IS NOT MONOTONE IN THE INDICES WALKED (the sawtooth in
--     the header table), so `transfer` / `third_party` / `unfracking`
--     cannot inherit a fuel number from here or from each other.
--
-- (3) THE CONCRETE-FAMILY TECHNIQUE GENERALISES. The three delegate
--     validators are 2.0-2.3 kB — far past the symbolic-prep cliff that
--     already kills the 829-byte PLB — but a fully pinned context preps
--     in about a third of a second per family here, and `.exec` is the
--     same term either way. Concrete accepting contexts for them are the
--     real blocker, exactly as `PrepTransfer.lean` says; the prep is not.
-- ===================================================================

end CIP113
