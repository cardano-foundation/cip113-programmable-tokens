# Audit-coverage plan — extending the CIP-113 Blaster harness to the known vulnerability classes

**What this is.** A coverage map, not a verdict and not an implementation. For each
standard Cardano on-chain vulnerability class: does it apply to CIP-113, to which
validator, what property must hold, how you'd check it *against the compiled bytes*
with the harness PR #101 already builds, what a pass and a fail look like in
ESTABLISHED / REFUTED / COULD-NOT-EVALUATE, and what it costs. Adopt or dismiss each
item independently — several are one-line `native_decide` additions, a few are
"no theorem can settle this, here is the mechanism that can".

**Sources read** (read-only, commit `02c7b86397f7660c8f479b20cc544a099269a7d5`):
`PropsBase.lean`, `PrepBase.lean`, `MutantControl.lean`, `flats/MANIFEST.md`,
`scripts/extract-flats.sh`, `.github/workflows/formal-verification.yml`,
`FORMAL_VERIFICATION_STATUS.md`, `documentation/design/formal-verification-methodology.md`,
`protocol-param-sensitivity.md`, and the validator/lib sources:
`programmable_logic_base`, `programmable_logic_global`, `unfracking`, `registry_mint`,
`registry_spend`, `protocol_params_mint`, `issuance_mint`,
`programmable_logic/{transfer,third_party,unfracking,owner,params,ledger_shape}`,
`lib/{pairs,list,types,assets,tokens,registry_node,linked_list,utils}`, `env/*`, `aiken.toml`.

**Nothing here was executed.** No `lake build`, no `aiken build`, no clone-write. Every
cost figure is an estimate and every claim about what Z3 or the CEK machine *would* do is
marked COULD-NOT-EVALUATE. Where a check can only be settled by a build, that is the work
being scoped, not work done.

**Companion document.** `invariants-findings.md` (Half 1) covers proof-scope and harness gaps
in the five existing theorems and is referenced here as C1–C14 rather than repeated. The two
documents partition cleanly: C1–C14 ask *"what does the existing ladder not cover about PLB,
and what does the harness not enforce about its own claims"*; this one asks *"which attack
classes does the protocol expose, and what would cover them"*. Where they meet (C1↔V1,
C9↔V5b, C4↔V18, C5↔the whole PLG column, C12–C14↔V20/R5/R6) the overlap is flagged inline;
§12 carries the full mapping.

---

## 1. What the PR already establishes — the floor this plan builds on

Stated first because it is the reason the rest of this document is cheap to execute.

- **The compiled artifact is what's under test.** `#import_uplc` on the blueprint's own
  `compiledCode`, no hand-written Lean model. The methodology doc says so explicitly and
  gives the reason (the neighbouring Plutarch campaign's hand models were refuted against
  actual bytecode). That decision is what makes every check below meaningful.
- **The identity triple is mechanical, not prose.** `extract-flats.sh` reads the compiler
  from `.preamble.compiler`, the variant is evidenced down to the `Inhabited` instance
  line, and `--check` is a byte diff. It has already caught a real v1.1.21/v1.1.22 drift.
  CI re-establishes commit → blueprint → flats → theorems on every push.
- **The accept/reject `native_decide` pair.** Non-vacuity and polarity demonstrated on the
  real CEK against the real bytes. Most formal write-ups skip this.
- **The mutant control goes through the real pipeline**, and has two legs at two evidence
  tiers: the SMT theorem must come back Falsified *and* the kernel-checked rejection must
  flip to acceptance. The second leg is what proves the mutation reached executable
  semantics rather than just the bytes.
- **SMT-VALID is separated from KERNEL-PROVED** where a reader sees it — vocabulary section
  of the methodology doc, `#print axioms` in the source, `blasterProven` named.
- **Independent negative controls already exist as tooling** (`cip113-mutation-seeds`,
  3/3 caught, and the exercise found a real six-test vacuity defect). Almost every control
  proposed in §8 is a new *seed* for that existing tool, not new machinery.

The forwarding ladder establishes **one link**: a PLB UTxO cannot be released unless PLG's
withdraw-0 runs in the same transaction. Every other protocol guarantee — transfer rules,
conservation, seizure limits, registry integrity — lives on the far side of that link and
is currently TESTED. That is the shape of this plan: most of it is about the second link.

---

## 2. Three pre-flight experiments that partition everything below

Do these first. Each is a single build, each has a declared stop, and their outcomes decide
whether half this plan is T2-cheap or COULD-NOT-EVALUATE-and-stop.

### EXP-0 — does `#prep_uplc` terminate on PLG and `unfracking`?

`appliedBase` preps at budget 600 on a 141-byte scan validator (K≈194 measured on the
comparable wsc base). PLG is 2 996 B and `unfracking` is 1 736 B — 21× and 12×. Both
branch on a typed redeemer, walk reference inputs, and allocate closures before dispatch.
Whether `#prep_uplc` produces a usable `.exec`/`.prop` at *any* budget on these is the
single gating unknown for classes V1(PLG half), V2, V4, V6 and V7.

- Method: `#prep_uplc appliedPlg programmableLogicGlobal plgInputs <budget>` at an
  escalating budget, timeboxed.
- ESTABLISHED: preps, and one concrete `native_decide` `UnfrackingAct` run reaches Halt.
- COULD-NOT-EVALUATE: no verdict inside the box, or prep succeeds but every `.exec`
  diverges. **This is a legitimate, publishable result** — it measures the toolchain's
  reach on a realistic validator and it is exactly the number Phil's Q4 exchange was
  after. It is not a failure of the plan; it reclassifies rows V2/V4/V6/V7 from
  "T2 theorem" to "TESTED-only, with the boundary recorded".
- Cost: 1 build unit, timeboxed. Do it before costing anything else at the PLG tier.

### EXP-0b — which builtins does the pinned CEK model dispatch?

`registry_mint`'s Insert path computes `blake2b_224(append(append(#"03", prefix),
append(hashed_param, postfix)))` — the cryptographic binding that makes the whole registry
unforgeable. If PlutusCoreBlaster's evaluator does not dispatch `blake2b_224`, **every**
result about `registry_mint` Insert is bounded at that dispatch failure and must say so.
`less_than_bytearray` / `equals_bytearray` matter the same way for the linked-list ordering.

- Method: one `RegistryInit` concrete run (no hashing on that path) and one `RegistryInsert`
  run in the same skeleton. Init reaching Halt while Insert stops on a *refused dispatch*
  is the diagnostic.
- Pass/fail: the harness must report **which** of the two stop reasons occurred — refused
  builtin dispatch (tooling limit, a builtin-support finding and nothing else) versus
  validator-logic error (a fact about the program). If the harness cannot tell them apart,
  the result is COULD-NOT-EVALUATE, per §3 of the methodology doc.
- Cost: 1 build unit, shares a build with EXP-0.

### EXP-0c — the extraction inventory is a declared subset (no build)

`extract-flats.sh`'s `TITLES` array is an explicit, versioned inventory of four titles.
That is the right pattern — enumerate from an inventory, not from a directory glob. But the
blueprint carries more validators than the inventory classifies, and nothing goes RED about
the difference. Missing from every tier above TESTED:

| Validator | Why it is load-bearing |
|---|---|
| `registry_spend` | Sole spender of every registry node; carries the update-path authorisation (`minting_logic_script` withdrawal) that mutation seed 2 targeted, and the "no mint of the spent node's own key" guard |
| `protocol_params_mint` | The trust root. Uniqueness of the params NFT is what makes `get_protocol_params_ref` deterministic (V11/V13) |
| `issuance_mint` | Owns mint-side custody of programmable tokens, and holds one end of the three-hop delegation argument with PLG that neither validator can state alone (V3) |

- Proposed: extend `--check` so that a blueprint title present in `plutus.json` and absent
  from `TITLES` fails RED unless it appears in a second, equally explicit
  `DELIBERATELY_UNVERIFIED` array with a one-line reason. Silent omission and declared
  omission read identically today; they should not.
- Falsification: add a fifth title to the blueprint (or remove one from `TITLES`) and
  require `--check` to redden. Mirror of the corrupted-flat/tampered-manifest legs that
  already exist.
- Cost: no build. Shell only. **Highest coverage-per-effort item in this document.**

---

## 3. Six standing rules every proposed check inherits (R2 carries a sharper second form, R2b)

Stated once so §5 does not repeat them.

**R1 — the twin-context rule, and its limit.** `isHaltB … = false` cannot, on its own,
distinguish a validator-logic rejection from a context-decode failure, a wrapper `expect`
failure, or a refused builtin dispatch. On PLB this is already handled by structure:
`exec_accepts` runs the *same skeleton* to completion and the only delta is the map entry
(C7). On PLG, `unfracking` and `registry_mint` — which touch far more of the builtin surface
— that argument does not carry. **Every proposed rejecting run below must ship with an
accepting twin in the same skeleton differing in exactly one field**, or its outcome is
COULD-NOT-EVALUATE rather than a fail you can act on.

**But a twin is not enough to say *why*.** The accepting twin proves the shared skeleton
decodes; it does not prove the rejecting run failed at the guard being credited rather than
at an earlier `expect`, the wrapper's own decode of the changed field, or purpose dispatch.
So for any run whose *reason* is load-bearing, add a **localisation leg**: mutate only the
intended guard, prove the extracted flat's sha256 changed, and require that specific run to
flip. Without it, report the honest weaker claim — "this context is rejected" — and not
"rejected by check X". This is the same discipline as the existing mutant control's leg 2,
applied per claim rather than once for the file.

**R2 — no ∀-family without an inhabitant.** A ∀-theorem is vacuously true if no witness
satisfies its hypothesis. Rungs 2 and 4 currently have no accepting witness (C10). Every
new symbolic family below ships with one `native_decide` accepting witness *inside that
family*, and the witness should put the satisfying entry in the **last** slot, which also
exercises the scan's recursion depth.

**R2b — an independence claim cannot be stated as an implication.** This is the sharp form of
R2 and it invalidated four of this plan's own controls before it was written down. The ladder's
shape is `accepts(ctx) → forwarding`. Bolt an extra quantifier on the front — *"∀ redeemer,
∀ validity range, ∀ input list, ∀ lovelace: accepts → forwarding"* — and you have **not**
stated that the validator ignores that field. Narrowing acceptance can never falsify an
implication: a mutant that accepts only the unit redeemer simply makes every non-unit case
vacuous, and the theorem stays Valid. The seeded bug survives its own control.

Independence must therefore be stated one of two ways:

- **relationally** — `accepts(ctx, x₁) ↔ accepts(ctx, x₂)` for arbitrary `x₁, x₂` in the field
  claimed irrelevant; or
- **by inhabitants** — one `native_decide` accepting witness per *discriminating* value of that
  field, so a mutant that narrows acceptance kills a witness rather than emptying a hypothesis.

Applies to every invariance row here: V1(b) input count, V6 redeemer, V9 lovelace, V10
validity range. Their controls (S-21…S-24) only bite against a statement of one of those two
shapes — against the implication form they pass on the seeded bug.

**R3 — ledger reachability cuts both ways, and the direction matters.**
The Lean context types are a strict *over*-approximation of what the ledger can produce:
`Withdrawals` is `Pairs Credential Int`, so a Lean fixture can carry `ScriptCredential ""`,
an empty withdrawal map under a rewarding purpose, negative output quantities, or duplicate
map keys — none of which a node will ever hand a script. Consequences, both load-bearing:

- For an **ESTABLISHED** ∀-safety theorem, over-approximation is *sound and free*: proving
  it over a larger family is strictly stronger. Do not narrow the families to gain realism.
- For a **REFUTED** result, over-approximation is *not* sound as a bug report: a Z3
  counterexample must be checked for ledger reachability before it is called a finding.
  This matters concretely here — the default-deny arguments for `empty_vkey` hooks
  (unfracking, third-party, transfer, origin node) rest on *"no ledger transaction can carry
  a withdrawal keyed by an empty hash"*, which is a ledger fact the on-chain code never
  checks and the Lean model does not encode. A counterexample exploiting an empty-hash
  withdrawal is spurious; a counterexample not exploiting one is real.
- Separately and in the other direction: the *concrete* fixtures are currently ledger-
  **unreachable** (3-byte hashes, empty tx id, fee 100, no min-ada floor, `mkCtx`'s single
  input). Fine for controls, but it means non-vacuity is demonstrated on a context the
  ledger could never produce, while the Aiken tier's `ledger_shape` discipline is not
  mirrored on the Lean side (C4b). One ledger-shaped accepting witness closes the
  rhetorical gap cheaply.

Recommendation: state R3 once in the methodology doc §7 next to limitation 3. It is the
sentence that stops a future reader from either over-claiming a REFUTED or "fixing" the
families into something weaker.

**R4 — every positive check ships with a seeded violation it must catch.** §8 gives the
seeds and closes with an explicit **check → control mapping**, one row per proposed check,
naming either its seed *or* `NONE — caveat named`. The first draft asserted the mapping was
complete
when it was not — six rows had no seed — which is the same "the check looked complete because
its author wrote both the check and its only test cases" failure this rule exists to prevent.
The mapping is now explicit and its gaps are named rather than implied.

**And an independence theorem's control is to introduce a dependence.** Four of those six
`NONE`s were justified as "nothing reads this field, so no mutation of it can change
behaviour". That reasoning is backwards: *"nothing reads the field"* is the claim under test,
so the negative control is to **make something read it**. Concretely — add an exactly-one-input
guard and the two-input witness must red; make the ignored redeemer require unit and the
symbolic-redeemer rung must red; add an equality on the allegedly free lovelace field and the
invariance theorem must red; add a bogus validity-range gate and the range-independence
theorem must red. Every invariance/independence claim in this plan has a control of exactly
that shape, and only V8's width ladder keeps a `NONE` **by form** — a rung's failure to
discharge is a measurement of the tool, not a check that could be seeded.

**R5 — `.prop` and `.exec` are two different objects.** `#prep_uplc` emits both: `.exec` is
the raw `cekExecuteProgram` application (computable, what `native_decide` runs), `.prop` is
the output of Blaster's prep-time optimizer on that expression (`noncomputable`, what every
`by blaster` theorem quantifies over). **No theorem or axiom connects them**, and the link is
invisible to `#print axioms`. Consequence for every row in this plan that pairs an S-check
with a K-control: the two legs are evidence about two objects, joined by optimizer
correctness. Two cheap responses, both worth taking: name the prep optimizer explicitly in
the trust base alongside Z3 and the Lean→SMT translation, and add **prop-side concrete
controls** — `#blaster` goals asserting that the accepting context succeeds and the foreign
one fails *on `.prop`*, symmetric to the existing exec-side pair. (Companion C13.)

