# Invariant-gap review — cip113 PR #101, Lean/Blaster theorems over compiled PLB

Scope: formal-verification coverage analysis (invariant half), two passes.
Round 1 read the PR's Lean tier and the Aiken validators. Round 2 (marked
**[R2]**) additionally read, all read-only at head commit
`02c7b86397f7660c8f479b20cc544a099269a7d5`: `FORMAL_VERIFICATION_STATUS.md`,
the CI workflow, `lakefile.lean` + `lake-manifest.json`, `Smoke.lean`,
`README.md`, both scripts, `lib/pairs.ak`, the PLG delegate sources — and the
**three upstream Lean dependencies at their pinned revs** (Lean-blaster
`083bae79`, PlutusCoreBlaster `a04042c4`, CardanoLedgerApiBlaster `5dab3c43`):
`Utils.lean`, `CekMachine.lean`, `PreProcess.lean`, `Command/Tactic.lean`,
`V3/Contexts.lean`. No build was run; no write touched his repo.

Round-2 headline: three new candidates (C12–C14) came out of the upstream
sources — the `warn.sorry false` / axiom-gate hole, the `.prop`-vs-`.exec`
optimizer trust link, and the CEK **step-budget (fuel) semantics**, which
turns out to sharpen C7, C8 and C10 as well. One round-1 candidate (C9) was
already on his own next-rungs list and is re-credited accordingly.

## 1. What the five theorems prove, precisely

All five statements are about `appliedBase` — the 141-byte compiled
`programmable_logic_base.spend` artifact (identity: Aiken v1.1.22+39d6b04,
PlutusV3, `BuiltinSemanticsVariant` E), applied to a parameter and a
`ScriptContext` built by `mkCtx`, which fixes **everything** in the
transaction except the withdrawal map: one PLB input, empty
outputs/mint/certs/signatories/votes, fee 100, one concrete spend redeemer
`Constr 0 []`, script info `SpendingScript outRef none` (no datum). Two
theorems are kernel-checked concrete CEK executions: `exec_accepts` (map
`[(stakeCred, 0)]` succeeds) and `exec_rejects_foreign_withdrawal` (map
`[(Script "EVE", 0)]` does not reach `Halt`). Three theorems are SMT-VALID
(Z3 via `blaster`, entering Lean through the `blasterProven` axiom): for
every deployment parameter and every withdrawal map of exactly 1, 2, or 4
entries **whose keys are all `ScriptCredential`** (symbolic hashes, symbolic
integer amounts), acceptance implies at least one entry's hash equals the
parameter.

**[R2] Three precision refinements from the upstream sources.** (a) The
kernel pair runs `appliedBase.exec` (the raw
`cekExecuteProgram` application); the SMT ladder is stated over
`appliedBase.prop`, a *different definition* — the Blaster-optimizer's output
(see C13). (b) Both bake in the `#prep_uplc` budget **600 as CEK fuel**:
PCB's `runSteps` returns `State.Error` when fuel is exhausted, so every
"acceptance" hypothesis really reads "halts within 600 machine steps" (see
C14). (c) "Success" is `isSuccessful = isHaltState` — *any* halt value
counts; the model never checks the CIP-117 PlutusV3 rule that the script
must return unit (see C14). None of these breaks the safety direction of the
proven implications; all three belong in the claims' fine print.

## 2. What's genuinely strong

- **The accept/reject `native_decide` pair is the right discipline.**
  Non-vacuity and polarity demonstrated on the real CEK against the real
  bytes. **[R2]** The pair does double duty nobody advertises: it also
  kernel-certifies that the 1-entry family halts within the 600-step fuel —
  the only rung so certified (see C10/C14).
- **∀-over-the-deployment-parameter is the right quantifier.** The
  forwarding theorems survive redeployment with a different PLG credential —
  claims about the script template, not one instance.
