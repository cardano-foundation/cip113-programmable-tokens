# Formal verification & test-hardening — status, blockers, next steps

Working file (local, like `CONTRACT_SURFACE_CHANGES.md`). Branch:
`feat/formal-verification` (supersedes `test/blaster-tier0-properties`).
Last update: 2026-08-11.

**Front door for evaluators:**
`documentation/design/formal-verification-methodology.md` — criteria,
claims vocabulary, identity + falsification discipline, trust base,
reproduction steps. This file is the running log behind it.

## 2026-08-12 — Paolo's PR-101 review: triage + adoption

**Reviews + triage.** Paolo Veronelli reviewed PR #101 at `02c7b86`
(one commit before `ce515dc`, so *without* `PropsGlobal.lean`). His three
review files and our item-by-item triage live under
`formal-verification/reviews/2026-08-12-paolino-pr101/`
(`1-invariants-findings.md`, `2-audit-coverage-plan.md`,
`3-adversarial-critique.md`, `TRIAGE.md`). Every triage item was checked
against actual source before acceptance. The batch plan (Part D of the
triage) is the running TODO at the bottom of this section.

**Standing rules adopted.** R1–R6 (Part C of the triage) are now binding
across every tier; see §3a of the methodology doc for the full text.

**Claims reframing (from C5).** His central premise "the PLG has no
theorem tier" is now stale for the TransferAct branch: `ce515dc`
discharges `t1_escape` (output payment credential forced = PLB — the
anti-escape/containment theorem) and `t1_conservation` (qOut ≥ qIn) as
SMT-VALID over the compiled 2996 B PLG. Per his ask, the PLG's *enforcing*
coverage is now stated per branch:

| PLG branch | proof-tier status |
|---|---|
| TransferAct | **SMT-VALID** (T1 family: `t1_escape` + `t1_conservation`) |
| ThirdPartyAct | enforcing check at proof tier: **NONE** (TESTED only) |
| UnfrackingAct | **NONE** (TESTED only) |
| registry validators (registry_mint / registry_spend) | **NONE** at proof tier |

TESTED here is the Layer-1 property suite + goldens; NONE means no
theorem-tier (KERNEL-PROVED or SMT-VALID) result yet exists for that
branch.