**R6 — identity is five coordinates, not three.** The manifest's own rule is that a claim
naming fewer than all identity coordinates is COULD-NOT-EVALUATE. Two more coordinates are
currently implicit and belong in the manifest by that same rule:

- **Aiken build environment.** `env/default.ak` makes `assert_no_ada_policy` the identity
  function; `env/with_assertions.ak` makes it a real check. CI runs a plain `aiken build`, and
  the byte-for-byte blueprint reproduction leg pins the env implicitly — so it *is* covered,
  but a reader cannot see that it is.
- **Prep fuel.** `#prep_uplc … 600` bakes 600 into both `.exec` and `.prop` as the CEK step
  bound, and PCB returns `State.Error` on exhaustion. So "acceptance" formally means *halts
  within 600 steps under variant E*, and "rejection" means *errored **or** ran out of fuel*.
  That is fine at the proven widths and becomes a vacuity trap exactly where this plan
  proposes to go — an 8- or 16-entry accepting run that silently outgrows the budget turns
  its rung vacuous while everything stays green. **Raise the budget with the width and record
  the fuel next to the claim.** (Companion C14.)

---

## 4. Coverage matrix

Applies: **Y** = live class for this protocol · **P** = partial / delegated to an
interface obligation · **N** = does not apply, reason in §5.
Method: **K** = concrete kernel-checked run (`native_decide`) · **S** = symbolic ∀-theorem
(`by blaster`) · **C** = negative control only · **X** = not settleable on-chain, needs the
named off-chain mechanism.
Cost: **T0** reuses the harness as-is · **T1** extends `mkCtx` with new fixture fields ·
**T2** needs a new context builder (rewarding purpose) + `#prep_uplc` on a big validator ·
**T3** new SMT rung, convergence unknown · **T4** off-chain / mechanical, no build.