- **The identity discipline is mechanised, not prose.** `MANIFEST.md` pins
  toolchain from the blueprint's own preamble (already caught a real
  v1.1.21/v1.1.22 drift), variant E with evidence down to the `Inhabited`
  instance, sha256s; **[R2]** and the consolidated CI workflow enforces the
  whole chain on one commit per push: aiken == preamble → clean rebuild
  reproduces `plutus.json` byte-for-byte → `extract-flats.sh --check` →
  `lake build`. The re-attestation staleness dance is genuinely gone.
- **The mutant control goes through the real pipeline** (mutated source →
  `aiken build` → extracted flat), and requires *both* the SMT theorem
  Falsified and the kernel-checked rejection flipped to acceptance —
  the harness shown able to fail at both evidence tiers.
- **[R2] The independent mutation-seed exercise is exceptional practice.**
  Sealed seeds authored by a different model than the suite's author, 3/3
  caught, and the unsealing analysis still found a real defect (six
  update-path negatives passing vacuously via the wrong `call_validator`).
  Very few teams run "don't let one person's imagination be the whole test"
  for real. The Lean tier deserves the same treatment (C10).

## 3. Invariant candidates

Each: (observation) · (why it matters) · (what would settle it) · label.
Phrased as questions Giovanni can answer or dismiss.

### C1 — Multi-input forwarding: does one withdrawal entry satisfying N PLB spends need its own rung?

**Observation.** `mkCtx` hardcodes one PLB input and one `SpendingScript
outRef`; every rung varies map width, never input count. "Each of N PLB
spends in one tx is individually forwarded" is in no proven family. At
source level this looks benign — the body reads only `self.withdrawals`,
ignores `own_ref`/datum, so N runs in one tx are pointwise identical checks —
but source-level independence is exactly the kind of claim this project
refuses to take on trust elsewhere.