**Disclosure obligations for the docs rewrite.** These MUST feed the
planned protocol-documentation rewrite (see CLAUDE.md "Upcoming: CIP-113
documentation rewrite"). Each is a documentation finding surfaced by the
review, not a code bug:

- **V4 — seizure & mutability.** Seizure destinations are
  *holder-unspendable, admin-recovery-only* — NOT permanently
  unspendable. And programmable tokens are *issuer-mutable*: a seizing
  hook can be installed **post-issuance**. Both facts must be stated
  plainly; "permanently locked" language is wrong.
- **V6 — datum / ref-script continuity.** Enforced in ThirdPartyAct and
  unfracking, but **NOT** in TransferAct. This is an interface obligation
  on substandards (they must preserve datum/ref-script on the transfer
  path themselves), and must be documented as such.
- **V8 — DoS surface.** `new_withdrawal_checker` is
  O(policies × withdrawals) — a multi-party DoS surface; and `maxValueSize`
  bounds fracked UTxOs (bench pin exists). Disclose both.
- **V14 — substandard-hook aliasing.** Two registry nodes can name the
  same hook; one withdrawal entry satisfies both; the core never binds a
  hook's redeemer to the node-set that named it. Needs normative guidance
  (a tx touching aliased nodes A+B must reject unless the hook proves B).
- **V15 — unfracking rescue is default-forbidden** (`empty_vkey`), so the
  hostile-freeze mitigation is **opt-in by the issuer**. Carries a
  wallet-UX obligation: **no cross-policy auto-consolidation** (or
  unfracking gains are silently undone).
- **V18 / R3 — reachability polarity.** Over-approximated ∀-safety is
  strictly stronger and free; a REFUTED counterexample needs a
  ledger-reachability check before it is a finding.

**C2 uniqueness — accepted as COVERED, no theorem.** The PLG entry is
unique by construction: `has_key_or_fail` returns at the first hit,
ledger map keying makes duplicate credentials unreachable, and the
composition is restrictive-only. One methodology sentence; no theorem
owed.

**Batch plan (Part D) — running TODO:**

- [~] **Batch 1a — docs (this session, in progress):** adopt R1–R6;
  C5 claims reframing; trust-base additions (optimizer / `blasterProven`
  / fuel-as-coordinate); disclosures V4/V6/V8/V14/V15/V18; stale
  `transfer.ak` comment (V3). *(scripts/README owned by a separate agent;
  .lean edits by a later agent.)*
- [~] **Batch 1b — harness (in progress, separate agent):**
  EXP-0c/V16 `DELIBERATELY_UNVERIFIED` extraction gate (his #2);
  V13 deployment-manifest checker + vkey-param demonstration (his #1);
  V20 axiom gates + trust-base/MANIFEST coordinates (his #5).
- [ ] **Batch 2 — cheap PLB Lean additions, one build:** C11 else-arm
  reject; C9 vkey-tag twin; C10 slot-2/4 witnesses + MutantControl 4-entry;
  C1 2-input witness; C6 redeemer witnesses (R2b form); V10 relational
  range rung; C14(iii) unit-halt upgrade; `exec_rejects_no_transfer_logic`
  control + `t1_conservation` non-vacuity probe.
- [ ] **Batch 3 — proof work (PLG prep template now exists):** V4
  two-owner auth (elevated); V7 covering-input double-sat (elevated);
  V1(c) UnfrackingAct forwarding rung; V7 ordering; V2 per-branch
  conservation; V19 boundaries; V9 ∀-lovelace; V11/V12 decoy+datum runs;
  V6b layout.
- [ ] **Batch 4 — DEFER:** V8/C8 width ladder; EXP-0b builtin probe;
  C4 ledger-shaped witness rung; V3 issuance×PLG composition.

**REJECTs.** V17 (integer domain) — N/A by form (arbitrary-precision;
keep S-7 as an Aiken-tier seed). S-10 — withdrawn by Paolo himself
(peek_first→full-scan is a liveness improvement; the decoy it targeted is
R3-unreachable).

## Phil's wsc-containment-proofs — inventory + migration matrix (2026-08-11)

Source: Anastasia-Labs/CardanoLedgerApiBlaster branch
`wsc-containment-proofs` (fetched into
`~/Development/workspace/CardanoLedgerApiBlaster`, remote `anastasia`;
worktree at /tmp/wsc-proofs during inventory). Full agent inventory
distilled here so it never needs re-deriving.

**His scorecard**: P1–P6 all PROVED VALID over 14 node-realizable
shapes; composed containment proved as a REDUCTION to 4 leaves (1 of 4
bytecode, 3 shape restriction) under 28 project axioms; top claim
("tokens cannot exist outside the mini-ledger") NOT proved in full
generality; coverage of the shape family provably FALSE (3 witnesses
outside all 16 shapes; enumeration priced at 3×10^14 skeletons — do not
attempt coverage).

**Load-bearing walls + workarounds (port these, in order):**
1. `#prep_uplc` memory cliff: UNSHAPED prep of the global validator
   dies at 20–35 GB for budgets ≥2300. SHAPED prep (family leaves as
   prep-function arguments = statement-level skeleton) at 4400 runs in
   ~1.5 s. RULE: never prep unshaped; cut the narrowest skeleton first,
   widen one dimension at a time, re-measure. (Bit us immediately: our
   first PrepGlobal draft was unshaped — killed, restructured.)
2. eqData translation failure (Lean-blaster#138): `eqData` on
   constructor-headed args breaks the SMT translator UNSHAPED; shaped
   skeletons reduce it to equalsByteString/equalsInteger — another
   reason shapes work.
3. Single-dimension cuts can be enough (his SHAPE B1W: freezing ONLY
   the withdrawal-map length closed P3 in 5 s) — try minimal cuts
   before full skeletons.
4. Two-sided K pinning: measure witness K where CEK halts at K and
   errors at K−1, against the real bytecode — binds the budget axiom.
5. Four-point bar per shape: (a) theorem Valid, (b) vacuity probe
   (¬POST expect-Falsified at the SAME prep), (c) concrete witness with
   two-sided K, (d) realizability (validXContext + redeemer coverage;
   note CLAB's validScriptContext OMITS Conway MissingRedeemers — he
   added `redeemerCovered`; port it).

**Migration matrix (his → ours):**
| his | invariant | ours | status |
|---|---|---|---|
| P3 base escape | spend at base forces global/seize wdrl | `base_forces_plg_withdrawal_{1,2,4}` | DONE (stronger: ∀-param, no redeemer-index residual) |
| P1 transfer containment | outAtBase ≥ inAtBase + mint | T1-escape + T1-conservation (`PropsGlobal.lean`) | **DONE 2026-08-11** (see below) |
| P2 seize (2a structure / 2b containment) | pairwise addr/datum/refScript preserved; ada ratchet; seized policy contained | ThirdPartyAct analog — pairs with our Finding-13 pairing + #96 lovelace ratchet | TODO (Stage 2) |
| P4 minting custody (4 arms) | registered policy mints can't land off-base | issuance_mint / R-04 analog | TODO |
| P5 non-member registration | covering-node proof authenticates | registry_mint insert (TokenDoesNotExist arm) | TODO |
| P6 member registration | mint added at base, no base input consumed | registry_mint + issuance path | TODO |
| composition | reduction to leaves + realizable classes | Stage 3 | TODO (after ≥2 leaf validators proven) |
| goldens + K-MEASUREMENTS | 13 hand-audited vectors vs real CEK | port pattern over our fixture txs | TODO |
| Coverage.lean negative result | shape family provably incomplete | replicate the honesty artifact once ≥2 families exist | TODO |

**Trust-base difference to preserve**: Phil needs 3 UNPUBLISHED branches
(his repro is machine-local); we are stock-upstream pinned + public — keep
it that way; do NOT adopt his substrate bundle.

## Done

- **2026-08-11 — STAGE-1 CONTAINMENT THEOREMS ON THE COMPILED PLG**
  (`formal-verification/Cip113Spike/{PrepGlobal,PropsGlobal}.lean`,
  family T1: TransferAct, 1 registered policy, 1 PLB input, 1 output,
  2 ref inputs [params + registry node], shaped prep at 4400 —
  2.3 s build):
  - `t1_escape` SMT-VALID: ∀ symbolic output payment credential C,
    ∀ symbolic qIn qOut — acceptance of the compiled PLG forces
    C = the PLB credential. THE "tokens cannot escape the jail"
    theorem, TransferAct path, on deployed bytes.
  - `t1_conservation` SMT-VALID: with C = PLB, acceptance forces
    qOut ≥ qIn (the compiled `tokens.contains` guarantee).
  - Vacuity probe (wsc four-point bar, point b): negation of t1_escape
    ✅ Expected Falsified at the same prep — family non-vacuous.
  - Kernel-checked execs: honest transfer accepted; escape to foreign
    credential rejected; quantity shortfall rejected.
  - Method notes: prep MUST be shaped (first attempt was unshaped =
    Phil's 20–35 GB cliff; killed at 0.8 GB, restructured so the T1
    leaves are the prep function's arguments). CLAB gotchas:
    `IsData.toData` lives at `CardanoLedgerApi.IsData.Class.IsData`;
    stake cred is `.StakingHash (.PubKeyCredential k)` (Data-identical
    to Aiken's `Some(Inline(..))`); big contexts need
    `set_option maxRecDepth 65536`.
  - NOT yet: two-sided K pinning, realizability audit (bar points c/d);
    ∀-deployment param quantification; multi-output/multi-policy rungs;
    ThirdPartyAct + UnfrackingAct branches. Tracked in the migration
    matrix above.

- **2026-08-11 — MONOREPO CONSOLIDATION** (Paolo's recommendation,
  seconded): the Lean spike repo was folded into this repo at
  `formal-verification/` on new branch `feat/formal-verification`
  (forked from `test/blaster-tier0-properties` + `origin/main` merged
  in — zero content delta, the FV branch already contained #98's
  content). Consequences:
  - **The source-commit axis of the identity triple is now implicit** —
    sources, blueprint, flats, and theorems share one commit. The
    MANIFEST no longer records a cross-repo commit, and the re-attest
    dance ("MANIFEST goes stale on every cip113 commit") is gone.
  - **One CI workflow replaces two**:
    `.github/workflows/formal-verification.yml` (replaces the spike's
    `verify.yml` + this repo's `fv-freshness.yml`) enforces per push:
    aiken == blueprint preamble → clean rebuild reproduces committed
    `plutus.json` byte-for-byte → `extract-flats.sh --check` →
    `lake build` re-discharges every theorem. A validator change that
    forgets re-attestation turns the SAME PR red.
  - `extract-flats.sh` / `falsification-control.sh` now derive the repo
    root from their own location (no `CIP113_REPO`, no sibling
    checkout); Lean sources unchanged (flat paths are
    package-root-relative).
  - `easy1staking-com/cip113-lean-spike` archived with a pointer README
    (history preserved there). `cip113-mutation-seeds` stays separate
    deliberately — second-author independence is its point.

- **2026-08-06 — identity + falsification discipline** (triggered by
  paolino's `aiken-blaster-verification` skill,
  https://gist.github.com/paolino/3d9b79baffc075606bdd1ba4f9002f81):
  - **Methodology doc** written (path above) — the single unified
    description of all four layers; external-evaluator oriented.
  - **Claims vocabulary adopted**: `blaster` theorems are **SMT-VALID
    (no proof term)** (Z3 `unsat` + named axiom `blasterProven`), the
    `native_decide` executions are **KERNEL-PROVED**; run outcomes are
    ESTABLISHED / REFUTED / COULD-NOT-EVALUATE with everything unclean
    RED. All prior "✅ Valid" wording in this file should be read as
    SMT-VALID (no proof term).
  - **Identity triple mechanised**: `extract-flats.sh` now also emits
    `flats/MANIFEST.md` (source commit + dirty flag, compiler from the
    blueprint's own preamble, blueprint/flat sha256s,
    `BuiltinSemanticsVariant = E` with evidence pointers); `--check`
    verifies flats AND manifest, and was itself falsified (corrupted
    flat + tampered manifest both turn it red).
  - **Real toolchain drift caught by the mechanical check**: blueprint
    built by Aiken v1.1.22+39d6b04, installed CLI was v1.1.21+42babe5
    (and this file previously said "v1.1.22" on trust). Fixed:
    `aikup install v1.1.22` — now byte-matching the preamble.
  - **CBOR wrapping settled empirically**: Aiken blueprint
    `compiledCode` is SINGLE CBOR-wrapped flat (inner bytes `010100…` =
    flat version header). Paolo's skill says `double_cbor_hex` — true
    for the on-chain tx-witness encoding, not for blueprints; worth a
    correction note to him.
  - **Full-pipeline falsification control**
    (`scripts/falsification-control.sh`, 5 legs, ALL GREEN 2026-08-06):
    toolchain identity → flats freshness → **clean rebuild reproduces
    committed `compiledCode` byte-for-byte** (source→blueprint
    correspondence now established, not assumed) → mutant (withdrawal
    check gutted → `True`, rebuilt through real `aiken build`, 94 vs
    141 B) → `controls/MutantControl.lean`: the clean-Valid forwarding
    theorem comes back **Falsified with a counterexample** (accepted
    foreign hash `"!0!"` ≠ param) and the mutant ACCEPTS the context
    the clean artifact rejects (kernel-checked) → baseline restored +
    re-verified. The Lean gate has now been shown able to fail.
  - Spike repo hygiene: `.lake/` untracked, `README.md` added (claims
    table with labels, layout, prerequisites, run + lineage).
  - **STANDING ASK (Giovanni / any reviewer)**: seed 2–3 undisclosed
    single-line validator mutations and require the pipeline to catch
    them — independent negative controls, per "don't let one person's
    imagination be the whole test".
    - **DONE 2026-08-06 (first round, seeded by Codex — a different
      model from the suite's author)**, tooling at
      `~/Development/workspace/cip113-mutation-seeds/`
      (`seed-mutations.sh` generates sealed patches, `run-seeds.sh`
      judges CAUGHT/ESCAPED/INVALID). Result: **3/3 CAUGHT**, and the
      unsealing analysis found a REAL suite defect anyway:
      | seed | mutation | verdict |
      |---|---|---|
      | 1 | `linked_list.ak` node ordering `key < next` → `key != next` | CAUGHT, surgical: exactly `prop_directory_node_rejects_any_unordered_key_pair` + `registry_insert_fails_covering_key_ge_insert_key` |
      | 2 | `registry_spend.ak` update auth read from `transfer_logic_script` instead of `minting_logic_script` | CAUGHT via over-rejection only (the 2 positive update tests). Unsealing revealed the update-path negatives could NOT catch the over-acceptance direction — see defect below. Now killed from both sides: + `fails_update_authorised_by_transfer_logic_withdrawal` |
      | 3 | `unfracking.ak` unpaired-output owner match on payment credential only (stake-swap class) | CAUGHT, surgical: exactly `unfracking_fails_acted_tokens_to_other_stake_cred` |
    - **Defect found by the exercise**: SIX pre-existing
      `fails_update_*` negatives called the insert-path
      `call_validator` (origin datum + placeholder own_ref), so
      `find_input` failed before any update-branch check ran — every
      one passed vacuously, regardless of its claimed invariant.
      Fixed with `call_update_validator` (real spent-node datum +
      matching own_ref); all six now exercise their real invariants,
      suite 331/331. This is the "check that cannot fail is
      decoration" failure mode, caught precisely because the seeds
      were independent.

- **Tier-0 property suite** (`21a5535`): 15 Blaster-shaped properties —
  unfracking conservation/strip (7), ThirdPartyAct ratchet + conservation
  + escape (4), registry credential/ordering equivalences (4). Shaped to
  aiken PR #1311 capabilities: arity-1 tuple fuzzers, bounded domains,
  boolean-equivalence bodies where possible.
- **Ledger-realism layer** (`a75cd29`): `programmable_logic/ledger_shape`
  module (rules ported from wsc-poc `Builder.hs` [LEDGER-RULE]s + Phil's
  Lean LR-CTX audit), all canonical fixtures reshaped (positive fee,
  ledger withdrawal order = Script<VKey then bytewise, min-UTxO 2 ada
  floor incl. resolved/ref inputs, sorted outref sets via
  `with_sequential_outrefs`), `is_ledger_shaped` audit + negatives.
  Suite stayed green under reshaping ⇒ validators are withdrawal-order-
  and fee-insensitive.
- **TransferAct properties** (4): conservation ∀ quantities, shortfall
  rejection, burn/mint reconciliation ∀ amounts.
- **Registry insert-chain property**: inserted+updated node pair valid ∀
  ordered 28-byte key triples; node output valid ∀ lovelace (min-ada
  robustness).
- **Golden Data-layout tests** (6): RegistryNode 7-field order (minting
  logic at index 2!), params 3-field, PLG redeemer indices 0/1/2,
  registry proofs 0/1, unfracking redeemer, Credential encoding.
- **Param-sensitivity analysis**:
  `documentation/design/protocol-param-sensitivity.md` — no action
  bricks under any audited param change; #96 hazard class proven absent
  on every surface (ratchet/ada-free/any-lovelace props).
- Suite: **326/326**.

- **2026-08-06 — CI layer LIVE (both sides green on first runs)**:
  - Spike repo published: https://github.com/easy1staking-com/cip113-lean-spike.
  - Lean deps pinned by exact git rev in the spike lakefile
    (Lean-blaster `083bae79`, PCB `a04042c4`, CLAB `5dab3c43` — stock
    upstream); full rebuild green locally AND in CI.
  - `verify.yml` (spike, on push/PR): parses the attested commit from
    `flats/MANIFEST.md`, checks out this repo AT that commit, runs the
    `extract-flats.sh --check` identity gate, then `lake build` (elan +
    pinned Lean 4.24.0, Z3 4.15.2 release binary, `.lake` cached).
    First run: **4m25s cold**, log-verified — 306 jobs, 4 artifacts
    decoded, 3 theorems ✅ Valid, axiom separation correct.
  - `fv-freshness.yml` (this repo, on push/PR): toolchain gated against
    the blueprint preamble, `aiken build`, byte-compares the 4 tracked
    `compiledCode` entries vs the spike's attested flats. RED = the
    change alters bytes the theorems were proven against → re-attest
    the spike. First run green. Note the division of labour: the
    spike's `--check` pins a SNAPSHOT (goes stale on any new commit —
    rerun `extract-flats.sh` to re-attest); `fv-freshness` tracks the
    branch TIP by bytes, so docs/test-only commits stay green.
  - Still pending (deliberate, not yet wired): weekly
    `falsification-control.sh` cron (needs aiken in spike CI), nightly
    `aiken check --max-success 500` here.

## Blockers

1. **RESOLVED 2026-07-31**: Tier-1 toolchain INSTALLED locally (Giovanni
   approved): elan + Lean 4.24.0, Z3 4.15.2 built from source at
   `~/.local/bin/z3`, IOG upstream Lean-blaster + PlutusCoreBlaster
   cloned to `~/Development/workspace/` and compiled. **SMOKE TEST
   PASSED**: spike project `~/Development/workspace/cip113-lean-spike/`
   imports all four flats (base 141 B, unfracking 1736 B, registry_mint
   1928 B, PLG 2996 B — extracted from our `plutus.json`) via
   `#import_uplc … single_cbor_hex` on STOCK upstream PCB `main`:
   "Successfully decoded" ×4, `lake build` green (283 jobs). ⇒ Aiken
   v1.1.22 PlutusV3 output needs NO fork for decode (answers Phil Q2).
   Whether the D6 tactic fix is needed only shows up at `blaster`-proof
   time, not decode time.
2. **Full symbolic proofs don't scale yet** (upstream): Phil's unshaped
   P3 gets no verdict in 93 min; the shaped-contexts methodology is the
   only viable route today. Not our blocker to fix — but it bounds what
   Tier 1 can promise.
3. **Permission gate**: harness blocked self-granting broad permissions
   (correctly). Giovanni: if wanted, add allow-rules to
   `.claude/settings.local.json` manually for smoother long runs.

## Open questions

- **For Giovanni**: (a) publish `ledger_shape`/realism docs into
  `documentation/` proper or keep as code-side docs? (b) benches now run
  on reshaped fixtures — the stored benchmark baselines shift slightly;
  re-baseline when? (c) is the 2-ada test floor OK, or prefer the real
  size-based formula ((160 + |serialized|) × coinsPerUTxOByte)?
- **Conway cert rules**: can a third party deregister a script stake
  credential (slashing its registration and blocking withdraw-0 gated
  actions until re-registration)? Affects the stakeAddressDeposit risk
  note in the param-sensitivity doc. Needs a ledger-rules check
  (cardano-ledger Conway certs), not guesswork.
- **For Phil** (from the 2026-07-31 investigation):
  1. Upstreaming timeline for the three forks (PCB CIP-153 / Blaster D6
     / CLAB fixes) — build on forks or wait?
  2. Does stock PCB decode Aiken 1.1.x PlutusV3 output (term/builtin
     coverage)? What's the quickest smoke test?
  3. Would he take our Aiken validators as a second verification target
     (wsc-poc already benchmarks our harness side-by-side)? Is the
     `WSC/` layout meant to be reusable?
  4. His keystone P3 only closes with ≤2 withdrawal entries
     (`WdrlPairShaped`); our unfracking composition carries FOUR
     withdraw-0s — same `pdropList`-class cliff on our bytecode?
  5. Vacuity-probe tooling: automated or by hand?

## MPFS PR #51 (cardano-foundation/cardano-mpfs-onchain) — reviewed 2026-07-31

Paolo Veronelli's (CF) OPEN PR: the same Blaster bridge for the MPFS
validators. Full notes in memory (`mpfs-blaster-bridge.md`). ADOPT from
it: (1) hermetic Nix derivation that rebuilds the blueprint and injects
the UPLC inside the proof build (kills blueprint staleness — our flats
are hand-copied); (2) universally quantified script params (adopted
already); (3) named Lean↔Aiken-fuzz mirroring (`/// **Lean: thm**`
doc-comments); (4) `jq -er` blueprint extraction script (rename-safe);
(5) cross-implementation golden vectors + CI freshness check. WE are
ahead on: property depth (their 29 theorems are dispatch/datum/signature
shell only), mutation testing (they have none), ledger-realism fixtures
(none), CI enforcement of the formal layer (their bridge isn't in CI).
Paolo is at CF and reachable — the Nix/bridge questions can go to him
instead of waiting for Phil.

## Next steps (in order)

1. Third-party **input-side** fuzzing (quantities, co-resident policies,
   input count) — needs a parametric variant of
   `validate_third_party_with_outputs`.
2. **Mutation-verification pass** (task #6): per property, mutate the
   guarded line, confirm exactly the matching test reddens, restore;
   record the matrix. Spot-checks DONE 2026-07-31:
   - `third_party.ak` ratchet `>=`→`>`: **18 tests redden** (unit
     baselines + `prop_third_party_lovelace_ratchet_accepts_any_topup`)
     — invariant heavily covered.
   - `unfracking.ak` conservation `==`→`tokens.contains`: **exactly 2
     redden** — `unfracking_fails_acted_surplus` +
     `prop_unfracking_rejects_any_fabrication_of_acted_tokens` — a
     surgical kill proving the fabrication guard is non-vacuous and
     uniquely owned by those tests.
   - `transfer.ak` output containment → `True`: **exactly 2 redden**
     (`transfer_act_mint_insufficient_output_fails` +
     `prop_transfer_rejects_any_shortfall`).
   - `linked_list.ak` `is_28_bytes` `==`→`>=`: **exactly the 2
     boolean-equivalence props redden** — the ⇔ shape catches the
     over-acceptance direction a plain positive test would miss.
   - `unfracking.ak` pairwise-equality skip (`expect True ||`): before
     2026-07-31 this mutation passed the ENTIRE suite — the lockstep
     walk's pairwise branch (co-resident policies sorting BEFORE the
     acted one) had zero guards. Two new props (pre-acted co-resident
     preserve/reject, `policy_pre` …0900) close the hole; the mutation
     now reddens exactly `prop_unfracking_rejects_any_pre_acted_non_acted_delta`.
     A REAL coverage gap found by mutation analysis.
   Remaining: golden-layout reorder (type-level mutation), full matrix
   write-up.
3. Registry insert **end-to-end** property through `registry_mint`
   (fuzz keys through the real Insert tx, not just the lib helpers).
4. **Benchmark-vs-ceiling CI pin** (from param doc): worst-case bench
   scenarios as % of mainnet maxTxExUnits.
5. **Tier-1 FIRST THEOREM PROVEN (2026-07-31 night)** — spike repo
   `~/Development/workspace/cip113-lean-spike/` (git-initialised):
   - `#prep_uplc appliedBase … 600` succeeds on our bytecode (1.6 s, no
     D6 failure, stock upstream everything incl. CardanoLedgerApiBlaster).
   - `base_forces_plg_withdrawal_one_entry` ✅ Valid: ∀ deployment
     param, ∀ one-entry withdrawal map (symbolic hash + amount),
     acceptance ⟹ the withdrawal credential IS the parameter — the PLB
     forwarding guarantee, universally quantified over deployments
     (idiom adopted from cardano-mpfs-onchain PR #51).
   - `exec_accepts` / `exec_rejects_foreign_withdrawal` kernel-checked
     (native_decide via the `isHaltB` reflection idiom; axioms are the
     standard native_decide set, NO sorry).
   - TRUST-CHAIN IMPROVEMENT vs Phil's pin: upstream Blaster `main`
     closes Valid goals with a NAMED axiom `Blaster.Tactic.blasterProven`
     (not `sorryAx`) — `#print axioms` now cleanly separates
     SMT-trusted from kernel-checked theorems.
   - **ENTRY-COUNT LADDER ✅ Valid at 1, 2 AND 4 withdrawal entries**
     (2026-07-31 late): the wsc `WdrlPairShaped` cliff (Phil stuck at 2
     on Plutarch's INDEX-based base) does not bite our SCAN-based
     `has_key_or_fail` — rung 4 = exactly the width of the unfracking
     composition. Each rung proved in seconds. Phil Q4 answered
     empirically, favourably.
   - Staleness guard added: `scripts/extract-flats.sh` (jq -er by
     blueprint title, --check freshness mode) — the non-Nix version of
     MPFS PR #51's extraction.
   Next rungs: find the actual entry-count wall (8, 16…), mixed
   vkey/script credential entries, unfracking mint-is-zero +
   hook-invocation theorems (needs a rewarding-context builder), budget/K
   measurements per validator, full Nix hermetic build.
6. Unfracking **shape-shrinking** test (maxValueSize mitigation claim).
7. `aiken check --max-success 500` nightly job.
