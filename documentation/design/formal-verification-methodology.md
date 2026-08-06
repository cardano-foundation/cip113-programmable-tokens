# Formal verification of the CIP-113 validators — methodology

Status: living document, 2026-08-06. Companion files:
`FORMAL_VERIFICATION_STATUS.md` (repo root — running status, blockers,
open questions) and `documentation/design/protocol-param-sensitivity.md`
(the protocol-parameter robustness analysis this effort produced).

This document is the **front door for an external evaluator**: what we
claim, under which vocabulary, with which evidence, produced by which
tools, reproducible how — and, just as deliberately, what we do *not*
claim. The reporting discipline follows paolino's
`aiken-blaster-verification` skill
(https://gist.github.com/paolino/3d9b79baffc075606bdd1ba4f9002f81),
which distills the same IOG toolchain's ground rules; where our
practices predate that document they are cross-referenced to it rather
than restated.

## 1. What is being verified

The four production validators of this repository, as **compiled
artifacts** — the `compiledCode` bytes in `plutus.json`, not a
hand-transcribed model of them:

| Validator | Blueprint title | Size |
|---|---|---|
| PLB (base) | `programmable_logic_base.programmable_logic_base.spend` | 141 B |
| Unfracking | `unfracking.unfracking.withdraw` | 1 736 B |
| Registry mint | `registry_mint.registry_mint.mint` | 1 928 B |
| PLG (global) | `programmable_logic_global.programmable_logic_global.withdraw` | 2 996 B |

We deliberately do **not** maintain a hand-written Lean model of the
validator logic. A model proof certifies the design, not the deployed
bytes, and the neighbouring Plutarch campaign (wsc-poc) demonstrated the
failure mode concretely: hand models there were refuted by the machine
against the actual bytecode. Everything at the theorem tier here runs
against imported compiled UPLC.

## 2. The verification stack

One effort, four reinforcing layers. Each layer's evidence class is
weaker than the one below it but covers far more surface; the layers
share fixtures, names and invariants so a property at layer 1 is the
*statement* a layer-4 theorem later proves.

**Layer 1 — property-based tests (evidence class: TESTED).**
46+ `prop_*` tests among the 330-test Aiken suite, written
"Blaster-shaped" (arity-1 tuple-encoded fuzzers, bounded integer /
bytearray domains, boolean or boolean-equivalence bodies) so that each
property is directly translatable into a Lean theorem by the
aiken → Blaster bridge (aiken draft PR #1311) when it lands — the
property suite doubles as the theorem backlog. Invariants covered:
conservation and containment for TransferAct / ThirdPartyAct /
Unfracking, the lovelace ratchet, seizure splits, PLB escape rejection,
registry key ordering and credential well-formedness, insert-chain
validity.

**Layer 2 — ledger realism (fixtures, not claims).**
`validators/programmable_logic/ledger_shape.ak` encodes the ledger's
transaction well-formedness rules (positive fee, min-UTxO floor on all
outputs *and* resolved/reference inputs, withdrawal maps in ledger
credential order — Script < VerificationKey, then bytewise, the
*opposite* of the Plutus/Aiken order — strictly ascending input
`OutputReference` sets, sorted signatories). Every canonical fixture is
audited against the `is_ledger_shaped` predicate, so no green test rests
on a transaction the ledger would never produce. The rules were ported
from the wsc-poc `Builder.hs` `[LEDGER-RULE]` annotations and Phil
DiSarro's Lean-side context audit.

**Layer 3 — golden Data layouts (evidence class: TESTED, frozen).**
Six tests pin the on-chain `Data` encodings (constructor indices and
field order for `RegistryNode`, the protocol-params datum, all redeemer
types, `Credential`) via raw `un_constr_data` destructuring — the
representation-level contract between the validators, the SDK, and the
Lean fixtures.

**Layer 4 — theorems over the compiled bytecode.**
Repository `cip113-lean-spike` (see §6). The compiled artifact is
imported with `#import_uplc`, prepared for symbolic execution with
`#prep_uplc`, and reasoned about along the wsc-poc shaped-contexts
methodology: concrete accepting/rejecting executions first (non-vacuity
+ polarity controls), then symbolic theorems over shaped context
families, universally quantified over the deployment parameter (idiom
from cardano-mpfs-onchain PR #51).

## 3. Claims vocabulary

Every published result carries exactly one disposition label:

- **KERNEL-PROVED** — a Lean kernel-checked proof term exists. Our
  concrete CEK executions (`native_decide` over the `isHaltB`
  reflection) are in this class. Trust base: the Lean kernel, the
  standard `native_decide` axioms (`ofReduceBool`), and the
  PlutusCoreBlaster CEK model's fidelity (§7).
- **SMT-VALID (no proof term)** — discharged by the `blaster` tactic:
  the negated goal was sent to Z3 and came back `unsat`. Closed in Lean
  by the named axiom `Blaster.Tactic.blasterProven` — visible to
  `#print axioms`, cleanly separating this class from KERNEL-PROVED.
  This is a strong result but it is *not* a kernel proof; the trust
  base adds Z3 4.15.2 and Blaster's Lean→SMT-LIB translation. All
  `base_forces_plg_withdrawal_*` theorems are in this class.
- **TESTED** — held under property-based fuzzing (bounded domains,
  default 100 samples per property, ledger-shaped fixtures).
- **UNPROVED / OUT-OF-SCOPE** — stated but not yet established, or
  outside the current shaped-context families. §5 of
  `FORMAL_VERIFICATION_STATUS.md` tracks these.

Run outcomes (orthogonal to the labels above) are ternary —
**ESTABLISHED / REFUTED / COULD-NOT-EVALUATE** — and anything that is
not a clean established/refuted result (timeout, missing artifact,
stale manifest, unsupported builtin dispatch, toolchain mismatch) is
COULD-NOT-EVALUATE and treated as **red**, never as a pass. When the
CEK machine stops we distinguish a *refused builtin dispatch* (tooling
limitation) from a *validator-logic error* (a fact about the program);
a harness that cannot tell the two apart has not produced a result.

## 4. Identity discipline

A claim about compiled code is only as good as its stated identity.
Every Lean-tier claim carries the triple:

**source commit + toolchain + `BuiltinSemanticsVariant`**

mechanically, via `cip113-lean-spike/flats/MANIFEST.md`, which is
generated (never hand-edited) by `scripts/extract-flats.sh` from:

- the source repo's `git rev-parse HEAD` (plus a dirty-tree flag scoped
  to compile-relevant inputs);
- the blueprint's **own** `.preamble.compiler` field — not prose, and
  not whatever `aiken` happens to be installed (this distinction caught
  a real drift on 2026-08-06: blueprint built by v1.1.22+39d6b04,
  installed CLI was v1.1.21);
- the pinned semantics variant: `defaultFunSemanticsVariantE` (PlutusV3,
  post-Conway — the mainnet deployment target), which is what
  PlutusCoreBlaster's `#prep_uplc` evaluates under
  (`cekExecuteProgram = …WithSemanticVariant default`,
  `Inhabited BuiltinSemanticsVariant := variantE`);
- sha256 of the blueprint and of every extracted flat.

`extract-flats.sh --check` re-derives everything and fails red on any
divergence; it is itself falsified (a corrupted flat and a tampered
manifest are both demonstrated to turn it red). Artifact encoding note:
an Aiken blueprint's `compiledCode` is **single** CBOR-wrapped flat
UPLC (`single_cbor_hex` to `#import_uplc`); the double-wrapped form is
the on-chain tx-witness encoding. Source→blueprint correspondence is
*not* assumed from git history — it is established by rebuild
(§5, leg 2).

## 5. Falsification discipline

No gate is trusted until it has been shown able to fail.

**Aiken tier — the mutation matrix** (`FORMAL_VERIFICATION_STATUS.md`
§Next-steps 2): for each guarded invariant, mutate the guarding line in
the validator source, confirm that *exactly* the matching tests redden,
restore. Six entries recorded to date; the method has already earned
its keep by finding a real hole (the unfracking pairwise-walk branch
had zero guards — a mutation survived the entire suite; two properties
now close it and the same mutation reddens exactly one of them).

**Lean tier — `scripts/falsification-control.sh`** (the
Vesting-"bugged" idiom from Lean-blaster's own examples, extended
through the real build pipeline). Legs, all mandatory, working tree
never touched (temp git worktree):

0. toolchain identity: installed `aiken` must equal the blueprint
   preamble's compiler, else COULD-NOT-EVALUATE;
1. flats + manifest freshness;
2. **reproducibility**: a clean rebuild from HEAD must reproduce the
   committed `compiledCode` byte-for-byte;
3. **mutant**: gut the base validator's withdrawal check (→ `True`),
   rebuild through the real pipeline, assert the artifact changed;
4. **control**: the theorem that is Valid on the clean artifact must
   come back **Falsified** on the mutant (`#blaster (solve-result: 1)`),
   and the context the clean artifact rejects must be *accepted* by the
   mutant, kernel-checked — proof the mutation reached the executable
   semantics;
5. restore, re-verify the clean baseline green.

**Independent negative controls (open).** Every mutation above was
seeded by the same author who wrote the checks. Per the discipline's
"don't let one person's imagination be the whole test": reviewers are
invited to seed their own single-line mutations (without disclosing
them) and require the pipeline to catch each one. This is a standing
ask, tracked in the status file.

## 6. Resources and repository map

**This repo** (branch `test/blaster-tier0-properties`): property suite
+ `ledger_shape` + golden layouts under `validators/` and `lib/`;
`FORMAL_VERIFICATION_STATUS.md`; this document;
`documentation/design/protocol-param-sensitivity.md`.

**`cip113-lean-spike`** —
https://github.com/easy1staking-com/cip113-lean-spike (checked out as a
sibling directory of this repo; `lakefile.lean` wires the paths):

```
lakefile.lean            -- requires Blaster, PlutusCore, CardanoLedgerApi (order matters)
flats/*.flat             -- extracted compiledCode hex (4 validators)
flats/MANIFEST.md        -- the identity triple, mechanically generated
scripts/extract-flats.sh -- extraction + --check freshness gate
scripts/falsification-control.sh -- the five-leg control of §5
Cip113Spike/Smoke.lean   -- decode smoke test (all 4 artifacts)
Cip113Spike/PrepBase.lean  -- parameter evidence + #prep_uplc, identity note
Cip113Spike/PropsBase.lean -- executions + the withdrawal-forcing theorem ladder
controls/MutantControl.lean -- expect-Falsified control (never in default build)
```

**Toolchain** (all public, Apache-2.0):
- Lean 4.24.0 via elan; Z3 4.15.2 (built from source).
- `input-output-hk/Lean-blaster` — the `#blaster` command/tactic
  (Lean → SMT-LIB → Z3), counterexample generation.
- `input-output-hk/PlutusCoreBlaster` — Lean model of UPLC, the CEK
  machine, `BuiltinSemanticsVariant`, `#import_uplc` / `#prep_uplc`.
- `input-output-hk/CardanoLedgerApiBlaster` — Lean model of the V1–V3
  script-context types.
- Aiken pinned per blueprint preamble (currently v1.1.22+39d6b04).
- **Stock upstream `main` of all three Lean repos — zero forks.**
  (Established empirically: Aiken 1.1.x PlutusV3 output decodes and
  proves on unmodified upstream.)

**Method sources**: wsc-poc `wsc-containment-proofs` campaign (Phil
DiSarro / Anastasia-Labs) — shaped contexts, `isHaltB` reflection,
vacuity probes; cardano-mpfs-onchain PR #51 (Paolo Veronelli / CF) —
universally-quantified script parameters, `jq -er` extraction,
hermetic-build direction; paolino's `aiken-blaster-verification` skill
— reporting and identity discipline; aiken draft PR #1311 — the
property→theorem bridge the Layer-1 shapes target.

## 7. Trust base and known limitations

Stated so nobody cites this effort for more than it establishes:

1. **SMT-VALID results trust Z3 and the Blaster translation.** No proof
   reconstruction yet; `#print axioms` names `blasterProven` on every
   such theorem. If/when Blaster gains proof reconstruction these
   upgrade to KERNEL-PROVED without restating.
2. **The CEK model is a model.** PlutusCoreBlaster's machine and
   builtin semantics are a faithful-by-construction Lean transcription,
   not the Haskell node code. Divergence between the two would
   invalidate layer-4 claims; it is mitigated, not eliminated, by the
   concrete-execution controls (accepting and rejecting runs match the
   Aiken-side test expectations).
3. **Shaped contexts, not full symbolic execution.** The theorem ladder
   quantifies over context *families* (currently: withdrawal maps of
   1/2/4 entries with symbolic script-credential hashes and amounts,
   fixed elsewhere). Full-context symbolic proofs do not scale in the
   current toolchain (upstream limitation, measured). A claim's family
   is part of its statement; nothing is claimed outside it.
4. **Variant E only.** All results are under PlutusV3 post-Conway
   semantics. Nothing is claimed for other variants or eras.
5. **Property tests sample.** Layer-1 TESTED results are 100-sample
   fuzz runs (500-sample nightly planned), not exhaustive; their role
   is breadth and future theorem statements, and their fixtures are
   ledger-shaped but use a flat 2-ada min-UTxO stand-in rather than the
   size-based formula (decision recorded 2026-07-31).
6. **The manifest cannot prove source→blueprint correspondence by
   itself** — that is exactly what leg 2 of the falsification control
   rebuilds and byte-compares for; run it, don't infer it.

## 8. Reproducing from a fresh checkout

```sh
# 1. Toolchain
brew install elan-init jq && elan default stable   # Lean via elan
# build Z3 4.15.2 from source into PATH (see Lean-blaster README)
aikup install v1.1.22                              # must match blueprint preamble

# 2. Clone side-by-side
git clone <this-repo>            cip113-programmable-tokens   # branch test/blaster-tier0-properties
git clone <cip113-lean-spike>    cip113-lean-spike
git clone https://github.com/input-output-hk/Lean-blaster
git clone https://github.com/input-output-hk/PlutusCoreBlaster
git clone https://github.com/input-output-hk/CardanoLedgerApiBlaster

# 3. Aiken tier (330 tests incl. all prop_* and golden layouts)
cd cip113-programmable-tokens && aiken check

# 4. Lean tier
cd ../cip113-lean-spike
./scripts/extract-flats.sh --check   # identity gate — must be green
lake build                           # smoke + prep + theorem ladder

# 5. Falsify the harness before believing any of the above
./scripts/falsification-control.sh   # all five legs must end GREEN
```

A result someone cannot reproduce from these steps plus the manifest
is not a result this effort claims.
