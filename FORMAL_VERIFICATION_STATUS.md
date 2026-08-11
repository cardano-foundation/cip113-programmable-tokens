# Formal verification & test-hardening — status, blockers, next steps

Working file (local, like `CONTRACT_SURFACE_CHANGES.md`). Branch:
`feat/formal-verification` (supersedes `test/blaster-tier0-properties`).
Last update: 2026-08-11.

**Front door for evaluators:**
`documentation/design/formal-verification-methodology.md` — criteria,
claims vocabulary, identity + falsification discipline, trust base,
reproduction steps. This file is the running log behind it.

## Done

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