| ID | Class | Validator(s) | Applies | Property that must hold | Method | Pass / fail | Cost |
|---|---|---|---|---|---|---|---|
| V1 | Double satisfaction | PLB, PLG | **Y** | (a) PLB acceptance forces PLG's entry — *proven*, widths {1,2,4}. (b) PLB acceptance is independent of input count and own-ref. (c) PLG's active branch accounts for **every** PLB input in the tx | S+K (b: T1) · S (c: T2) | ESTABLISHED = ∀-theorem discharges + witness inhabits family; REFUTED with a ledger-reachable cex = finding | T1 / T2 |
| V2 | Value preservation / leakage | PLG (transfer, 3rd-party), unfracking | **Y** | Per registered policy: PLB-output total ≥ PLB-input total + mint (transfer, 3rd-party); strict equality at owner outputs (unfracking) | S (T2/T3), TESTED today | ESTABLISHED on the branch family; COULD-NOT-EVALUATE if EXP-0 fails | T2/T3 |
| V3 | Unauthorized mint / name control | registry_mint (+ issuance_mint, **no flat**) | **Y** | Registry NFT: exactly one, quantity 1, name == `key`, `key` == blake2b of the parameterised issuance template. Programmable token mint custody: `no_escape` locally, plus a **three-hop cross-validator delegation argument** with PLG | K+S for registry_mint (gated on EXP-0b) · **cross-artifact K** for the issuance_mint × PLG composition | ESTABLISHED per leg. The composition leg is **COULD-NOT-EVALUATE today** — blocked on a missing flat and the rewarding-context builder, *not* out of scope for on-chain proof | T2 |
| V4 | Authorization / freeze / seize | PLG (`owner.ak`), unfracking, registry_spend | **Y** | Every PLB input spent on holder authority carries an inline stake credential that signed or withdrew. Seizure is gated on the node's `third_party_transfer_logic_script` | K (per-branch), S if EXP-0 allows | ESTABLISHED per concrete authorised/unauthorised twin | T2 |
| V5 | Purpose confusion | all four + registry_spend | **Y** | PLB rejects every non-spend purpose; PLG/unfracking `publish` accepts only `RegisterCredential`; registry_mint rejects non-mint | K, twin-paired | ESTABLISHED = rejecting run + accepting twin. A surviving accept is a finding | **T0** (PLB) / T2 |
| V5b | Credential-tag confusion | PLB, PLG | **Y** | A `VerificationKey` entry whose payload equals the param must not satisfy a `Script` gate (C9) | K (rejecting twin) + S (mixed family) | ESTABLISHED; the K leg needs no SMT | **T0/T1** |
| V6 | Datum / redeemer validation | PLG, unfracking, registry_spend | **P** | Malformed redeemer rejects. Datum continuity enforced per pair in 3rd-party + unfracking; **not enforced in TransferAct** — interface obligation | K (malformed-redeemer runs) · X (TransferAct datum obligation) | ESTABLISHED per run; the TransferAct asymmetry is a documentation finding, not a bug | T2 / T4 |
| V6b | Data-layout contract | registry_node fields, params fields | **Y** | Field indices 0/1/2/3/4/5 read by `with_key_and_*` and `*_field` are the ones `registry_mint`/`protocol_params_mint` write | K (discriminating-datum run) | ESTABLISHED = the run reads the field the golden test pins | T2 |
| V7 | Replay / uniqueness / thread token | registry_mint, registry_spend (**no flat**) | **Y** | Origin is one-shot; `covering.key < new.key < covering.next` strictly; NFT name == key; nodes are never burnable; sole spender is registry_spend | S (ordering), K (init/insert), X (spender binding) | ESTABLISHED per leg; registry_spend leg blocked on EXP-0c | T2/T3 + T4 |
| V8 | Unbounded / DoS | PLG, unfracking | **P** | No unbounded loop is attacker-controlled *for free*; width has no enforced bound (C8); `maxValueSize` on fracked UTxOs | X (bench-vs-ceiling CI pin) + S (width ladder) | ESTABLISHED = ladder rung discharges; a rung that stops is COULD-NOT-EVALUATE and *measures the tool*, not the code | T3 / T4 |
| V9 | Min-UTxO / ada / dust | PLG 3rd-party, unfracking | **P** | Validators must be *insensitive* to lovelace where they claim to be (the #96 hazard class); ada floors are the ledger's, not the script's | S (∀-lovelace theorem) | ESTABLISHED = acceptance invariant under the lovelace field | T2/T3 |
| V10 | Validity range / time | all | **N** | No validator reads `validity_range`. Cheaply *provable* N/A: acceptance invariant under `txInfoValidRange` | S (invariance rung) | ESTABLISHED turns a source claim into a theorem | **T0** (PLB) |
| V11 | Reference input / script trust | PLG, unfracking, **protocol_params_mint (no flat)** | **Y** | Authentication is by **policy id via `peek_first` only**. Uniqueness + immutability are closed by `protocol_params_mint`, but its **construction shape is not**: a lower-sorting co-asset in the params output hides it from `peek_first` permanently. Node authentication rests on an induction spanning registry_mint × registry_spend | K (decoy runs) + **X (construction gate)** | **Polarity matters**: PLG rejecting the co-asset params UTxO *demonstrates the brick*, it does not establish safety. Safety = the deployment gate rejects that construction. Gate accepts + PLG rejects ⇒ **REFUTED** | T2 + T4 |
| V12 | Datum-hash vs inline | PLG, unfracking, registry_* | **P** | `expect InlineDatum` on params + nodes; 3rd-party/unfracking compare the whole `Datum` (so hash↔inline swaps are caught); TransferAct does not compare | K (hash-datum rejecting run) | ESTABLISHED = hash-datum ref input rejects, with accepting twin | T2 |
| V13 | **Deployment / trust-root closure** | all (cross-cutting) | **Y** | `params.prog_logic_cred` == hash of `programmable_logic_base(PLG_cred)`; `params.registry_node_cs` == the registry_mint instance whose `registry_spend_cred` is the deployed spender; PLB's `stake_cred` is a **Script**. The datum is shape-checked at mint and **never closure-checked**, and it is **write-once** | **X** — no on-chain check exists or can exist | Mechanical deployment-manifest checker; RED on any unclosed edge | **T4** |
| V14 | **Substandard-hook aliasing** | PLG transfer / 3rd-party, unfracking | **Y** | One withdrawal entry satisfies *every* registry node naming that credential. A hook must validate **all** policies whose node names it, not just the first | **X** — interface obligation on substandards | Normative sentence in the substandard guide + a conformance test | **T4** |
| V15 | Fracking / freeze collateral damage | protocol-level | **Y** | The unfracking rescue path is default-**forbidden** (`empty_vkey`), so the mitigation for a hostile freeze is opt-in *by the hostile issuer* | **X** — governance/disclosure | Disclosure item, not a code check | **T4** |
| V16 | Verified-inventory completeness | tooling | **Y** | A blueprint title with no flat must be *declared* unverified, not silently absent | X (extend `--check`) | RED on an unclassified title; falsified by adding one | **T4**, see EXP-0c |
| V17 | Integer / quantity domain | all | **N** | Plutus `Integer` is unbounded; no fixed-width arithmetic anywhere. Only residual is R3: Lean families admit ledger-impossible negative output quantities | — | N/A by form | — |
| V18 | Proof-family reachability | methodology | **Y** | An ESTABLISHED result over an over-approximating family is stronger; a REFUTED one needs a reachability check before it is a bug | **X** — one paragraph in §7 | Documentation | **T4** |
| V19 | **Attacker-controlled positional indices** | PLG 3rd-party, unfracking, TransferAct proofs | **Y** | `registry_node_idx`, `outputs_start_idx` and proof *order* are security-bearing redeemer pointers. No output may be counted twice (prefix accumulation **and** paired continuation), none skipped | K (boundary fixtures at 0, 1, len, len+1), S for the ∀ | **KERNEL-PROVED at those boundaries**, not ESTABLISHED — four executions are not a partition theorem. A double-counted or skipped output is a value-accounting finding | T2 |
| V20 | **Claim-integrity gates** | harness | **Y** | The evidence-class labelling must itself have an enforcing check: axiom sets pinned, `.prop`/`.exec` trust named, fuel recorded as a claim coordinate | X (`#guard_msgs` pin) + C (prop-side controls) | RED on axiom-set drift; falsified by adding a `sorry` | **T4** + T0 |

---

## 5. Per class: applicability, property, method, criterion, cost

### V1 — Double satisfaction

**(a) Applies, and it is the class this protocol is built around.** But not in its classic
shape, and saying where it *doesn't* live is half the finding.

- **Not in PLB.** One PLG withdrawal entry satisfying N PLB spends is the withdraw-0
  forwarding pattern working as intended: PLG runs once and is meant to validate the whole
  transaction. There is no per-input payment to double-count.
- **Not in TransferAct's accounting.** `validate_transfer` aggregates *all* PLB inputs into
  `input_assets` and *all* PLB outputs into `output_assets`, then checks containment per
  policy. Aggregate accounting is structurally immune to double-counting; a per-input
  pairing scheme would not be.
- **Not across PLG branches.** `txInfoWdrl` is a map keyed by reward account, so PLG runs
  **at most once per transaction** and exactly one redeemer branch is live. A transaction
  cannot be simultaneously a TransferAct and a ThirdPartyAct.
- **It lives in the seam**: PLB accepts on PLG's *presence*, under any redeemer. So the
  obligation is "whichever branch is live accounts for every PLB input in the transaction".
  Reading the source, all three branches do: TransferAct scans all inputs for
  `payment_credential == prog_logic_cred`; ThirdPartyAct pairs every PLB input positionally
  and rejects an input not holding the acted policy; UnfrackingAct delegates to `unfracking`,
  which walks all inputs and pins them to one owner address. That is a *source* reading and
  is exactly the kind of claim this project refuses to take from source reading.

**(b) Property.**
1. `PLB_accepts(param, ctx) ⟹ param ∈ keys(ctx.withdrawals)` — proven, widths {1,2,4}.
2. `PLB_accepts` is invariant under `txInfoInputs` and the spent `outRef` (C1).
3. For each PLG branch B: `PLG_accepts(B, ctx) ⟹ every input of ctx with payment
   credential `prog_logic_cred` is constrained by B`.

**(c) Method.**
- (2) is the cheap half and needs no SMT to start: extend `mkCtx` from a fixed
  `txInfoInputs := [⟨outRef, resolved⟩]` to a parameter, then one `native_decide` accepting
  run with **two** PLB inputs and one with a PLB input plus a non-PLB input. Per R2b those
  witnesses are the *statement*, not decoration — an implication-shaped "∀ input list,
  accepts → forwarding" rung would survive S-21 vacuously. The full answer is a relational
  rung (`accepts(ctx, ins₁) ↔ accepts(ctx, ins₂)`), which is a T3 gamble.
- (3) is T2 and gated on EXP-0. The cheapest useful instance is the **UnfrackingAct arm**:
  it is PLB-shaped — a single `has_key_or_fail` against a params-datum field — so
  `PLG_accepts(UnfrackingAct, ctx) ⟹ unfracking_cred ∈ keys(ctx.withdrawals)` is the same
  theorem as the existing ladder with one extra indirection through the reference-input
  params lookup. If any PLG theorem is going to discharge, it is that one. (This matches
  C5's read: it is the cheapest second theorem in the codebase.)

  **But label it correctly: that theorem is rung 2 of three, not "the second link closed".**
  The unfracking chain is three distinct claims and only the middle one is cheap:

  | Rung | Claim | Where it lives | Status |
  |---|---|---|---|
  | 1 | PLB accepts ⟹ PLG's withdrawal present | PLB | **proven**, widths {1,2,4} |
  | 2 | PLG accepts under `UnfrackingAct` ⟹ unfracking's withdrawal present | PLG | the cheap T2 rung above |
  | 3 | unfracking accepts ⟹ every PLB input is paired, single-owner, and conserved | `unfracking` | the actual accounting obligation — T2/T3, and the expensive one |

  Rungs 1 and 2 are *forwarding* — they say the next script runs. Only rung 3 says anything
  is checked. A plan that stops after rung 2 has bought a longer chain of "something else
  will validate this", which is not the same as validation. Prioritise rung 2 because it is
  cheap and it de-risks the context builder; do not let it close the row.

**(d) Criterion.** ESTABLISHED = the ∀-theorem discharges **and** an accepting witness
inhabits the family (R2). REFUTED with a ledger-reachable counterexample (R3) is a finding.
Timeout is COULD-NOT-EVALUATE and red.

**(e) Cost.** (2) T1, batched into one build with V5/V5b/V10. (3) T2, gated on EXP-0.

**Independent seed (§8, S-1):** replace `has_key_or_fail(stake_cred)` with
`has_key_or_fail(list.head(withdrawals).1st)` — accept whatever credential is first. This
mutant still *rejects* many contexts, so the existing polarity control would not obviously
catch it; the ∀-theorem must. That is a sharper test of the ladder's discriminating power
than the current `→ True` mutant, which makes the validator accept everything.

### V2 — Value preservation / leakage

**(a) Applies to all three PLG branches.** Scope statements first, because each branch
guarantees strictly less than "tokens are safe" and the difference is where an auditor
looks:

- **TransferAct guarantees containment, not ownership.** `output_assets` aggregates PLB
  outputs regardless of *whose* they are. Alice's and Bob's tokens of policy P in one
  transaction are checked against a single sum, so tokens may move between owners — every
  input is individually authorised, so no unconsented movement occurs, but ownership rules
  are entirely the policy's `transfer_logic_script`'s job. That delegation should be stated
  in the guide as a normative obligation, not left implicit.
- **ThirdPartyAct guarantees containment-within-PLB, not destination.** Seized tokens must
  reappear in *some* PLB output; which one is the admin's choice. That is the intended
  seizure semantic, and it is worth writing down as such.
- **Unfracking guarantees strict equality at owner-address outputs** — no leak and no
  fabrication, and destinations pinned to the owner. It is the tightest of the three.
- **Ada is unconstrained** in TransferAct and unfracking; ThirdPartyAct ratchets it
  per pair (`output_lovelace >= input_lovelace`, deliberately not equality — issue #96).
- **Unregistered co-resident policies are unconstrained** by design.

**(b) Property.** Per branch, as the module docstrings state them. They are already written
precisely enough to be theorem statements verbatim — which is the property suite's stated
purpose (Layer 1 doubles as the theorem backlog).

**(c) Method.** T2/T3, gated on EXP-0. If EXP-0 fails, the honest outcome is: these stay
TESTED, and the methodology doc records the measured boundary ("`#prep_uplc` does not reach
a 2 996-byte validator at budget N"). That is a publishable result about the toolchain.

If EXP-0 succeeds, the highest-value first target is **not** full conservation but the
`!dict.is_empty(input_tokens_at)` guard in `third_party.ak` (Finding 12). Reading the code,
that one line carries more weight than its comment claims: it is also what stops a
ThirdPartyAct aimed at the **origin node** (`key = #""`, the ada policy) from treating
lovelace as the acted policy. A guard doing two jobs, only one of them documented, is
exactly what a targeted control should pin.

**(d) Criterion.** Per branch: ESTABLISHED / REFUTED (with R3 reachability check) /
COULD-NOT-EVALUATE.

**(e) Cost.** T2 minimum, T3 for the conservation quantifiers. Assume the input-count
quantifier does not discharge and plan concrete rungs at 1, 2, 3 inputs instead.

### V3 — Unauthorized mint / other-token minting / name control

**(a) Applies. Split it in two, because the halves are in very different states.**

**Registry NFTs (`registry_mint`) — tight, and provable if EXP-0b allows.**
`validate_mint` requires exactly one asset name at quantity exactly 1; the name must equal
`node.key`; `validate_directory_node_output` requires the output carry exactly two policies
(ada + node_cs) and no reference script; and `is_programmable_token_id_valid` binds `key`
to `blake2b_224(#"03" ++ prefix ++ minting_logic_hash ++ postfix)`. Two consequences worth
naming explicitly because they are load-bearing and not stated anywhere I found:
- **Registry nodes can never be burned.** A burn is still the mint purpose with a negative
  quantity, and `[Pair(name, 1)]` rejects it. The registry is append-only by construction.
- **Two policies cannot share a `minting_logic_script`**, because the policy id is a
  deterministic function of it. This does *not* hold for the transfer / third-party /
  unfracking hooks — see V14, which is where the aliasing risk actually lives.

**Programmable token mint (`issuance_mint`) — a cross-validator composition, not a hole.**

First, a correction to a signpost rather than to code. `transfer.ak:73–85` describes
`issuance_mint`'s delegation as `or { plg_invoked, validate_mint_outputs }` and calls it
"too broad — same root cause as finding 04 … Tightening issuance_mint's delegation closes
both. Tracked separately." **At this commit that comment is stale**: `issuance_mint` already
carries the tightened form, `or { plgl_delegates_for_own_registry_node(…), custody_ok() }`,
whose own comment says it closes Finding 04 / re-audit R-04. Worth fixing, because a comment
that reads as an open custody finding is the first thing an external auditor will chase, and
it points at a validator whose current code does not have that shape.

Second, what is actually there. Locally, `no_escape` forbids `own_policy` at any non-PLB
output and requires every PLB output to carry an inline stake credential — combined with
ledger value conservation that pins every minted unit at the PLB. That much is one
validator's own business and is checkable in one place.

But on the `RefInput` path, custody may be **delegated to PLG**, and the soundness of that
delegation is a **three-hop argument spanning two validators**:

1. `verify_registry_node` binds `RefInput { index }` to `own_policy` (NFT asset name and
   `datum.key` both equal `own_policy`), so "same index" ⇒ "same policy";
2. PLG's `verify_proofs` consumes `proofs` **positionally, in lockstep** with `input_assets`,
   so a `TokenExists { node_idx }` proof only survives if it lines up with an input policy —
   and `choose_registered_token_with`'s `expect key == policy` kills a mislaid one;
3. `validate_transfer` requires `[] == verify_proofs(…)`, so the proof list must be *exactly*
   exhausted — a spare proof cannot be smuggled in for a policy that has no PLB input.

Together those close the escape: since `apply_mint_to_known_policies` drops mint deltas for
policies with no PLB input, delegation is only reachable in exactly the case where PLG does
account for the mint. Reading it through, the argument holds. **The point is not that it is
wrong — it is that it is a property of `issuance_mint` × `programmable_logic_global` that
neither validator's own theorem, nor either one's property tests, can state.** It currently
lives in two comment blocks. `UnfrackingAct → False` in `plgl_scope_covers` is the same
argument's explicit negative case, which is a good sign about how it was reasoned.

One consequence for fixtures: `issuance_mint` reads `tx.redeemers` to find PLG's
`Withdraw(cred)` entry. That promotes the redeemer-map shape — which `ledger_shape.ak`
currently documents as "not representable … documented for completeness" — into a
load-bearing input for at least one validator. `mkCtx`'s `txInfoRedeemers` is a single
`Spending` entry today; any issuance_mint fixture must get that map's contents and Conway
ordering right, or it will test a transaction the ledger would not produce.

**(b) Property.** (i) Registry: at most one node NFT per transaction, name == key, key
cryptographically bound. (ii) Issuance, local: no `own_policy` token sits at a non-PLB output.
(iii) Issuance, compositional: delegation to PLG is reachable only when PLG's active branch
actually accounts for `own_policy`'s mint delta.

**(c) Method.** (i) K + S on `registry_mint`, gated on EXP-0b — if `blake2b_224` is not
dispatched, the binding check is unreachable and every Insert result is bounded there, which
must be reported as a builtin-support finding and not as coverage. (ii) K once `issuance_mint`
is in the inventory. (iii) **Cross-artifact K, then S** — and note this is *not* class X. An
earlier draft filed it as "out of scope for on-chain proof" one paragraph after describing how
it could be built, which was inconsistent. Both artifacts are `#import_uplc`-able and a single
ledger-shaped `ScriptContext` can drive both `.exec`s, so the claim is **statable and
COULD-NOT-EVALUATE-today** — blocked on a missing flat (EXP-0c) and the rewarding-context
builder, not on form. A shaped relational theorem over `.prop` follows if it scales. It would
be the first genuinely cross-validator claim in the project, which is worth something on its
own: the three-hop argument is exactly the kind no per-validator tier can hold.

**(d) Criterion.** (i) ESTABLISHED per leg; a bounded-at-dispatch result is
COULD-NOT-EVALUATE, never a partial pass. (ii) ESTABLISHED per twin pair. (iii) ESTABLISHED
requires **both** validators to halt on the same ledger-shaped context, and each negative seed
(S-13/S-14/S-15) to flip the appropriate conjunct — a seed that reds only one side has not
tested the composition. Until the flat and builder exist: COULD-NOT-EVALUATE, and the
composition should meanwhile be written down as a named invariant carrying
`enforcing check: NONE at proof tier` rather than living in two comment blocks.

**(e) Cost.** (i) T2 + EXP-0b. (ii) T4 (inventory) then T2. (iii) T2 after EXP-0c + the
builder; price the relational S separately.

### V4 — Authorization / signature / freeze / seize

**(a) Applies.** The authorisation kernel is `owner.ak`'s `authorised_stake_cred`: a PLB
UTxO's owner is its **inline** stake credential; a vkey owner must sign, a script owner must
withdraw. It is used by TransferAct (every PLB input) and unfracking (first PLB input, with
address equality forced on the rest). ThirdPartyAct deliberately does not use it — admin
actions are authorised by the policy's own third-party hook. Freeze is not implemented in
the core at all; it is a substandard behaviour expressed through `transfer_logic_script`.

**Two asymmetries worth putting in front of a reader:**

1. **Seizure destinations are not required to be spendable *by their holder*.** TransferAct
   requires PLB outputs to have `Some(Inline(..))` stake credentials
   (`collect_output_assets`). ThirdPartyAct's unpaired seizure destinations are checked only
   for `payment_credential == prog_logic_cred` by `drop_accum_tokens` and the closing `foldl`.
   So a seizure can land tokens at a PLB address with no stake credential or a pointer
   credential, which both holder paths then refuse: TransferAct's `expect Some(Inline(..))`
   and unfracking's same kernel.

   Precisely: **holder-unspendable, admin-recovery-only** — not "permanently unspendable".
   ThirdPartyAct deliberately bypasses holder authorisation, so a later admin action could in
   principle move it again, and calling it permanent overstates the finding. Whether *every*
   recovery branch also rejects such an output is a fixture question, not a source-reading
   one, and it is the check that would settle which of the two labels is right. Admin-only
   either way, and one `expect` on the destination shape removes the asymmetry.
2. **Registry-node updates are authorised by the substandard's own minting logic.**
   `registry_spend`'s update path requires
   `pairs.has_key(withdrawals, spent_node.minting_logic_script)` and rejects a
   `VerificationKey` minting logic. `is_field_updated_registry_node` freezes `key`, `next`
   and `minting_logic_script`, and lets the issuer change `transfer_logic_script`,
   `third_party_transfer_logic_script`, `unfracking_logic_script` and `global_state_cs` at
   will. **Programmable tokens are issuer-mutable by construction**: an issuer can install a
   seizing third-party hook at any time after issuance. That is the standard's intent, and
   it should be disclosed in exactly those words rather than inferred from four field
   comments.

**(b) Property.** `PLG_accepts(TransferAct, ctx) ⟹ ∀ PLB input i, i.address.stake_credential
= Some(Inline(c)) ∧ (c is vkey → c.pkh ∈ signatories) ∧ (c is script → c ∈ keys(withdrawals))`.

**(c) Method.** T2. Four concrete runs, twin-paired per R1: authorised-by-signature (accept),
same context with the signature removed (reject), authorised-by-withdrawal (accept), same
with the withdrawal removed (reject). Then the ∀ version if EXP-0 was generous.

**Those four are not enough, and the gap is a double-satisfaction one.** All four are
single-input, so a first-input-only authorisation bug passes every one of them. The context
that matters is **two PLB inputs with distinct owners and only one owner's authorisation**:
clean bytes must reject it (`collect_input_assets` calls `authorised_stake_cred` on *every*
PLB input), and the seeded mutant that authorises only the first must accept it. Run it in
both flavours — vkey owner + signature, and script owner + withdrawal — since they take
different branches of the kernel.

This ranks **above** V1(b)'s PLB input-count independence. V1(b) asks whether a validator that
reads nothing but the withdrawal map cares how many inputs there are; this asks whether the
validator that actually polices ownership polices all of it. Users depend on the second.

**(d) Criterion.** Per twin pair: ESTABLISHED requires *both* legs behaving as declared. A
rejecting leg without its accepting twin is COULD-NOT-EVALUATE (R1).

**(e) Cost.** T2. Reuses `mkCtx` extended with signatories and an input list; the fixture
work is shared with V1(2) and V2.

### V5 — Purpose / multi-validator interference

**(a) Applies, and the PLB half is the single cheapest check in this document.**

**First, a premise worth settling before anyone builds on it.** An objection was raised that
Aiken emits a *separate* artifact per handler — that a `.spend` flat therefore cannot
establish anything about the `.else` arm, and the `.withdraw` flats cannot reach `.publish`.
Checked against the blueprint at this commit, that is not how Aiken v1.1.22 compiles: **every
handler of a validator carries byte-identical `compiledCode`.**

| Validator | Titles | `compiledCode` |
|---|---|---|
| `programmable_logic_base` | `.spend`, `.else` | both 282 hex chars, hash `be1e5967da54…` |
| `programmable_logic_global` | `.withdraw`, `.publish`, `.else` | all 5 992, hash `a8ea72e81ac2…` |
| `unfracking` | `.withdraw`, `.publish`, `.else` | all 3 472, hash `0d4dd6bd486a…` |
| `registry_mint` | `.mint`, `.else` | both 3 856, hash `647da5bc0256…` |
| `registry_spend` | `.spend`, `.else` | both 3 024, hash `58f582d1e52f…` |

There is one script per validator; the blueprint entries differ only in datum/redeemer
schema. So varying `scriptContextScriptInfo` against the tracked flat *does* execute the
purpose-dispatch and `else` arm, and **PLG's `publish` behaviour is reachable from the flat
already in the manifest — no extra title needs importing.** That makes the certifying-purpose
check cheaper than first scoped.

The objection's *control* is still right, and is adopted as R1's localisation leg: prove the
arm you are claiming about is in the bytes under test by mutating it and requiring the
extracted flat's sha256 to change. An unchanged flat means the check targeted the wrong bytes,
whatever the title said.

- **PLB**: `else(_) { fail }`. Only the spend purpose is in any proven family (C11). One
  `native_decide` run with `scriptContextScriptInfo := .RewardingScript …` must not reach
  Halt. Same skeleton, one field changed — R1's twin already exists (`exec_accepts`).
  **T0: this is a five-line addition to `PropsBase.lean` and no new fixture.**
- **PLG / unfracking `publish` handlers** (reachable from the existing `.withdraw` flat, per
  the table above): `RegisterCredential { .. } -> True`, `_ -> False`.
  This is the standard "let anyone register my stake credential" pattern and it is
  restrictive in the right direction — in particular, **PLG's stake credential cannot be
  deregistered**, because Conway requires the script to witness its own deregistration and
  the handler returns False for `UnregisterCredential`. That answers the standing open
  question in `FORMAL_VERIFICATION_STATUS.md` ("can a third party deregister a script stake
  credential and brick withdraw-0 gated actions?") in the *favourable* direction — from
  source. A concrete certifying-purpose run turns it into a byte-level result, which is
  worth having precisely because the question was raised and left open.
  Minor consequence to note: the registration deposit is therefore locked permanently.
- **registry_mint**: `else(_) { fail }`, reachable from the flat already in the manifest.
  **registry_spend**: same shape, but it has no flat at all (EXP-0c).

**Interference.** The "purely restrictive" argument in `unfracking.ak`'s header is right but
worth stating in its sharper form: adding a withdrawal entry to a transaction both *adds* a
constraint (that script must accept) and *satisfies* any gate keyed on that credential. The
argument therefore holds exactly as long as **every credential used as a gate key belongs to
something that actually runs** — a script, or a vkey reward account whose withdrawal the
ledger requires be signed. Both hold here. That sentence is the whole safety argument for
withdraw-0 composition and it deserves to be in the methodology doc rather than a module
header.

**(d) Criterion.** ESTABLISHED = rejecting run + accepting twin. A surviving accept on any
`else` arm is a finding, not a curiosity.

**(e) Cost.** PLB: **T0**. Others: T2, batched.

### V5b — Credential-tag confusion (extends C9)

**(a) Applies.** Every gate in the protocol compares whole `Credential` values
(`has_key_or_fail`, `list.has_or_fail`, `pairs.has_key`), but the compiled comparison is
over `Data` — `Constr 0` vs `Constr 1` wrappers. Source is safe by construction; the bytes
are what the project refuses to trust from source.

**(b) Property.** A `VerificationKeyCredential h` entry never satisfies a gate keyed on
`ScriptCredential h` with the same payload bytes, and vice versa.

**(c) Method.** The rejecting twin is a **`native_decide` with no SMT at all**: `mkCtx
[(VerificationKeyCredential "PLG", 0)]` against `stakeCred = ScriptCredential "PLG"` must
not reach Halt. Same bytes in the payload, wrong tag. Then the symbolic rung: one symbolic
vkey entry plus one symbolic script entry, acceptance forces the *script* entry's hash.

**Second reason this matters beyond tag hygiene**: a realistic transaction that also
withdraws the holder's ordinary staking rewards has exactly a mixed map — `[(vkey reward
account, r), (PLG, 0), …]`. No proven family contains one today, so the theorem ladder
currently covers a map shape that real transfers do not have.

**(d) Criterion.** ESTABLISHED. A surviving accept here would be a genuine finding.

**(e) Cost.** **T0** for the rejecting twin, T1/T3 for the mixed symbolic rung. Best
value-per-build in the plan after EXP-0c.

### V6 — Datum / redeemer validation

**(a) Partially applies.**

- **Redeemers.** PLB ignores its redeemer, but the compiled V3 wrapper still extracts it
  from the context before discarding — an unproven path in the bytes (C6). PLG's redeemer is
  typed, so a malformed one fails deserialisation loudly; the constructor indices 0/1/2 are
  pinned only by golden TESTED tests.
- **Datums.** PLB accepts any datum (`_datum: Option<Data>`), which is correct — the datum is
  the substandard's state. But **datum continuity is enforced in ThirdPartyAct and unfracking
  (`output.datum == input.datum`) and not in TransferAct**. A stateful programmable token's
  per-UTxO datum can therefore be rewritten by an ordinary transfer unless its
  `transfer_logic_script` checks. That asymmetry is defensible (transfers are the
  substandard's domain) but it is an interface obligation that should be normative text, not
  an inference from which module has the `expect`.
- **Reference scripts.** Same asymmetry: pinned per pair in ThirdPartyAct (Finding 13) and
  unfracking, unconstrained in TransferAct.

**(c) Method.** Redeemer: a redeemer-independence rung on PLB (C6 — cheap, and it converts a
header comment into a theorem) plus malformed-redeemer concrete runs on PLG.

**State it relationally, not as "∀ rdmr, accepts → forwarding"** (R2b). The implication form
is not an independence claim: mutate PLB to accept only the unit redeemer and every non-unit
case goes vacuous while the theorem stays Valid — S-22 would pass on the bug it exists to
catch. The two viable shapes are `accepts(ctx, r₁) ↔ accepts(ctx, r₂)` for arbitrary `r₁, r₂`,
or accepting witnesses at several structurally discriminating redeemer shapes (`Constr 0 []`,
`Constr 1 [I 0]`, `B ""`, a deep nesting), which S-22 then kills by removing one.

Datum/reference-script asymmetries: **X**, one paragraph in the integration guide.

**(e) Cost.** PLB redeemer rung T1/T3; PLG runs T2; obligations T4.

### V6b — The Data-layout contract

**(a) Applies.** `with_key_and_transfer_logic` reaches field 3, `..._3rd_party_logic` field
4, `..._unfracking_logic` field 5, `..._minting_logic` field 2, and the params accessors
fields 0/1/2 — all by positional `head_list`/`tail_list` with no shape validation, trusting
`registry_mint` and `protocol_params_mint` to have shape-checked at write time. A field
reorder silently changes which credential authorises what.

**(b) Property.** Each accessor reads the index the golden layout test pins.

**(c) Method.** One concrete run per accessor over a node datum whose six credential fields
are **pairwise distinguishable**, asserting the branch gates on the expected one. This is the
Lean-tier version of the golden tests, and it is stronger than them in the one way that
matters: it exercises the *compiled* extraction rather than an Aiken-side destructuring.

**Distinguishable fields alone do not prove which accessor ran**, though — a run can accept
without reaching the accessor at all, or because the expected credential also happens to
satisfy some earlier check. Two additions make the claim real: (i) build the accepting context
with **exactly** the expected credential's withdrawal present and no other, so an accessor
reading an adjacent field has nothing to match; (ii) apply R1's localisation leg — change the
accessor's `tail_list` depth by one in the source, prove the flat changed, and require the
accept/reject pair to flip. Without (ii) the run shows the branch is satisfiable, not that it
read field 4.

**(e) Cost.** T2, shares fixtures with V4 and V11.

### V7 — Replay / uniqueness / thread token (registry integrity)

**(a) Applies, and it is the class whose failure is most total.** If a covering node could be
forged whose `(key, next)` range spans a *registered* policy, a `TokenDoesNotExist` proof
would let a holder transfer that policy without ever invoking its `transfer_logic_script` —
a complete bypass of V4 for that token. Everything protecting against that is registry
integrity.

Reading the source, the chain is clean and the argument is short enough to state in full:
`RegistryInit` is one-shot on `utxo_ref`; Insert requires exactly one covering input and
exactly two node outputs, both passed through `validate_directory_node_output` (address
inherited from the covering input, no reference script, exactly ada + node_cs, exactly one
NFT at quantity 1, `key < next`, NFT name == key); the inserted node takes
`covering.next` and the covering node takes `next := key`, and since both outputs must
satisfy `key < next` strictly, `covering.key < key < covering.next` follows — so duplicate
keys are impossible and the list stays sorted. `registry_spend` is the sole spender and
refuses to let a node's own `key` be minted or burned in the same transaction.

The load-bearing assumption underneath, stated in the code and worth stating in the
methodology doc too: **node authentication at read time is `peek_first == registry_node_cs`
— the policy id of the first non-ada asset, with no name or quantity check.** It is sound
only by the induction above (any UTxO carrying that policy is a genuine node). That
induction is precisely what a proof about `registry_mint` + `registry_spend` would
establish, and it is why `registry_spend`'s absence from the flat inventory matters more
than its 3 178 source bytes suggest.

**And there is a double-satisfaction shape here that V1 does not reach.** `registry_spend`'s
insert arm authorises itself on a *transaction-global* signal: "a registry node NFT was minted
with `amount > 0`". That signal is the same for every registry-node spend in the transaction.
Two authentic nodes spent together would each see the same mint and each conclude "an insert
is happening, `registry_mint` will validate the structure" — one witness, N executions, which
is the classic shape.

What actually stops it is on the *other* side: `registry_mint`'s
`expect [covering_input] = list.filter(inputs, has_currency_symbol(policy_id))` requires
**exactly one** registry-NFT-bearing input. So the guard protecting `registry_spend` lives in
`registry_mint`, and neither validator's own tests can express that dependency. Relaxing that
destructure to "take the first covering input" is the seed (S-17): construct an insert that
also consumes a second authentic node, and require the system-level fixture to reject it.
The ordering/uniqueness theorem proposed above does *not* cover this — it reasons about one
node's key bounds, not about how many spend executions one mint can satisfy.

**(c) Method.** S for the ordering/uniqueness arithmetic (`less_than_bytearray` chains are
the friendliest shape Blaster will see in this codebase, so this is a plausible second SMT
success after the PLB ladder); K for Init/Insert shape runs, gated on EXP-0b; X for the
spender binding (V13).

**(e) Cost.** T2/T3, plus EXP-0c to get a `registry_spend` flat at all.

### V8 — Unbounded / DoS

**(a) Partially applies.** No loop here is unbounded in the dangerous sense — every recursion
is over a transaction-sized list, and Cardano's fee model prices them. Three real residuals:

1. **Width has no enforced bound anywhere** (C8). Neither PLB, PLG, unfracking nor the ledger
   caps the withdrawal count, and production transactions already exceed four entries: a
   multi-policy TransferAct carries PLG + one transfer-logic withdrawal *per policy* +
   holder auth, plus any unrelated vkey reward withdrawals the holder adds. So rung 4's
   comment ("exactly the width of the unfracking composition") gives 4 more significance
   than the composition has, and widths ∉ {1,2,4} are production-reachable and unproven.
2. **`new_withdrawal_checker` builds a closure chain of depth |withdrawals|**, evaluated per
   lookup — so cost is O(policies × withdrawals). Self-inflicted for a solo transaction, but
   in a **multi-party transaction** (a batcher, a co-signed swap) a counterparty can add
   withdrawal entries and push the transaction over `maxTxExUnits`, invalidating it. That is
   the collaborative-transaction DoS shape, and it is the reason the width question has an
   economic edge and not only a proof-coverage edge.
3. **`maxValueSize` on fracked UTxOs** — already tracked as the unfracking shape-shrinking
   claim.

**(c) Method.** (1) climb the ladder to 5, 8, 16 until Blaster stops, and **record the stop as
COULD-NOT-EVALUATE** — that number measures the toolchain and answers Phil's Q4 with a
figure rather than an anecdote. (2) and (3) are bench-vs-ceiling CI pins (already next-step
#4 in the status file), not theorems.

**A rung that succeeds is not exempt from R4, and an earlier draft of this document said it
was.** The two outcomes are different objects:

| Rung outcome | What it is | Control owed |
|---|---|---|
| No verdict inside the timeout | a measurement of Blaster's reach | **NONE, by form** — there is nothing to seed |
| Returns Valid | a **positive safety check** | **S-26**: add that exact width's statement to the existing always-accept mutant and require Falsified, plus a last-slot accepting witness at fuel raised for the width (R6) |

Treating every rung as "just a measurement" would let a widened ladder accumulate green
∀-theorems that have never been shown able to fail — the decoration failure mode, arriving
through the door marked *tool benchmarking*.

**(e) Cost.** (1) T3, one build per rung, cheap individually. (2)(3) T4.

### V9 — Min-UTxO / ada-only / dust

**(a) Partially applies — and the interesting direction is the reverse of the usual one.**
Scripts cannot observe protocol parameters, so "does the validator enforce the min-UTxO
floor" is the wrong question; the ledger enforces it. The question that has already bitten
this codebase (issue #96) is the opposite: **does the validator accidentally make a
ledger-legal ada amount unsatisfiable?** Equality on lovelace did exactly that, and the
ratchet fixed it.

**(b) Property.** Acceptance is invariant under the lovelace field wherever the design says
ada is free (unfracking pairs, TransferAct) and monotone where it says ratchet (ThirdPartyAct).

**(c) Method.** A ∀-lovelace rung — **relational for the invariance half** (R2b):
`accepts(ctx, ℓ₁) ↔ accepts(ctx, ℓ₂)`. The implication form would survive S-23 vacuously,
which matters more here than elsewhere because the #96 hazard *was* an accidental narrowing of
acceptance on exactly this field — a control that cannot see a narrowing cannot see #96's
class. The ratchet half is genuinely monotone (`ℓ_out ≥ ℓ_in`) and is fine as an implication.

One symbolic integer with everything else concrete is a *good* Blaster shape, so this is a
plausible early T2 win, and it re-proves the param-sensitivity doc's central claim at the byte
tier rather than the fixture tier.

**(e) Cost.** T2/T3.

### V10 — Validity range / time manipulation

**(a) Does not apply.** No validator reads `validity_range` — confirmed mechanically, not by
eye: a grep for `validity_range|interval|Interval|posix|Posix` across every validator and lib
source fetched at this commit (`programmable_logic_base`, `programmable_logic_global`,
`unfracking`, `registry_mint`, `registry_spend`, `protocol_params_mint`, `issuance_mint`, the
five `programmable_logic/*` modules and all eight lib modules) returns nothing. There is no
deadline, no expiry, no time-gated authority anywhere in the protocol.

**This is a well-reasoned N/A that is also cheap to *prove*** — provided the statement is the
right shape. `mkCtx` already parameterises `range` as a concrete `Data`; making it symbolic
turns "we don't use time" from a source claim into a byte-level theorem. But per R2b it must be
`accepts(ctx, range₁) ↔ accepts(ctx, range₂)`, not "∀ range, accepts → forwarding": the latter
is trivially preserved by S-24's bogus range gate, so the theorem would certify a validator
that *had* grown a time dependency. Side benefit either way: it is a second, structurally
different family for the existing ladder, which partly answers "are these theorems easy because
the validator is small, or because the family is narrow?"

**(e) Cost.** **T0/T1** on PLB. Batch it with V5 and V5b.

### V11 — Reference input / reference script trust

**(a) Partially applies.** Of the edges I first opened, one is closed outright, one survives
in a changed and worse form, and one is closed by an induction with no theorem on either end.
Recorded with the resolutions rather than dropped, because *why* something is safe is worth
writing down — and because one of these resolutions moved a hazard from "attack" to
"unfixable deployment mistake", which is a promotion, not a dismissal.

Reference inputs are unauthenticated by the ledger — anyone can reference any UTxO — so all
trust rests on the NFT-policy checks, and both readers (`get_protocol_params_ref`,
`new_registry_node_getter` / `locate_registry_node`) authenticate by **policy id via
`peek_first` only**: first non-ada policy, no asset name, no quantity.

1. **First-match selection of the params UTxO — CLOSED.** `get_protocol_params_ref` returns
   the first matching reference input, so if two params NFTs existed the transaction author
   would choose the protocol's parameters. `protocol_params_mint` makes that unreachable:
   one-shot on `utxo_ref`, `has_policy_nft_strictly` (exactly one name, quantity 1, name ==
   `"ProtocolParams"`), and `else(_) { fail }` so there is no burn path. Exactly one params
   NFT exists, forever.
2. **Decoy asset bricking the params lookup — the *attack* is closed; the *construction
   invariant* is live, and it is worse.** The worry as I first wrote it was a params UTxO
   respent with a lower-sorting decoy policy, so `peek_first` walks past it. As an attack it
   is unreachable: `protocol_params_mint` locks the NFT at
   `address.from_script(always_fail_hash)`, so the UTxO can never be spent.

   But the hazard does not need a spend — it only needs the **deployment transaction** to
   create that output with an extra asset. `protocol_params_mint` checks the mint
   (`has_policy_nft_strictly`: one name, quantity 1), the datum (full
   `ProgrammableLogicGlobalParams` decode) and the address — and **does not constrain what
   else the output's value contains**. `get_protocol_params_ref` later requires the params
   policy to be `peek_first`, the first *non-ada* policy. Ship the params NFT alongside any
   policy sorting before it and the lookup never matches: PLG and `unfracking` fail on every
   transaction, forever, with no spend path to fix it.

   So this is not a mutable-reference attack. It is an **immutable trust-root construction
   invariant**, in the same family as V13 and with the same one-shot-to-get-it-right property.
   It belongs in the deployment checker as a value-shape assertion, not only a datum one. If
   the team would rather have it enforced on-chain, the fix is one `expect` in
   `protocol_params_mint` pinning the output to exactly ada + the params NFT — the same shape
   `validate_directory_node_output` already pins for registry nodes, and the asymmetry between
   the two is itself the tell.
3. **Decoy registry node — CLOSED by induction, but the induction has no theorem on either
   end.** `validate_directory_node_output` pins a node's value to exactly ada + node_cs with
   one NFT at quantity 1, and `registry_spend` is the sole spender, so `peek_first` on a
   node is always the registry policy and no non-node UTxO can carry it. That induction spans
   `registry_mint` × `registry_spend`, and `registry_spend` has no flat (EXP-0c) — so the one
   thing holding up node authentication is the least-verified thing in the repo.
4. **Reference scripts on PLB outputs — still open.** Pinned per pair in ThirdPartyAct
   (Finding 13) and unfracking, unconstrained in TransferAct (see V6).

**(c) Method.** Three runs, and **they do not all have the same polarity** — grouping them
under one criterion was an error in the earlier draft of this document, so the split is
spelled out:

| Run | What a rejection means | The gate that establishes safety |
|---|---|---|
| Fake params UTxO ordered before the real one | Safety: PLG refuses an unauthenticated params source | the run itself |
| Node ref input whose first non-ada policy is not the registry policy | Safety: node authentication holds | the run itself |
| **Params UTxO carrying a lower-sorting co-asset** | **Not safety — this is the brick.** PLG *must* reject it, and that rejection is the permanent-liveness failure, not evidence against it | **`protocol_params_mint` or the deployment checker refusing to build it** |

For the third row the pass/fail is therefore about the *construction*, not the read:
a clean deployment must be accepted by the pre-submission gate, and the same deployment plus a
lower-sorting policy must be **rejected** by it. If the gate accepts a construction that PLG
then rejects on-chain, the safety property is **REFUTED** — the protocol was deployed dead —
and reading that outcome as "PLG correctly rejected a bad context" inverts it.

**(d) Criterion.** Rows 1–2: ESTABLISHED per run, twin-paired per R1. Row 3: ESTABLISHED only
on the construction gate; a PLG rejection there is the demonstration of the hazard.

R3 still applies in the other direction for rows 1–2: those decoy contexts are largely
ledger-unreachable given `protocol_params_mint`, so an unexpected **accept** is not
automatically a finding — check reachability first.

**(e) Cost.** T2 for rows 1–2. Row 3 is T4 and belongs to the V13 checker.

### V12 — Datum-hash vs inline confusion

**(a) Partially applies, mostly already closed.** Params and registry nodes are read through
`expect InlineDatum(...)`, so a hash datum rejects loudly. ThirdPartyAct and unfracking
compare `output.datum == input.datum`, which compares the `Datum` *constructor* too — so an
inline↔hash swap on a continuing output is caught for free. TransferAct compares nothing
(V6). One concrete rejecting run per read site, twin-paired, closes the class at the byte
tier.

**(e) Cost.** T2, batched with V11's decoy runs (same fixture family).

### V13 — Deployment / trust-root closure *(CIP-113-specific; highest severity in this document)*

**(a) Applies, cross-cutting, and no on-chain check exists or can exist.**

The protocol's parameters form a cycle that nothing validates:

```
params_policy ──parameter──▶ PLG              (programmable_logic_global(params_policy))
PLG credential ──parameter──▶ PLB              (programmable_logic_base(stake_cred))
PLB script hash ──must equal──▶ params datum field 1 (prog_logic_cred)
params datum field 0 (registry_node_cs) ──must equal──▶ policy id of the deployed registry_mint
registry_mint's registry_spend_cred ──must equal──▶ the deployed registry_spend credential
params datum field 2 (unfracking_cred) ──must equal──▶ the deployed unfracking credential
protocol_params_mint's always_fail_hash ──must equal──▶ the deployed always_fail validator
```

**And the datum is write-once.** `protocol_params_mint` shape-checks it at mint
(`expect _params: ProgrammableLogicGlobalParams`) — field 0 is a ByteArray, fields 1 and 2 are
`Credential`s — and then locks the NFT at `address.from_script(always_fail_hash)`. Shape is
checked; **closure is never checked**; and because the UTxO can never be spent, a wrong value
can never be corrected. Recovering from a one-byte mistake in that datum means redeploying
under a new `params_policy` — which changes PLG's hash, which changes PLB's hash, which means
migrating every programmable UTxO in existence.

So the deployment-manifest checker is not a nice-to-have that catches a bug early. **It is the
only opportunity, ever, to catch it.**

PLG and `unfracking` identify "a PLB UTxO" as `payment_credential == prog_logic_cred`, read
from the params **datum**. If that datum names a credential other than the deployed PLB's
hash, then every PLB spend is forwarded to a PLG run that treats those inputs as ordinary
non-programmable inputs and constrains nothing about them — **a total break of every
transfer, seizure and conservation guarantee, produced purely by a configuration mistake**,
with all five theorems in PR #101 still perfectly true.

That last clause is the point. The ladder is universally quantified over the deployment
parameter, which is the right and strongest form — and it is exactly that quantifier that
makes this failure mode invisible to it. A ∀-over-parameter theorem cannot see a wrong
parameter.

**And the quantifier is narrower than the prose, in a way that lands precisely here.** The
theorems read `∀ (param : ByteString), … appliedBase.prop (.ScriptCredential param) …` — the
constructor is *fixed*, and only the inner 28 bytes are quantified. So the honest statement is
"for every **script-credential hash**", not "for every deployment parameter". Every place this
document, the source comments, and the methodology doc say "proven for all deployments at
once" should say "for all script-credential parameterisations".

That matters because of the second instance of this class: **nothing requires PLB's
`stake_cred` to be a `Script` credential.** Parameterised with `VerificationKey h`, PLB is
satisfied by a signature-backed reward withdrawal and PLG never runs at all — and that
deployment is not a case where the theorem is true-but-unhelpful, it is a case **outside the
theorem family entirely**. Two closers, both cheap: a `native_decide` accepting run with a
vkey parameter, demonstrating the hazard at the byte tier; and a manifest assertion that the
applied parameter's constructor is `Script`, so the gap between the family and the deployment
is mechanically pinned rather than trusted.

**(c) Method. X — a mechanical deployment-manifest checker**, not a theorem:

- read the blueprint's `hash` field per validator and its declared parameters;
- recompute the closure: apply `params_policy` to PLG → hash → apply to PLB → hash;
- read the params datum **that the deployment transaction will write**, before it is
  submitted, and compare every edge byte-for-byte;
- assert the params output's **value shape** — exactly ada + the params NFT — because a
  lower-sorting co-resident asset permanently hides the UTxO from `peek_first` (V11.2);
- assert PLB's applied `stake_cred` has constructor `Script`, since the theorem family covers
  only script-credential parameterisations;
- fail **by name** on any unclosed edge, and on any parameter it cannot classify — never a
  silent skip.

Run it as a **pre-submission gate on the deployment transaction**, not as a post-hoc audit —
after submission there is nothing to fix.

This is the same shape as the lock-file identity checker in the verification skill, and the
same blind-spot discipline applies: it should state plainly that it cannot tell that a
correct value landed in the wrong column.

**(d) Criterion.** RED on any unclosed edge. Falsified by perturbing one byte of one
parameter and requiring the checker to name that edge.

**(e) Cost.** **T4 — no build.** Shell + `jq` over `plutus.json` plus the deployment config.
Cheapest high-severity coverage in this document, and it is the one class where the existing
formal work actively cannot help.

### V14 — Substandard-hook aliasing *(CIP-113-specific)*

**(a) Applies at the interface, not inside these bytes.** Nothing prevents two registry nodes
from naming the **same** `transfer_logic_script` (or `third_party_transfer_logic_script`, or
`unfracking_logic_script`). When they do, **one withdrawal entry satisfies the gate for both
policies**, and the hook script is invoked once for a transaction touching both.

A hook is a withdraw validator, so it *does* have its own redeemer and a substandard may well
require policy identifiers in it. The gap is not that the hook is blind — it is that **the core
never binds that redeemer to the set of registry nodes naming the hook.** A hook that names
policy A in its redeemer, validates A, and returns True satisfies the gate for B as well,
because PLG and `unfracking` only ask "is this credential in `withdrawals`". Nothing forces the
hook to have considered B at all. That is a double-satisfaction vulnerability located in the
substandard, enabled by an unbound gate in the core.

Note the contrast that makes this a real asymmetry rather than a theoretical one:
`minting_logic_script` **cannot** be aliased, because the policy id is
`blake2b_224(template ⊕ minting_logic_hash)` — a deterministic function of it. The three
other hooks have no such binding.

**(c) Method. X — normative text plus a conformance test**, in the substandard developer
guide: *"a logic script MUST validate every registry node that names it as a hook, not merely
the one its own redeemer identifies."* The conformance fixture: two aliased nodes (policies A
and B sharing the hook), a hook redeemer naming only A, and a transaction touching both — the
kit must reject it unless the hook proves it covered B too.

**(e) Cost.** **T4.** One paragraph and one fixture. Worth doing before third-party
substandards exist rather than after.

### V15 — Fracking / freeze collateral damage *(CIP-113-specific)*

**(a) Applies at the governance layer.** The design rationale is explicit: a freeze scoped to
one policy locks every co-resident asset in the same UTxO, and unfracking is the escape
hatch. But the escape hatch is **default-forbidden**: `unfracking_logic_script` defaults to
`empty_vkey`, which no ledger withdrawal can match, so unfracking is impossible for that
policy until its issuer opts in.

Composed: to rescue assets from a UTxO frozen by hostile policy F, you must unfrack **F** —
which requires **F's issuer** to have set F's hook. The mitigation for a hostile freeze is
opt-in by the hostile party.

The attack is bounded, and the bound is worth stating alongside it: contaminating a victim's
existing UTxO requires spending it, which requires the victim's authorisation. An attacker
can only create a *new* PLB UTxO at the victim's address holding F. The residual risk is
therefore consolidation — a holder who merges an unknown token into a UTxO holding valuable
ones has accepted that policy's freeze authority over all of them.

**(c) Method. X — disclosure**, in the integration guide's wallet-behaviour section:
programmable-token wallets should not auto-consolidate across policies, and should surface a
policy's `unfracking_logic_script` status (set / unset) before accepting its tokens into a
shared UTxO. Not a code change; a normative note and a wallet-UX obligation.

**(e) Cost.** **T4.**

### V16 — Verified-inventory completeness

Covered in EXP-0c. Restated here so it appears in the taxonomy: *"which deployed validators
are not under verification, and does anything go red about that?"* is itself a coverage class,
and it is the one where "untracked means uncovered" bites hardest — the inventory here is
explicit (good) but partial, and partial-and-explicit reads identically to complete unless a
check says otherwise.

### V17 — Integer / quantity domain

**Does not apply.** Plutus `Integer` is arbitrary-precision; there is no fixed-width
arithmetic, no truncation and no wraparound anywhere in these validators. Quantity handling
is sign-aware by design (`sum_if_non_zero` collapses full burns, `contains` uses `>=`,
`assets.union` deliberately preserves zero entries so a fully-burned policy still triggers
its proof and transfer-logic checks — that last one is an anti-bypass measure worth a
dedicated control, seed S-7).

The only residual is R3: Lean context families admit negative output quantities that the
ledger cannot produce, so a counterexample built on one is spurious.

### V18 — Proof-family reachability

Covered as rule R3 in §3. Listed as a class because it is the methodological failure mode
most likely to produce a wrong *conclusion* from a correct *run* once this harness is
extended to validators whose contexts are rich enough for Z3 to find creative
counterexamples.

### V19 — Attacker-controlled positional indices *(added after the adversarial pass)*

**(a) Applies, and it deserved its own row rather than being folded under V6.** Three redeemer
fields are *pointers into ledger-ordered lists*, supplied by the transaction author and
security-bearing:

- `registry_node_idx` (ThirdPartyAct, `UnfrackingRedeemer`) selects which registry node — and
  therefore which policy is acted on and which hook must be invoked;
- `outputs_start_idx` (both) partitions `tx.outputs` into a prefix that is *accumulated as
  value* and a region that is *paired positionally with inputs*;
- the **order** of `TransferAct`'s `proofs` list, which `verify_proofs` consumes in lockstep
  with `input_assets`.

Out-of-range and negative indices are handled loudly (`aiken_list.at` → `None` → `expect`
fails; `drop_accum_*`'s `expect [output, ..tail]` fails when the list runs out). The
interesting question is not the extremes but the **boundary**: with `outputs_start_idx` at
0, 1, `len(outputs)` and `len(outputs)+1`, is every output counted exactly once — never both
as prefix value *and* as a paired continuation, never skipped?

Reading it, the accounting is disjoint by construction: `drop_accum_tokens` returns the
*remainder* after dropping `n`, the pair walk consumes from that remainder via
`list.tail(outputs)` per PLB input, and the closing `foldl` folds what is left. Each output is
visited by exactly one of the three regions. That is the invariant, and it is exactly the kind
that an off-by-one silently breaks while every test stays green.

**(b) Property.** For all `outputs_start_idx` and all input/output arrangements, the acted
policy's total over `tx.outputs` used by the conservation check equals the sum over the three
regions, with each output contributing to exactly one.

**(c) Method.** K, boundary fixtures at 0, 1, `len`, `len+1`, in both ThirdPartyAct and
unfracking. Cheap once the context builder exists, and the fixtures are shared with V2. The
∀-version is an S theorem over the shaped output-list family, priced separately.

**(d) Criterion — and do not inflate it.** Four boundary fixtures are four executions, not a
universal partition theorem. Label them **KERNEL-PROVED at those boundaries** (a TESTED-shaped
family), and reserve ESTABLISHED for the S theorem over the shaped list family, with an
inhabitant per R2 and S-18 as its control. Stating (b) as a ∀ and then discharging four points
would be exactly the scope inflation R2 and R3 exist to prevent — including when this document
does it.

A double-count is a **value-accounting** finding (conservation satisfiable without the tokens
existing); a skip is a leak.

**(e) Cost.** T2, folded into V2's fixture work. Seeds S-18.

### V20 — Claim-integrity gates *(added after the adversarial pass; companion C12–C14)*

**(a) Applies — this is the class where the *evidence* rather than the *validator* is the
attack surface**, and the PR's central distinction is the thing at risk.

1. **The axiom separation has no enforcing check.** Blaster's own disclosure warning
   ("SMT-verified, no proof term") is emitted only when `warn.sorry` is true, and
   `PropsBase.lean` sets `set_option warn.sorry false` **file-wide**. So Blaster's honesty
   label is silenced, and a stray `sorry` would compile silently. The `#print axioms` lines at
   the bottom print into the build log, but CI runs `lake build` and gates on nothing — the
   "axiom separation correct" check was a human reading a log once. The SMT-vs-KERNEL
   distinction is one of this PR's genuinely good properties and it is currently enforced by
   no mechanism.
2. **`.prop` and `.exec` are joined only by optimizer trust** — R5. The trust base in §7 names
   Z3 and the Lean→SMT translation, not the prep-time optimization whose output *is* the
   object of every SMT theorem.
3. **Fuel is a claim coordinate** — R6. `600` is baked into both definitions, and every
   "acceptance" means *within 600 steps*.

**(c) Method.** All three are cheap and none needs a new mechanism:

- `#guard_msgs` around each `#print axioms`. The expected-output comment makes `lake build`
  itself fail on any axiom-set drift — no script, kernel-adjacent, and enforced by the CI that
  already exists. Then drop the file-wide `warn.sorry false` or scope it per theorem; three
  expected warnings are informative, not noise.

  **But the pin is itself an inventory, and an inventory covers only what it enumerates.**
  `#guard_msgs` constrains exactly the declarations a guard names. A *newly added, unpinned*
  theorem carrying a `sorry` still compiles clean, and restoring `warn.sorry` emits a warning
  without failing the build. This is EXP-0c's pattern one level up — the flats inventory omits
  validators, the axiom inventory omits theorems, and both read identically to complete unless
  something says otherwise. So the gate needs two legs:

  1. **Per-claim pin** — every published theorem has a `#guard_msgs`-pinned expected axiom set
     (seed **S-20a**: replace a pinned theorem's proof with `sorry`, guard must red);
  2. **Inventory rule** — a check that every theorem the project publishes *has* a pin, or a
     source/CI gate rejecting human `sorry` outright (seed **S-20b**: add a new *unpinned*
     theorem containing `sorry` and require the inventory leg to catch it).

  Leg 1 without leg 2 is a gate that protects yesterday's claims and not tomorrow's.
- Prop-side concrete controls: `#blaster` goals asserting the accepting context succeeds and
  the foreign one fails **on `.prop`**, symmetric to the existing exec-side kernel pair.
- One sentence in §7 naming the prep optimizer in the SMT trust base; fuel and build-env added
  to `MANIFEST.md` as identity coordinates 4 and 5.

**(d) Criterion.** RED on axiom-set drift **and** RED on an unpinned published claim.
Falsification is mandatory and now two-legged (S-20a, S-20b) — "insert a `sorry` somewhere and
watch it fail" is too loose a criterion to state, because *where* decides whether it fails at
all. A gate on the honesty of the evidence that has never been shown able to fail is the
purest instance of the decoration failure mode, and a gate shown able to fail only on the
declarations it already knows about is the second purest.

**(e) Cost.** **T4 + one T0 build.** Highest ratio of "protects the PR's own headline claim"
to effort in this document.

---

## 6. Priority ordering

**Tier A — load-bearing, do first.**

| # | Item | Why it leads | Cost |
|---|---|---|---|
| 1 | **V13** deployment/trust-root checker | A misconfigured params datum is a total break that leaves all five existing theorems true — the ∀-over-parameter form, the strongest thing about the ladder, is precisely what cannot see it. And the datum is **write-once at an always-fail address**, so a pre-submission gate is the only chance there will ever be | T4, no build |
| 2 | **EXP-0c / V16** inventory completeness | `registry_spend`, `protocol_params_mint`, `issuance_mint` are load-bearing and outside every tier above TESTED. `registry_spend` in particular is the sole thing holding up the induction that makes policy-id-only node authentication sound (V11.3) | T4, no build |
| 3 | **EXP-0** PLG/unfracking prep feasibility | Partitions the plan. Its failure is a publishable toolchain measurement, not a dead end | 1 build, timeboxed |
| 4 | **V1(c)** PLG UnfrackingAct forwarding theorem | The second link of the chain, at its cheapest point — PLB-shaped, one indirection through the params lookup | T2 |
| 5 | **V20** axiom pin (both legs) + prop-side controls | The SMT-vs-KERNEL separation is one of the PR's genuinely distinguishing properties and nothing currently enforces it. Ahead of the cheap PLB work deliberately: otherwise every theorem added below can silently acquire an unapproved axiom before the higher-value validator work even starts | T4 + 1 build |
| 6 | **V5 + V5b + V10 on PLB**, batched | Three classes, one build, no new fixtures, and V5b's rejecting twin needs no SMT at all | **T0/T1** |

**Tier B — high value, gated on EXP-0.** Two of these outrank the rest and are called out
because they test obligations users actually depend on rather than properties of the smallest
validator:

- **V4's two-owner authorisation control (S-16)** — the four single-input twins all pass a
  first-input-only bug. This ranks above V1(b).
- **V7's covering-input double satisfaction (S-17)** — one mint witness, N `registry_spend`
  executions, guarded from the other validator.

Then: V7 ordering/uniqueness (the friendliest SMT shape in the codebase) · V2 conservation per
branch · V19 index boundaries (shares V2's fixtures) · V9 ∀-lovelace · V11 decoy reference
inputs · V6b Data-layout runs.

**Tier C — cheap, do when convenient.**
V8 width ladder to 5/8/16 with the stop recorded · V6 symbolic-redeemer rung on PLB ·
V12 hash-datum runs · the C10 witnesses for rungs 2 and 4 · the ledger-shaped accepting
witness (C4b).

**Already partly covered by PR #101.**
V1(a) — the PLB half, widths {1,2,4}, one skeleton, all-script maps.
V5 — the spend purpose, positively (accept) but not negatively (the `else` arm).

**Genuinely N/A, with reasons.**
V10 (no validator reads time — and cheaply provable as such) · V17 (unbounded integers, no
fixed-width arithmetic) · V9 in its usual form (min-UTxO is not observable on-chain; the
useful direction is the insensitivity theorem).

**On the PR's own rating.** Half 1 (§4 of `invariants-findings.md`) tests it in detail and I
agree with its revised, two-pass conclusion: #1 is the indispensable *control*, #3–5 are the
only statements with the shape the composition needs, and their current narrowness is about
**family width** — one skeleton, all-script withdrawal maps, **script-only parameters**, fixed
redeemer, fuel 600 — rather than about entry count. The implication for this plan is that
widening the family (V5b's mixed-credential rung, V10's symbolic validity range, C6's symbolic
redeemer, V1(b)'s input-count independence) buys more per build than climbing to five entries.

One refinement his instinct deserves, which I did not give it in the first draft: the kernel
pair is the **only** part of the file that touches `appliedBase.exec`, the executable object,
and the only part that certifies within-fuel halting. The ladder speaks of `.prop` through two
unnamed trust links — the prep optimizer (R5) and the fuel bound (R6) — plus Z3. So "the
concrete pair matters most" has a defensible technical reading, and the response is not to
re-rank but to converge the classes: per-rung witnesses, prop-side controls, and the wider
families each transfer real certified content into #3–5.

---

## 7. Reuse-first: what each proposed check extends

No new mechanism is proposed except one, and it is named explicitly.

| Existing piece | Extended by | Serving |
|---|---|---|
| `mkCtx (wdrl : Withdrawals)` | Add parameters, one field at a time: `inputs`, `outputs`, `mint`, `signatories`, `datum`, `range`, `rdmr`, `scriptInfo`. Keep it **one** builder — a second skeleton would fork the family vocabulary | V1(2), V5, V5b, V6, V10 |
| `appliedBase.exec` + `isHaltB` / `isHaltB_sound` | Nothing new. Every K-row is another `native_decide` over the same reflection | all K rows |
| `appliedBase.prop` | Nothing new. Every S-row is another `blaster` goal over the same applied program | all S rows |
| `#import_uplc` + `flats/*.flat` | Two flats already exist and are unused by any theorem (`registry_mint`, `unfracking`, plus PLG). No extraction work needed for three of the four | V2, V3, V7 |
| `baseInputs = toTerm param :: spendingInputs ctx` | **The one genuinely new piece**: the rewarding-purpose analogue for `withdraw` validators. Whether `CardanoLedgerApiBlaster` supplies it is COULD-NOT-EVALUATE from here — the status file calls it "needs a rewarding-context builder". It is *one* helper, shared by PLG, `unfracking` and every future substandard hook, which is why it is worth the build | V1(c), V2, V4, V6, V9 |
| `MutantControl.lean`'s `#blaster (solve-result: 1)` + `mutant_accepts_*` twin | Every control in §8 is another entry in this file's two-leg pattern | all C rows |
| `scripts/falsification-control.sh` (5 legs) | Unchanged. Each seed is another run, not another script | all C rows |
| `cip113-mutation-seeds` sealed-patch tooling | Already exists and already has second-author independence as its stated point. §8's seeds go in as new sealed patches | all C rows |
| `extract-flats.sh --check` | One `DELIBERATELY_UNVERIFIED` array + a title-set diff | EXP-0c / V16 |
| `ledger_shape.is_ledger_shaped` | Mirror one canonical fixture into the Lean side as a ledger-shaped accepting witness | C4b |

**Justification for the one new mechanism:** there is no way to execute a `withdraw` handler
without a rewarding script-context builder, and `spendingInputs` cannot be adapted — the
purpose determines the wrapper's argument shape. Everything else on this list is a new *value*
passed to an existing function.

---

## 8. Falsification duty — the seed list

Every positive check above ships with a seeded violation it must catch, mirroring the
existing five-leg control. These are written as **source mutations rebuilt through the real
`aiken build`**, because a hand-edited flat proves nothing about the pipeline. Seeds marked
★ are ones I would expect the current controls to *miss*, and are therefore the ones worth
sealing first.

| ID | Target | Mutation | Must be caught by | Direction |
|---|---|---|---|---|
| ★S-1 | `programmable_logic_base.ak` | accept whichever credential is **first** rather than `stake_cred`. Compile-valid form (the module imports only `address`, `transaction`, `pairs` — a bare `list.head` would not build): `when self.withdrawals is { [] -> False, [Pair(c, _), ..] -> pairs.has_key_or_fail(self.withdrawals, c) }` | the ∀ forwarding ladder must go Falsified. The existing polarity control may **not** catch it: the mutant still rejects plenty of contexts | over-acceptance, subtle |
| ★S-2 | `programmable_logic_base.ak` | `else(_) { fail }` → `else(_) { True }` | V5's non-spend rejecting run must flip to accept | over-acceptance |
| ★S-3 | `lib/pairs.ak` | `has_key_or_fail` compares inner hashes only (unwrap both credentials before `==`) | V5b's vkey-tagged-`"PLG"` rejecting run must flip to accept | tag confusion |
| S-4 | `third_party.ak` | drop `expect output.address == input.address` | an owner-swap pairing run | theft |
| ★S-5 | `third_party.ak` | drop `expect !dict.is_empty(input_tokens_at)` | **two** independent runs: a contamination run (Finding 12's stated purpose) **and** an origin-node run (`registry_node_idx` → origin, `key = #""`). The second is the undocumented job this line does | over-acceptance ×2 |
| S-6 | `programmable_logic/unfracking.ak` | conservation `==` → `tokens.contains` | already CAUGHT at Aiken tier (2 properties); add the Lean-tier leg once V2 exists | fabrication |
| ★S-7 | `lib/assets.ak` | `union` drops zero-valued entries (remove the "preserving null assets" behaviour) | a fully-burned-policy transfer must still require its proof and transfer-logic withdrawal. Nothing I can see currently tests this bypass | proof bypass |
| ★S-8 | `lib/utils.ak` | `is_programmable_token_id_valid` → `True` | a registry Insert claiming a policy id the registrar does not control must be rejected. **The registry's whole unforgeability rests on this line** | forgery |
| S-9 | `lib/linked_list.ak` | `is_updated_directory_node`'s `next: insert_key` → `next: original.next` | a duplicate-key / broken-chain insert run | list integrity |
| ~~S-10~~ | ~~`params.ak` `peek_first` → full scan~~ | **Withdrawn.** The mutation is more permissive, but possession of the unique params policy *is* the authenticity signal, so on ledger-reachable state a full scan is a liveness improvement rather than a vulnerability — and the forged-policy decoy that would make it a vulnerability is unreachable (R3). A mutation kill on an unreachable context must not be sold as security sensitivity. **Replaced by S-10′** | — |
| ★S-10′ | `protocol_params_mint.ak` | deployment-side: create the params output with a valid NFT **plus** a lower-sorting non-ada policy | either the mint gate rejects it, or the V13 deployment checker names the permanent-liveness hazard. Today neither does (V11.2) | construction invariant |
| S-11 | `registry_spend.ak` | update-path auth reads `transfer_logic_script` instead of `minting_logic_script` | already CAUGHT (seed 2) from both sides after the 2026-08-06 fix; carry it into the Lean tier when `registry_spend` gets a flat | authorisation |
| S-12 | `extract-flats.sh` | remove one title from `TITLES` / add one to the blueprint | `--check` must go RED (EXP-0c) | completeness |
| ★S-13 | `issuance_mint.ak` | `plgl_scope_covers`'s `UnfrackingAct -> False` → `True` | a mint delegated to an `UnfrackingAct` PLG run must be rejected. `UnfrackingAct` requires `mint` to be zero, so the mutant is only reachable *through* the composition — precisely the three-hop argument (V3) that no single-validator test covers | delegation escape |
| ★S-14 | `transfer.ak` | `[] == verify_proofs(…)` → `_ = verify_proofs(…)` (drop the exhaustion equality) | hop 3 of the same argument: a spare `TokenExists` proof for a policy with no PLB input must not survive. If nothing reddens, the delegation soundness rests on a check nothing tests | delegation escape |
| ★S-15 | `issuance_mint.ak` | `plgl_delegates_for_own_registry_node` → "any PLG redeemer exists" (the pre-tightening shape) | a mint for node A routed to a non-PLB output while PLG names node B must be rejected. This is the *regression* control for the fix that `transfer.ak`'s stale comment still describes as pending | delegation escape |
| ★S-16 | `transfer.ak` | `collect_input_assets` calls `authorised_stake_cred` on the **first** PLB input only, still accumulating the rest | the two-owner / one-authorisation context (V4). All four single-input twins pass this mutant — that is the point. Run in both vkey-signature and script-withdrawal flavours | authorisation, double satisfaction |
| ★S-17 | `registry_mint.ak` | `expect [covering_input] = list.filter(…)` → take the first match | an insert that also consumes a second authentic registry node must be rejected. Both `registry_spend` executions see the same global mint, so this is one witness satisfying N executions (V7) | registry double satisfaction |
| S-18 | `third_party.ak` / `programmable_logic/unfracking.ak` | `n - 1` → `n - 2` in a `drop_accum_*` helper; separately, omit one `list.tail(outputs)` in the pair walk | boundary fixtures at `outputs_start_idx` ∈ {0, 1, len, len+1} must expose the double-counted or skipped output (V19) | value accounting |
| S-19 | `lib/registry_node.ak` | change one accessor's `tail_list` depth to the adjacent field | the V6b accept/reject pair must flip, with **exactly** the expected credential present so an adjacent read has nothing to match | Data-layout |
| ★S-20a | `PropsBase.lean` (scratch copy) | replace a **pinned** theorem's proof with `sorry` | the `#guard_msgs` axiom pin must turn `lake build` RED. Today, under file-wide `warn.sorry false`, it would not (V20) | claim integrity |
| ★S-20b | `PropsBase.lean` (scratch copy) | add a **new, unpinned** theorem containing `sorry` | the *inventory* leg must catch it. S-20a alone does not — a pin covers only what it names | claim-integrity inventory |
| S-21 | `programmable_logic_base.ak` | add an exactly-one-input guard | kills V1(b)'s two-input accepting witness. **Bites only against a relational or witness-based statement** — an implication-shaped rung survives it vacuously (R2b) | independence control |
| S-22 | `programmable_logic_base.ak` | make the ignored redeemer require unit | must break `accepts(ctx,r₁) ↔ accepts(ctx,r₂)`, or kill a per-shape witness. Against *"∀ rdmr, accepts → forwarding"* it **passes on the bug it exists to catch** — narrowing an antecedent cannot falsify an implication (R2b) | independence control |
| S-23 | `programmable_logic/unfracking.ak` | add an equality on the deliberately-free lovelace field | must break the relational invariance statement. This re-seeds the #96 hazard class, which *was* an accidental narrowing of acceptance — so an implication-shaped V9 could not see the very bug it commemorates (R2b) | independence control |
| S-24 | any tracked validator | add a bogus `validity_range` upper-bound gate | must break `accepts(ctx,range₁) ↔ accepts(ctx,range₂)` (R2b) | independence control |
| S-25 | `programmable_logic/params.ak` or `registry_node.ak` | change one `expect InlineDatum` to accept a hash datum | V12's hash-datum run must flip | over-acceptance |
| S-26 | per **successful** width rung | add that exact width's statement to the existing always-accept mutant | must come back Falsified, with a last-slot accepting witness at fuel raised for the width. Applies once a rung returns Valid — a rung that times out is a measurement and needs no seed (V8) | ladder integrity |

### The check → control mapping R4 promises

One row per proposed check. `NONE — caveat named` is a legitimate entry; an *implied* control
is not.

| Check | Control | Status |
|---|---|---|
| V1(a) forwarding ladder, widths 1/2/4 | existing mutant + **S-1** | rung 1 covered; rungs 2/4 by analogy only — add the 4-entry statement to `MutantControl.lean`'s `solve-result: 1` list (C10) |
| V1(b) input-count independence | **S-21** | valid **only** for a relational or witness-based statement (R2b) |
| V1(c) rung 2 (PLG → unfracking presence) | relax PLG's `UnfrackingAct` gate | must red the rung-2 theorem |
| V1(c) rung 3 (unfracking accounting) | stop the input walk after the first PLB input | a two-input family must red |
| V2 TransferAct conservation | existing Aiken-tier kill (`transfer.ak` containment → `True`, 2 tests red) | **carry to Lean tier when V2 exists** |
| V2 ThirdPartyAct conservation | **S-4**, **S-5**, plus the existing ratchet kill (`>=`→`>`, 18 tests red) | covered |
| V2 unfracking conservation | **S-6** | covered at Aiken tier |
| V3 registry NFT shape | **S-8** | covered |
| V3 issuance × PLG delegation | **S-13**, **S-14**, **S-15** | covered — three hops, three seeds |
| V4 single-input authorisation | signature/withdrawal removal twins | covered |
| V4 multi-input authorisation | **S-16** | covered |
| V5 purpose dispatch | **S-2** + R1 localisation leg | covered |
| V5b credential tag | **S-3** | covered |
| V6 redeemer independence | **S-22** | valid **only** for a relational or per-shape-witness statement (R2b) |
| V6b Data layout | **S-19** | covered |
| V7 ordering / uniqueness | **S-9** | covered |
| V7 covering-input double satisfaction | **S-17** | covered |
| V8 width ladder — **rung times out** | **NONE — by form** | the negative result *is* the measurement; nothing to seed |
| V8 width ladder — **rung returns Valid** | **S-26** | a successful rung is a positive safety check and owes a kill, plus a last-slot witness at raised fuel (R6) |
| V9 lovelace invariance / ratchet | ratchet: existing `>=`→`>` kill · invariance: **S-23** | ratchet is monotone and fine as an implication; invariance needs the relational form (R2b) |
| V10 validity-range independence | **S-24** | valid **only** for the relational form (R2b) |
| V11 decoy reference inputs | **S-10′** | covered for the params construction edge (and see the polarity split in §5) |
| V12 inline/hash handling | **S-25**: change one `expect InlineDatum` to accept a hash datum | the hash-datum run must flip |
| V13 deployment closure | perturb one byte of one parameter; checker must name that edge | covered |
| V16 inventory completeness | **S-12** | covered |
| V19 positional indices | **S-18** | covered |
| V20 axiom pin, pinned theorem | **S-20a** | covered |
| V20 axiom pin, inventory completeness | **S-20b** | covered — see below |

**One row keeps `NONE`, by form**: V8's width ladder. A rung that fails to discharge is a
measurement of Blaster's reach, not a check that could be seeded. Every other row now names a
seed. The first draft claimed this mapping was complete when six rows had none, and the four
I had written off as unseeable turned out to have the most natural controls of all — see R4.

**27 active seeds**: S-1…S-9, S-10′, S-11…S-19, S-20a, S-20b, S-21…S-26. S-10 is withdrawn.
Six of them (S-10′, S-13, S-14, S-15, S-17, S-26) span two artifacts or a deployment gate and
therefore do **not** run through `falsification-control.sh` as it stands — see §10.

**A mutant that does not compile is not a killed seed.** Make "the mutant built, and the
extracted flat differs from the clean one" an explicit precondition of counting any kill —
`falsification-control.sh`'s leg 3 already asserts the artifact changed, so this is one
`|| exit` away. Without it, a patch that fails to build reads as "the pipeline caught it",
which is the same false-green shape as reading exit codes instead of logs. S-1 was originally
written in a form that would have hit exactly this (a `list.head` call in a module that does
not import `list`).

**On independence.** Seeds S-1, S-3, S-5, S-7 and S-10′ were proposed by someone who did not
write the checks, and S-15 through S-20b by a second reviewer who wrote neither the checks nor
this plan — which is the standing ask in methodology §5, satisfied twice over. They should go
into `cip113-mutation-seeds` **sealed**, and the pipeline should be required to name *which*
check caught each one, not merely that something went red. A seed caught by the wrong check is
a finding about the checks.

---

## 9. Out of scope for on-chain proof — and what covers it instead

| Class | Why no theorem can settle it | The mechanism that can |
|---|---|---|
| V13 deployment closure | Scripts cannot learn their own hash; ∀-over-parameter is deliberately blind to *which* parameter | Mechanical deployment-manifest checker (T4) |
| V14 hook aliasing | The defect lives in a substandard that does not exist yet | Normative text + conformance fixture in the substandard kit |
| V15 freeze collateral | A governance asymmetry, not a code path | Disclosure + wallet-behaviour guidance |
| V9 min-UTxO floors | Protocol parameters are not in the script context | `ledger_shape` fixtures + the param-sensitivity analysis; the byte-tier contribution is the *insensitivity* theorem |
| Empty-hash default-deny | Rests on a ledger deserialisation rule the script never checks and the Lean model does not encode | State it as a named ledger assumption (R3); a `cardano-ledger` citation, not a proof |
| PLG deregistration | A Conway certificate rule, not a script property — though the script's `publish` handler is the half that *is* checkable | Certifying-purpose concrete run + a ledger-rules citation |
| Ledger reachability of counterexamples | Z3 explores the Lean type, not the ledger | R3, applied by hand to every REFUTED |

---

## 10. Cost summary and build budget

**Units.** 1 BU = one `lake build` of the FV package (incremental; the cold CI figure on
record is 4m25s for 306 jobs). 1 AB = one `aiken build` (seconds). 1 FC = one
`falsification-control.sh` run ≈ 2 AB + 2 BU in a temp worktree.

| Bucket | Items | Estimated cost |
|---|---|---|
| **No build at all** | EXP-0c/V16, V13 checker, V14 text, V15 disclosure, R3 paragraph | 0 BU — and this bucket holds the two highest-severity rows |
| **T0/T1 batch** | V5 (PLB `else` arm), V5b (vkey twin), V10 (symbolic range), C1 (2-input witness), C10 (rung-2/4 witnesses) | 1 BU if batched into one edit of `PropsBase.lean`; several are 5-line additions |
| **EXP-0 + EXP-0b** | PLG/unfracking prep feasibility, builtin dispatch | 1 BU, timeboxed. **Do before costing anything below** |
| **T2 tier** | V1(c), V2, V4, V6, V6b, V9, V11, V12, V7 — all requiring the rewarding-context builder | 1 BU for the builder, then ~1 BU per batch of runs. Unknowable until EXP-0 |
| **T3 tier** | width ladder 5/8/16, conservation quantifiers, mixed-credential rung | 1 BU per rung. Budget in rungs, and **declare the stop in advance** — a rung with no verdict is COULD-NOT-EVALUATE, recorded, and the ladder ends there |
| **Controls, single-artifact** | 21 of the 27 active seeds | 1 FC each; independent, so they parallelise |
| **Controls, multi-artifact** | S-13, S-14, S-15 (issuance_mint × PLG), S-17 (registry_mint × registry_spend), S-26 (per successful rung), S-10′ (deployment-side) | **not** a plain `falsification-control.sh` run — each needs two artifacts rebuilt and executed against one shared context, or a deployment-gate harness. Price the sealed-seed runner separately; do not assume the existing five-leg script covers them |

**Two budget cautions.**

1. `#prep_uplc appliedBase … 600` was tuned for 141 bytes with K≈194 measured on a comparable
   validator. Nothing in that number extrapolates to 2 996 bytes. Treat any PLG budget as an
   unbounded search until EXP-0 returns, and timebox it explicitly rather than letting a
   `maxHeartbeats 0` build run overnight.
2. `set_option maxHeartbeats 0` plus `blaster (timeout: 1800)` means a non-converging rung
   consumes wall-clock without a natural stop. For the T3 ladder, set the Blaster timeout to
   the budget you are willing to spend *per rung* and record the timeout value alongside the
   COULD-NOT-EVALUATE — the number is the result.

**Not priced here:** everything above is a build-count estimate from reading the sources. No
build was run for this document, so wall-clock and disk figures are COULD-NOT-EVALUATE.

---

## 11. Register of what this plan could not evaluate

Recorded rather than guessed, per the discipline this repo already applies to itself.

1. **Whether `#prep_uplc` reaches PLG or `unfracking` at any budget** (EXP-0). Half of §5's
   method column depends on it.
2. **Whether the pinned CEK model dispatches `blake2b_224`** and the bytestring comparison
   builtins (EXP-0b). Determines whether `registry_mint` is reachable at all.
3. **Whether `CardanoLedgerApiBlaster` supplies a rewarding-purpose input builder**, or
   whether it must be written. The one new mechanism in §7.
4. **Whether any proposed SMT rung discharges.** Source reading cannot predict Z3 —
   emphatically so for V2's conservation quantifiers over list-shaped state.
5. **Whether `extract-flats.sh --check` is green at `02c7b86`** and whether the five-leg
   control currently passes. Both were read, neither run.
6. **Whether traces are compiled into the shipped artifacts** (`trace @"Starting …"` appears
   in all five validators). Affects whether a log-based rejection-reason discriminator is
   available for R1, or whether the twin-context argument is the only route.
7. ~~`protocol_params_mint`'s and `issuance_mint`'s actual contents.~~ **Resolved — both read
   at the same commit, and the plan was corrected in three places.** For the record, because
   the corrections cut both ways: (a) `transfer.ak`'s comment about `issuance_mint`'s
   `or { plg_invoked, … }` delegation is **stale** — the tightened form is already in the code,
   so what I first wrote up as an open custody gap is not one (V3); (b) the params NFT is
   one-shot **and** locked at an always-fail address, which closes both reference-input edges
   I had opened (V11.1, V11.2) and simultaneously makes V13 worse, because the trust root is
   write-once; (c) `issuance_mint` reads `tx.redeemers`, promoting the Conway redeemer-map
   shape from "documented for completeness" to a load-bearing fixture input.
   What replaced this item: the `issuance_mint` × PLG delegation is a **three-hop
   cross-validator argument** that neither validator's tests or theorems can state (V3(iii),
   seeds S-13/S-14).
8. **Whether the build environment axis matters in practice.** `env/default.ak` makes
   `assert_no_ada_policy` the identity function; `env/with_assertions.ak` makes it a real
   check. CI runs a plain `aiken build`, and the byte-for-byte blueprint reproduction leg
   pins the env implicitly — so this is *covered*, but a reader cannot see it. Now folded
   into **R6** as identity coordinate 4, alongside prep fuel as coordinate 5.
9. **The actual step-count `K` for the rejecting run and the 4-entry rung.** This is what
   says how much headroom the fuel-600 bound has, and therefore how far the ladder can climb
   before an accepting run silently exceeds it and turns a rung vacuous (R6). Needs execution
   or a step-budget probe.
10. **Whether `.prop` and `.exec` agree on this artifact.** R5 names the trust link; nothing
    read here can measure it. The prop-side concrete controls in V20 are the cheap partial
    answer, not a proof.
11. **Whether Aiken v1.1.22's V3 wrapper returns `Const.Unit` on success.** `isSuccessful`
    accepts *any* halt value while CIP-117 requires PlutusV3 success to be unit. For the
    implication direction proven this is sound (any-halt ⊇ unit-halt), leaving one thin
    residue on `exec_accepts`: the model says "halts", the chain additionally needs "with
    unit". One `native_decide` on the halt value settles it.
12. **Whether every ThirdPartyAct recovery branch rejects a no-stake-credential PLB output.**
    Decides whether V4's seizure-destination finding is "holder-unspendable, admin-recovery
    only" or something stronger. A fixture question, not a source-reading one.

---

## 12. Reconciliation with `invariants-findings.md`

Half 1 and this document were produced independently and agree where they overlap; the
mapping, so the two can be read as one:

| Half-1 candidate | This document |
|---|---|
| C1 multi-input forwarding | V1(b) — same check, framed as the double-satisfaction seam |
| C2 entry uniqueness (COVERED) | Consistent; V8 adds that width is also economically attacker-influenced in multi-party transactions |
| C3 amount symbolic (COVERED) | Consistent; V9 extends the same reasoning to lovelace |
| C4 quantifier scope / ledger-unreachable fixtures | R3, both directions, plus the recommendation to state it in methodology §7 |
| C5 all safety is in PLG, no theorem | The whole PLG column; V1(c) picks the UnfrackingAct arm as the cheapest entry, agreeing with C5's read |
| C6 redeemer independence | V6 |
| C7 rejection = ¬Halt (COVERED for PLB) | R1 — generalised, because the twin-context argument does **not** carry to the bigger validators |
| C8 width, 4 is a convention | V8, plus the multi-party ex-unit angle |
| C9 mixed-credential maps | V5b — same check; this document adds the deployment consequence (a vkey `stake_cred` parameter disables PLG entirely, V13) |
| C10 rungs 2 and 4 lack witnesses/controls | R2 and §8's mapping table |
| C11 non-spend invocations | V5 — same check, and this document's cheapest row |
| C12 `warn.sorry false`, no axiom gate | V20(1) — adopted wholesale, including the `#guard_msgs` closer and seed S-20 |
| C13 `.prop` vs `.exec` optimizer trust | **R5**, promoted to a standing rule because it qualifies every S-row paired with a K-control in this plan |
| C14 fuel as a claim coordinate | **R6**, merged with this document's build-env axis into one five-coordinate identity |

New here, not in Half 1: V13 (deployment closure, write-once trust root), V14 (hook
aliasing), V15 (freeze collateral), V16 (inventory completeness), V11 (`peek_first` /
first-match reference-input selection — two edges opened and closed, one still resting on
`registry_spend`), V3's issuance_mint × PLG composition and the stale `transfer.ak` comment,
V4's two authorisation asymmetries, V6b (Data-layout at the byte tier), and the
S-1/S-3/S-5/S-7/S-10/S-13/S-14 seeds.

---

## 13. What changed under review, and what was contested

This plan was drafted, then attacked by an independent reviewer who had not written it, then
revised. Recording the deltas rather than quietly folding them in, because which claims moved
is itself information — and because two of them moved *against* me.

**Withdrawn or corrected:**

- **The `issuance_mint` "open custody gap" is withdrawn.** `transfer.ak`'s comment describes a
  delegation shape the code no longer has; reading the file at this commit shows the tightened
  form already in place. What replaced it (the three-hop composition argument, V3) is a better
  finding, but the first version was a live-bug claim resting on a stale comment.
- **Seed S-10 is withdrawn.** Replacing `peek_first` with a full policy scan would have been
  killed by a decoy context that R3 says is unreachable — my own rule, applied to my own seed,
  by someone else. Replaced by S-10′.
- **"Permanently unspendable" softened to "holder-unspendable, admin-recovery only"** (V4).
- **"∀ over the deployment parameter" corrected to "∀ over script-credential hashes"** (V13) —
  which strengthens rather than weakens the finding, since a vkey parameterisation turns out
  to be *outside* the family rather than covered by it.
- **V1(c) relabelled**: the cheap PLG theorem is rung 2 of three, not "the second link
  closed". Rungs 1 and 2 are forwarding; only rung 3 checks anything.
- **R4's completeness claim was false as written** — six checks had no seed. Now an explicit
  mapping with `NONE — caveat named` where it belongs.

**Contested and settled by evidence:**

- The objection that Aiken emits a separate artifact per handler — so a `.spend` flat could
  not establish anything about `.else`, and `.withdraw` flats could not reach `.publish`. The
  blueprint says otherwise: every handler of a validator carries byte-identical
  `compiledCode` (table in V5). The purpose checks stand, and PLG's `publish` is cheaper than
  scoped. The objection's *control* was adopted anyway as R1's localisation leg — proving the
  arm you claim about is in the bytes under test is right regardless of why you doubted it.

**Added because of the review:** V19 (positional indices), V20 (claim-integrity gates), R5
(`.prop` ≠ `.exec`), R6 (five identity coordinates), R1's localisation leg, the two-owner
authorisation control (S-16), the registry covering-input double satisfaction (S-17), the
params-construction invariant (V11.2, S-10′), and seeds S-15 through S-20b.

**Second round — four more corrections, three of them to my own criteria:**

- **A pass/fail polarity was inverted.** V11 grouped three decoy runs under one criterion, but
  for the lower-sorting co-asset params UTxO a PLG rejection *is* the permanent brick, not
  evidence against it. Safety there is established by the construction gate, and a gate that
  accepts what PLG rejects means **REFUTED**, not ESTABLISHED. Now split explicitly.
- **Four `NONE — caveat named` entries were wrong**, and the reasoning behind them was
  backwards: *"nothing reads this field"* is the claim under test, so the control is to make
  something read it. Now S-21…S-25.

**Third pass — two vacuity holes in the controls I had just added:**

- **R2b, and it invalidated four of my own controls.** An independence claim stated as
  *"∀ x, accepts → forwarding"* cannot be falsified by narrowing acceptance: a mutant that
  accepts only the unit redeemer makes every other case vacuous and the theorem stays Valid.
  S-21…S-24 all passed on the bugs they existed to catch. Independence must be **relational**
  (`accepts(ctx,x₁) ↔ accepts(ctx,x₂)`) or **witness-based** (one inhabitant per discriminating
  value). Sharpest instance: an implication-shaped V9 could not detect the #96 hazard class,
  which was itself an accidental narrowing of acceptance.
- **V8's `NONE` was right for one outcome and wrong for the other.** A rung that times out is a
  measurement of Blaster's reach and needs no seed; a rung that returns **Valid** is a positive
  safety check and owes a kill (S-26). Without the split, a widening ladder accumulates green
  ∀-theorems never shown able to fail — the decoration failure mode arriving through the door
  marked *tool benchmarking*.
- Plus two mechanical corrections: 27 active seeds, not 21; and six of them span two artifacts
  or a deployment gate, so the claim that one `falsification-control.sh` run covers every seed
  was too broad. The sealed-seed runner for those is now named and costed separately.
- **The V20 axiom gate was incomplete as specified** — `#guard_msgs` pins only what it names,
  so an unpinned new theorem with `sorry` still compiles. Split into S-20a (pinned claim) and
  S-20b (inventory), which is EXP-0c's pattern one level up.
- **V19's property was stated as a ∀ and discharged with four fixtures.** Relabelled
  KERNEL-PROVED-at-boundaries; ESTABLISHED reserved for the S theorem.
- Also: V3's composition reclassified from `X` to **COULD-NOT-EVALUATE today** (it is
  buildable, just blocked); V14's "the hook has no redeemer" corrected to the real gap (the
  core never *binds* the hook's redeemer to the nodes naming it); S-1 given a compile-valid
  form, plus a standing rule that a mutant which fails to build is not a killed seed.

---

*Read-only review at commit `02c7b86397f7660c8f479b20cc544a099269a7d5`. No build was run and
no code was written; every check above is scoped work, not completed work. Adopt or dismiss
each row independently.*
