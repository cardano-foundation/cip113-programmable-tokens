# Formal verification (Lean 4 / Blaster)

Lean 4 verification of the **compiled** CIP-113 Aiken validators using
the IOG Blaster toolchain: theorems and controlled executions over the
actual `compiledCode` bytes from `plutus.json` — not a hand model of
them. The Aiken sources, the blueprint, the extracted artifacts, and the
theorems all live in this repository, so every claim is pinned by a
single commit.

This directory is one layer of a single, unified verification effort.
Read **`../documentation/design/formal-verification-methodology.md`
first** — it defines the claims vocabulary (KERNEL-PROVED / SMT-VALID /
TESTED), the identity discipline, the falsification discipline, and the
trust base. Nothing here should be cited without that context. Running
status lives in `../FORMAL_VERIFICATION_STATUS.md`.

History note: this work started as a standalone spike repo
(`easy1staking-com/cip113-lean-spike`, now archived) and was folded into
this repo 2026-08-11 so the verification cannot drift from the code it
verifies.

## What is established here (as of 2026-08-11)

| Claim | Label |
|---|---|
| All 4 validators decode on stock upstream PlutusCoreBlaster (`single_cbor_hex`) | ESTABLISHED |
| PLB accepts a withdraw-0 context carrying its parameter credential | KERNEL-PROVED (`exec_accepts`) |
| PLB rejects a context whose only withdrawal is a foreign credential | KERNEL-PROVED (`exec_rejects_foreign_withdrawal`) |
| ∀ deployment param, ∀ 1/2/4-entry withdrawal maps (symbolic hashes + amounts): PLB acceptance forces the param to be present — the forwarding guarantee | SMT-VALID, no proof term (`base_forces_plg_withdrawal_{one,two,four}_entries`) |
| The pipeline can tell working code from broken code (mutant rebuilt through the real Aiken pipeline → theorem Falsified with counterexample, mutant accepts the rejected context) | ESTABLISHED (`scripts/falsification-control.sh`, all 5 legs) |
| ∀ symbolic output credential + quantities in family T1 (TransferAct, 1 policy, 1 PLB input, 1 output): PLG acceptance forces the output credential to BE the PLB — tokens cannot escape the jail | SMT-VALID, no proof term (`t1_escape`; vacuity probe Expected Falsified) |
| Same family, output pinned at the PLB: acceptance forces qOut ≥ qIn | SMT-VALID, no proof term (`t1_conservation`; non-vacuity probe Expected Falsified) |
| Dropping the transfer-logic withdrawal from an otherwise-accepting T1 context rejects — the substandard-invocation guarantee on the compiled PLG | KERNEL-PROVED (`exec_rejects_no_transfer_logic`) |
| PLB witness/control suite per standing rules R1/R2/R2b: non-spend purpose rejected (dispatch gate), vkey-tagged same-bytes credential rejected (tag sensitivity), 2/4-entry maps accepted with param in last slot, two PLB inputs accepted, three discriminating redeemer shapes accepted, structurally different validity range accepted, accepting halt value is the unit constant | KERNEL-PROVED (`exec_rejects_nonspend_purpose`, `exec_rejects_vkey_tagged_param`, `exec_accepts_{two,four}_entries`, `exec_accepts_two_inputs`, `exec_accepts_redeemer_*`, `exec_accepts_range_variant`, `exec_accepts_unit`) |
| Axiom drift reddens the build: every `#print axioms` is pinned by `#guard_msgs`, falsified live on both tiers (seeded `sorry` → mismatch; dropped `blasterProven` → mismatch) | ESTABLISHED (claim-integrity gate, CI-enforced) |
| Two-owner authorization (V4/S-16): with two PLB inputs of distinct owners, an unauthorized second owner rejects on the compiled PLG (vkey and script-staked flavours, accepting twins per R1); a seeded first-input-only auth mutant ACCEPTS the same context (falsification Leg 4b) | KERNEL-PROVED (`PropsGlobalAuth.lean`, 4 controls) + ESTABLISHED (auth mutant leg) |

Identity for every claim: `flats/MANIFEST.md` (compiler from the
blueprint's own preamble, sha256s, `BuiltinSemanticsVariant = E` /
PlutusV3 post-Conway; the source commit is the commit containing the
manifest). If `./scripts/extract-flats.sh --check` is not green, every
claim above is COULD-NOT-EVALUATE.

## Layout

```
lakefile.lean              -- requires Blaster FIRST, then PlutusCore, CardanoLedgerApi
flats/                     -- extracted compiledCode + MANIFEST.md (generated)
scripts/extract-flats.sh   -- extraction + --check identity gate (now also
                              a completeness gate: every blueprint title
                              must be extracted or DELIBERATELY_UNVERIFIED)
scripts/deployment-manifest-check.sh -- pre-submission trust-root closure
                              checker (V13); the only catch for a
                              misconfigured params datum
scripts/falsification-control.sh -- 5-leg harness falsification (see below)
examples/deployment-manifest.example.json -- schema example for the closure checker
Cip113Spike/Smoke.lean     -- artifact decode smoke test
Cip113Spike/PrepBase.lean  -- parameter evidence, #prep_uplc, identity note
Cip113Spike/PropsBase.lean -- executions + the withdrawal-forcing theorem ladder
Cip113Spike/PrepGlobal.lean -- PLG artifact import (prep is SHAPED, in PropsGlobal)
Cip113Spike/PropsGlobal.lean -- T1 containment family: escape + conservation theorems
controls/MutantControl.lean -- expect-Falsified control; NEVER in the default build
```

CI: `.github/workflows/formal-verification.yml` (repo root) enforces the
whole chain per push — toolchain == blueprint preamble, clean rebuild
reproduces the committed blueprint byte-for-byte, flats + manifest fresh,
`lake build` re-discharges every theorem.

## Prerequisites

- Lean via elan (toolchain pinned in `lean-toolchain`)
- Z3 **4.15.2** on PATH (release binary or source build; see the
  Lean-blaster README — CI uses the GitHub release binary)
- Aiken matching the blueprint preamble (currently `v1.1.22`; check
  `jq .preamble.compiler ../plutus.json` — a different version is
  COULD-NOT-EVALUATE for the rebuild legs)
- The three Lean deps (Lean-blaster, PlutusCoreBlaster,
  CardanoLedgerApiBlaster — stock upstream, zero forks) are fetched
  automatically by `lake` at the exact revs pinned in `lakefile.lean`.

## Run (from this directory)

```sh
./scripts/extract-flats.sh --check   # identity + completeness gate first
lake build                           # decode + prep + all theorems
./scripts/falsification-control.sh   # falsify the harness before trusting green
./scripts/deployment-manifest-check.sh examples/deployment-manifest.example.json
                                     # trust-root closure BEFORE any deployment
```

The falsification control never touches the working tree (temp git
worktree): it verifies toolchain identity, rebuilds the blueprint
cleanly (must reproduce committed bytes exactly), rebuilds with the
base validator's check gutted, and requires the clean-Valid theorem to
come back **Falsified** on the mutant — then restores and re-verifies
the baseline.

## Method lineage

Shaped-context methodology and `isHaltB` reflection from Phil DiSarro's
wsc-containment-proofs campaign (Anastasia-Labs/CardanoLedgerApiBlaster);
universally-quantified script parameters and `jq -er` extraction from
cardano-mpfs-onchain PR #51 (Paolo Veronelli); reporting and identity
discipline per paolino's aiken-blaster-verification skill; property
shapes target the aiken→Blaster bridge (aiken draft PR #1311).