**Why.** The unfrack composition ("one run per PLB input") and every
multi-input transfer rely on it. Note one entry satisfying many PLB inputs is
*by design* in the withdraw-0 pattern — PLG runs once and validates the whole
tx — so classic double-satisfaction risk lives in whether PLG accounts for
**all** programmable inputs (C5's territory), not in PLB. The PLB-side
question is only: is acceptance invariant in input count and own-ref?

**What would settle it.** A 2-PLB-input concrete witness (`native_decide`,
cheap) and/or a symbolic-inputs rung; or an invariance theorem over
`txInfoInputs`/`outRef`.

**Label: GAP** (proof-scope; plausibly benign at source, unproven at bytes).

### C2 — Uniqueness of the PLG entry: does anything rest on it?

**Observation.** The 2/4-entry conclusions are disjunctions — *at least one*
entry matches. `has_key_or_fail` returns at the first hit; later entries and
duplicates are never inspected.

**Why it seems not to matter.** On-chain `txInfoWdrl` comes from a ledger
map keyed by reward account — duplicate keys are ledger-unreachable — and
extra entries only add stake scripts that must *also* pass (the
restrictive-only composition argument `unfracking.ak`'s header makes
explicitly). I found no protocol guarantee resting on exactly-once.
Question: agreed that ledger map semantics carries uniqueness, so "at least
one" is the whole forwarding obligation?

**What would settle it.** A one-line note in the methodology; no theorem
needed if the argument is accepted.

**Label: COVERED** (ledger semantics + restrictive-only composition).

### C3 — Withdrawal amount: is zero load-bearing?

**Observation.** `amt`/`a1..a4` are symbolic and absent from every
conclusion; the proofs allow any amount, including negative.

**Why it seems fine — and better than fine.** Neither PLB (key comparison
only) nor PLG's `withdraw` handler reads the amount. "Withdraw-zero" is a
liveness convention (script stake creds accrue no rewards; the ledger's
withdraw-the-full-balance rule then forces 0), not a safety invariant — so
symbolic amounts make the theorems *stronger* than the idiom. **[R2]** The
convention is even self-enforcing: PLG's/unfracking's `publish` arms accept
only `RegisterCredential` and return `False` for everything else, so the
credential can never be delegated (delegation certs need the script witness)
— its reward balance is 0 forever, and withdraw-0 stays buildable. That
publish arm, though, is in no proven or (as far as I could see) tested
family — worth one Aiken test. It also seems to answer the status file's
open Conway question in the self-deregistration direction: `UnregCredential`
needs the script witness, and the script says no. The remaining half —
whether any cert path allows a *third party* to deregister without the
script witness — is a cardano-ledger rules check, as the status file already
says.

**Label: COVERED** (symbolic quantification broader than the convention);
one cheap Aiken test suggested for the publish arm.

### C4 — The true quantifier scope: one tx skeleton — which is not even a ledger-encodable one.

**Observation.** The prose ("proven for all deployments at once", "the
forwarding guarantee of the whole PLB", and the README's claims table) reads
wider than the statement: the real scope is *this one skeleton* — empty
outputs/mint, fee 100, datum `none`, `txInfoId ""`, fixed redeemer.
**[R2] Sharper:** CLAB types `txInfoCurrentTreasuryAmount` and
`txInfoTreasuryDonation` as raw `Data` ("keep at Data level") and injects
them verbatim, and `mkCtx` fills both with `Data.I 1`. Per plutus-ledger-api
V3 these fields are `Maybe Lovelace`, encoded `Constr 0 [I n]` /
`Constr 1 []` — a bare `I 1` is outside the V3 encoder's image. If that
reading is right, **strictly no ledger-produced context lies in any proven
family**: the theorems hold over a family disjoint from the reachable one.
Behaviorally inert here — both fields sit *after* `wdrl` in the TxInfo
constructor and the compiled scan's spine-walk never inspects them — but
"the source doesn't read it" is precisely the argument this effort refuses
to accept at bytes level elsewhere.

**Why.** §7.3 already says a claim's family is part of its statement; this
asks that the family be stated accurately next to the theorems — and be made
ledger-realistic, since the fix costs two tokens.

**What would settle it.** (i) Change the two fields to a valid `Maybe`
encoding (`Constr 1 []` is the honest "no treasury" choice) and re-discharge
— likely identical results; (ii) state the skeleton as part of each claim
(file docstring + README table caveat); (iii) optionally a ladder refinement
over ledger-shaped maps — CLAB itself ships a `[LEDGER-RULE]`
`validWithdrawals` predicate, so `validWithdrawals w → acceptance → forced
hash` is expressible in existing upstream vocabulary, mirroring the Aiken
tier's own layer-2 discipline; (iv) one ledger-shaped accepting witness.

**Label: GAP** (statement-accuracy; two-token fixture fix + doc line would
close most of it).

### C5 — The load-bearing contract invariant: all real safety is in PLG, which has no theorem.

**Observation.** Everything proven says: *PLB cannot release a programmable
UTxO unless the PLG stake script runs in the same tx.* Transfer rules,
conservation, freeze/seize, third-party logic, registry authentication,
unfracking invariants — all live in `programmable_logic_global` (2 996 B)
and its delegates (`unfracking` 1 736 B, `registry_mint` 1 928 B), which are
TESTED (46+ properties, mutation-exercised) but have no theorem tier. The
chain "PLB forwards → PLG enforces" has its second link at evidence class
TESTED.

**Why.** This is the invariant users of the standard actually care about;
the proven half is the cheap half. It deserves to be stated as the top
contract invariant: **"programmable value cannot move except under PLG's
transfer rules" — enforcing check at proof tier: NONE.**

**What would settle it.** Full PLG symbolic proof won't scale (§7.3, and the
status file's 93-minute no-verdict datum). Moves that still raise the tier:
(i) the `UnfrackingAct` arm is PLB-shaped — a single `has_key_or_fail`
against a params-datum field — plausibly the cheapest second theorem in the
codebase; (ii) theorems on `locate_registry_node`'s policy-ID-suffices
assumption; (iii) the aiken→Blaster bridge (PR #1311) promoting the existing
Blaster-shaped properties. Question: is the UnfrackingAct arm the intended
next `#prep_uplc` target?

**Label: GAP** (acknowledged by the layering; the ask is naming it with
`enforcing check: NONE at proof tier`).

### C6 — Redeemer independence: a comment, not a theorem.

**Observation.** "The base validator IGNORES its redeemer" is a source
claim; every theorem concretizes `rdmr = Constr 0 []` (as spend redeemer and
in `txInfoRedeemers`). The compiled V3 wrapper does extract the redeemer
from the context before ignoring it; that path is in the bytes and unproven.
The wsc-poc history in the file's own header is exactly about
redeemer-handling residuals surviving into compiled bytes.

**What would settle it.** A symbolic-redeemer rung (theorem 3 with `rdmr`
quantified), or at least a second accepting witness with a structurally
different redeemer. Cheap, and it converts the header comment into a
theorem.

**Label: GAP** (cheap rung, high rhetorical value).

### C7 — Rejection = ¬Halt: can "for the right reason" be separated?

**Observation.** `lib/pairs.ak`'s `has_key_or_fail` has no `False` path — a
missing key rejects via `list.head` on the exhausted list, i.e. a CEK error
— so "did not reach `Halt`" genuinely is the right rejection observable for
this validator. What `isHaltB … = false` cannot separate is *which* error:
scan-exhausted (the intended fail), context-decode failure, unsupported
builtin — **[R2] and now also fuel exhaustion: PCB's `runSteps` returns the
same `State.Error` constructor when the 600-step budget runs out.** The
methodology's own §3 demands this distinction.

**Why it's mostly carried anyway.** `exec_accepts` runs the *same skeleton*
to completion within the same fuel, differing only in one credential — so
the rejecting run's error can't plausibly be decode or fuel; it's the
scan's. That twin-context argument is what makes the control meaningful, and
it deserves to be written down.

**What would settle it.** A one-line comment stating the twin argument; a
mechanical upgrade would be re-running the rejecting context at, say, 10×
fuel and asserting the same `Error` (fuel-invariance of the rejection), or
asserting the `"Starting …"` trace fired if traces are compiled in and the
model exposes logs.

**Label: COVERED** (twin-context argument), with a small documentation ask
and a cheap mechanical hardening available.

### C8 — Width: 5+ is a proof-ladder question — but the wall he plans to probe may be the fuel wall.

**Observation.** The validator scans; no width-dependent branch exists in
the source, and nothing anywhere — PLB, PLG, unfracking, ledger — enforces a
withdrawal-count cap. The unfrack composition's "four withdraw-0s" is one
action's canonical shape, while a multi-policy `TransferAct` (PLG + one
transfer-logic withdraw-0 per policy + holder auth) plus ordinary vkey
reward withdrawals makes **>4-entry maps production-reachable today**. So
widths ∉ {1,2,4} are a proof-coverage gap over reachable shapes, not a
validator gap — the ladder measures Blaster's climb, as the file itself
says. **[R2] Sharper:** the status file plans to "find the actual
entry-count wall (8, 16 …)" — but `.prop` bakes in fuel 600, and a rung
whose *accepting* runs need more than 600 steps has an **unsatisfiable
hypothesis: Z3 will return Valid, fast, vacuously.** The wall found that way
could be the fuel wall wearing a Blaster costume, and nothing warns.

**What would settle it.** Climb with a per-rung within-fuel accepting
witness (C10) and raise the prep budget alongside the width; record the
genuine stop as COULD-NOT-EVALUATE. Longer term, a parametric-N statement if
the toolchain ever supports induction over the map; failing that, a
docstring stating which widths are proven while production reaches more.

**Label: GAP** (proof-coverage only; "4" is a convention, and the ladder's
honest extension needs the fuel discipline of C14).

### C9 — Mixed-credential withdrawal maps are outside every proven family. *(Already on his list — credited.)*

**Observation.** All three symbolic rungs build every entry as
`.ScriptCredential hᵢ`; no proven family contains a `VerificationKey` entry.
Yet a transaction that also withdraws the holder's *staking rewards* — a
perfectly ordinary combination — has exactly such a map. The source is safe
(`has_key_or_fail` compares whole `Credential`s; a Script param never equals
a VKey entry), and the compiled comparison is expected to be tag-sensitive
(`equalsData` on the `Constr 0/1` wrappers or an explicit tag dispatch), but
that expectation at bytes level is exactly what the ladder exists to
discharge. **[R2]** `FORMAL_VERIFICATION_STATUS.md` already lists "mixed
vkey/script credential entries" as a next rung — so treat this as
confirmation with one sharpening: the cheap control.

**What would settle it.** The planned mixed rung, plus a `native_decide`
polarity twin that needs no SMT: a map whose only entry is
`VerificationKeyCredential "PLG"` — *same payload bytes as the parameter,
wrong constructor tag* — must reject. That witness pins tag-sensitivity of
the compiled equality in one kernel-checked line.

**Label: GAP, already tracked** (the rejecting twin is the addition).

### C10 — Rungs 2 and 4 have neither a non-vacuity witness nor a mutant control — and witnesses now do double duty.

**Observation.** `exec_accepts` inhabits the 1-entry family;
`MutantControl.lean` falsifies only the 1-entry theorem and flips only the
1-entry rejecting context. The 2-/4-entry ∀-theorems have no accepting
witness and are never shown able to fail. **[R2]** With fuel semantics in
view (C14), a per-rung accepting witness is not just anti-vacuity hygiene —
it kernel-certifies that the rung's family is inhabited *within the 600-step
budget*, which is what protects the ladder from the vacuous-Valid failure
mode of C8. Put the param in the last slot to exercise full scan depth.
**[R2]** Also: the project's admirable independent-seed exercise ran against
the Aiken tier only; the Lean tier's falsification has one author-chosen
mutation. A seeded second mutation (e.g. compare-on-payload-only, or
first-entry-only scan) required to redden the theorems would extend "don't
let one person's imagination be the whole test" to the theorem tier.

**What would settle it.** Per rung: one `native_decide` accepting witness
(param in slot 2 / slot 4); add the 4-entry statement to the mutant
control's `#blaster (solve-result: 1)` list; one independently-seeded
Lean-tier mutation. All cheap; no new SMT difficulty.

**Label: GAP** (harness-coverage, directly in the spirit of the existing
controls).

### C11 — (minor) Non-spend invocations of the compiled PLB are unproven.

**Observation.** `else(_) { fail }` should make the artifact reject any
non-`SpendingScript` purpose (e.g. the PLB hash registered as a stake
credential and invoked as withdraw). Only the spend purpose appears in any
proven family. Low stakes, one `native_decide` rejecting run to close.

**Label: GAP** (minor, cheap).

### C12 — **[R2, new]** `warn.sorry false` silences the axiom disclosure, and nothing mechanically checks the axiom sets.

**Observation.** From Lean-blaster at the pinned rev: the `blaster` tactic
closes Valid goals by assigning the axiom `blasterProven : ∀ {α : Sort u}, α`,
and its disclosure warning — "declaration uses 'blasterProven' (SMT-verified,
no proof term)" — is emitted only `if (← getOptions).getBool `warn.sorry
true`. `PropsBase.lean` sets `set_option warn.sorry false` **file-wide**, so
(a) Blaster's own honesty label is silenced, and (b) a human `sorry` slipped
into the file would compile without a peep. The `#print axioms` commands at
the bottom print into the build log, but CI is `lake build` only — the
"axiom separation correct" check was a human reading a log once, not a gate.
A stray `sorry` (or a future toolchain change routing something else through
an admit) would keep CI green with zero signal.

**Why.** The SMT-vs-kernel separation is one of this PR's genuine
distinctions (§2); it's currently enforced by nothing. Note also
`blasterProven` as stated inhabits every type — including `False`; its
meaning is purely operational ("each use was backed by a Z3 unsat"). That's
the standard trade for this tool class, but §7.1 saying it in one sentence
would pre-empt the sophisticated reader's alarm.

**What would settle it.** Mechanical axiom pinning, e.g. Lean's `#guard_msgs`
idiom around each `#print axioms` (the expected-output comment makes the
build fail on any axiom-set drift — no script, kernel-adjacent, CI-enforced
by the existing `lake build`); then drop the file-wide `warn.sorry false`
(three expected warnings are informative, not noise) or scope it per
theorem. Question: was silencing chosen deliberately for clean logs, and
would `#guard_msgs` pins be acceptable instead?

**Label: GAP** (harness; cheap to close, and it guards the PR's own central
claim).

### C13 — **[R2, new]** The ladder is about `.prop`, the controls are about `.exec`, and the two are linked only by optimizer trust.

**Observation.** From PCB's `PreProcess.lean`: `#prep_uplc` creates **two
definitions** — `.exec` := the raw `cekExecuteProgram` application
(compiled, executable), and `.prop` := the output of `Blaster.Optimize.main`
on that expression (declared `noncomputable`). The SMT ladder quantifies
over `appliedBase.prop`; the kernel-checked pair runs `appliedBase.exec`.
**No theorem or axiom connects them** — their agreement is the correctness
of the Blaster optimizer, a trust link that is invisible to `#print axioms`
and unnamed in §7 (which lists Z3 + translation, but not the prep
optimizer as a separate preprocessing step whose output *is* the object of
the theorems).

**Why.** If the optimizer mis-transformed the term, the ladder could be
Valid about `.prop` while `.exec` (and the chain) behaved differently — and
the accept/reject pair would not notice, since it never touches `.prop`.
The mutant control partially couples them (leg 1 falsifies `.prop`-of-mutant,
leg 2 flips `.exec`-of-mutant — both respond to the same source mutation),
which is real but behavioral evidence at two points, not an equivalence.
`.prop` being noncomputable means `native_decide` cannot bridge directly.

**What would settle it.** (i) One sentence in §7 naming the optimizer in the
SMT trust base ("SMT-VALID trusts Z3, the Lean→SMT translation, *and the
prep-time optimization of the imported program*"); (ii) prop-side concrete
controls within the same trust base — `#blaster` command goals asserting the
accepting context succeeds and the foreign context fails *on `.prop`* with
expected result Valid (cheap, symmetric to the existing exec-side pair);
(iii) if upstream ever exposes it, an optimizer-correctness lemma would
collapse the link. Question: is prep-optimizer trust deliberately folded
into "the Blaster translation" in §7.1, and is that fold worth making
explicit?

**Label: GAP** (trust-base disclosure + two cheap prop-side controls).

### C14 — **[R2, new]** Fuel is part of every claim's statement — the identity triple is really a quadruple.

**Observation.** `#prep_uplc … 600` bakes 600 into both `.exec` and `.prop`
as the `Nat` fuel of `cekExecuteProgram`; PCB's `runSteps` returns
`State.Error` on exhaustion. So every theorem's "acceptance" formally means
"halts within 600 steps under variant E", and every rejection means "error
*or* out of fuel" (C7). The real chain bounds execution by ExUnits, not this
step count, and its budgets are orders of magnitude larger — so
model-acceptance ⊆ chain-acceptance-shaped behavior only while runs fit the
fuel. For the proven widths this is empirically fine (Phil's comparable base
measured K = 194; `exec_accepts` kernel-checks the 1-entry case within
fuel), but nothing *states* it, and the ladder's planned extension (8, 16
entries) is exactly where an accepting run silently outgrowing 600 would
turn a rung vacuous (C8). Separately, `isSuccessful` accepts *any* halt
value, while CIP-117 makes PlutusV3 success require returning unit — for the
implication direction proven this is sound (any-halt ⊇ unit-halt), and for
`exec_accepts` it leaves one thin residue: the model says "halts", the chain
additionally needs "with unit".

**Why.** The manifest's own rule is "a claim naming fewer than all three
identity coordinates is COULD-NOT-EVALUATE" — fuel is a fourth coordinate of
exactly the same kind: a parameter that silently changes what was proven.

**What would settle it.** (i) Add fuel (and the `isSuccessful =
any-halt` convention) to `MANIFEST.md`/§7 as part of claim identity;
(ii) per-rung within-fuel witnesses (C10) whenever the ladder grows, raising
the budget with the width; (iii) a one-line kernel upgrade of
`exec_accepts` asserting the halt *value*: `fromHaltState … = some (.VCon
.Unit)` — PCB has both `fromHaltState` and `Const.Unit`, so the CIP-117-tight
statement is directly expressible. Question: does the Aiken v1.1.22 V3
wrapper return unit on success (expected, CIP-117), and shall `exec_accepts`
say so?

**Label: GAP** (statement fine print; three cheap, concrete closers).

## 4. His rating, tested

He rates #1 (`exec_accepts`) most important and 3–5 "un po' meh". Two-pass
answer: **backwards on property content, half-right on evidence class — and
round 2 gives his instinct more credit than round 1 did.**

- #1–2 are *controls*, not guarantees: point executions certifying the
  machinery touches reality and can say both yes and no. The property the
  composition needs — "acceptance forces forwarding, for every deployment" —
  lives only in 3–5. On content, the ladder is the load-bearing half, and
  rung 2 holding where the Plutarch index-based base got stuck is evidence
  about the scan design, not a lesser theorem.
- But **[R2]** the kernel pair is also the only part of the file that
  touches `appliedBase.exec` — the executable object — and the only part
  that certifies within-fuel halting. The ladder speaks of `.prop` through
  two unnamed trust links (prep optimizer, fuel bound) plus Z3. So "the
  concrete pair matters most" has a defensible technical reading his
  "meh" may be groping toward: 3–5 currently carry *less certified content
  per word of prose* than they appear to (fixed skeleton — itself not
  ledger-encodable per C4 — script-only credentials, widths {1,2,4}, fuel
  600, optimizer trust).
- The resolution isn't to re-rank but to converge the classes: per-rung
  witnesses (C10), prop-side controls (C13), the two-token fixture fix (C4),
  and the mixed-credential rung he already plans (C9) each transfer real
  content into 3–5. After those, the ladder is unambiguously the crown and
  the pair its foundation.

## 5. COULD-NOT-EVALUATE (needs build)

- Whether Blaster discharges: a 5+/N-entry rung, a symbolic-redeemer rung
  (C6), the mixed-credential rung (C9), a skeleton-independence or
  ledger-shaped (`validWithdrawals`) rung (C4), or the prop-side `#blaster`
  concrete controls (C13) — all SMT runs.
- Whether the proposed `native_decide` closers evaluate as expected:
  slot-2/slot-4 accepting witnesses (C10), the vkey-tagged `"PLG"` rejection
  (C9), the 2-input witness (C1), the non-spend rejection (C11), the
  10×-fuel rejection rerun (C7), and the `Const.Unit` halt-value upgrade
  (C14).
- Whether the two-token treasury-field fix (C4) re-discharges all five
  theorems unchanged (expected, but that's the point of running it).
- Actual step-counts K for the rejecting and 4-entry runs (settles how much
  fuel headroom the current rungs have) — needs execution or a
  `runStepsWithBudget` probe.
- Whether `extract-flats.sh --check` is green at `02c7b86` and the five-leg
  falsification control passes today — scripts read, not executed; the
  control is not in CI (by design per the workflow comment), so its
  most-recent green is the 2026-08-06 manual run recorded in the status
  file.
- Whether Aiken v1.1.22's V3 wrapper returns `Const.Unit` on success
  (C14's CIP-117 residue) — one `native_decide` or a flat decode would
  settle it.
