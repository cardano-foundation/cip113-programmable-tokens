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

## Status (2026-08-25)

The first theorems since the PLG dissolution (#110) are discharged, on
`programmable_logic_base` only. Everything below names its artifact, its
prep fuel, and whether a falsification control has been shown to break
it — a claim missing any of those is not a claim.

### Live claims

Artifact for every PLB row: `flats/programmable_logic_base.flat`
(829 B), **prep fuel 1600**, BuiltinSemanticsVariant E, theorems in
`Cip113Spike/PropsBase.lean`. "Control" is leg 4 of
`scripts/falsification-control.sh`: a PLB rebuilt through the real Aiken
pipeline with its witnessed-withdrawal equality gutted to `True`.

| Claim | Label | Control |
|---|---|---|
| All 5 committed flats decode on stock upstream PlutusCoreBlaster (`single_cbor_hex`) | ESTABLISHED (`Cip113Spike/Smoke.lean`) | n/a |
| Each validator's compile-time parameter application is expressible and typechecks against the current signatures (PLB / transfer / third_party / unfracking take a `PolicyId`; registry_mint takes `OutputReference`, `PolicyId`, `Credential`) | ESTABLISHED (`Cip113Spike/Prep*.lean`) | n/a |
| **The dispatch matrix.** One live protocol (all three delegates withdrawing, in ledger order), nine redeemers: PLB accepts exactly the three where the arm's params-datum field and the witnessed withdrawal agree, and rejects all six mismatches — including a `SpendViaTransfer` that witnesses the THIRD-PARTY delegate | KERNEL-PROVED (`exec_accepts_{transfer,third_party,unfracking}_arm`, `exec_rejects_*_arm_at_*`) | GREEN — all six rejections flip to acceptances on the mutant |
| PLB rejects a transaction in which no delegate withdraws at all (the sole withdrawal is a foreign credential), and accepts the one-delta twin in which the delegate does | KERNEL-PROVED (`exec_rejects_foreign_withdrawal`, `exec_accepts_sole_delegate_withdrawal`) | GREEN |
| The compiled credential equality is TAG-sensitive: the delegate's 28 bytes under a verification-key credential are not the delegate | KERNEL-PROVED (`exec_rejects_vkey_tagged_delegate`) | GREEN |
| `wdrl_idx` is self-validating: an index addressing a real withdrawal of the same transaction that is not the delegate's rejects, while the ledger-ordered twin accepts | KERNEL-PROVED (`exec_rejects_wdrl_idx_at_foreign_withdrawal`, `exec_accepts_four_entry_map`) | GREEN |
| An out-of-range `wdrl_idx` rejects | KERNEL-PROVED (`exec_rejects_out_of_range_wdrl_idx`) | NONE — guarded by `list.expect_at`, which this mutant leaves standing (mutant still rejects, asserted in the control) |
| The delegate credentials must come from an AUTHENTICATED params UTxO: a forged datum without the params NFT rejects, a params input without an inline datum rejects, a `params_idx` addressing a decoy reference input rejects, and `params_idx: 1` accepts when the ledger puts the real one there | KERNEL-PROVED (`exec_rejects_unauthenticated_params_input`, `exec_rejects_params_input_without_inline_datum`, `exec_rejects_params_idx_at_non_params_reference_input`, `exec_accepts_params_at_reference_index_one`) | NONE — guarded by the NFT-presence and inline-datum `expect`s in `programmable_logic/params.ak`; their mutants are a later slice |
| Independence witnesses (R2b witness-set form): two PLB spend inputs accept; a structurally different validity range accepts | KERNEL-PROVED (`exec_accepts_two_plb_inputs`, `exec_accepts_range_variant`) | NONE — witness form, nothing to falsify |
| A non-spend (rewarding) purpose does not reach Halt — the LEDGER dispatch gate, not an in-body branch | KERNEL-PROVED (`exec_rejects_nonspend_purpose`) | NOT APPLICABLE — a control would have to mutate the harness's `spendingInputs`, not the validator |
| The accepting halt value is the unit constant (CIP-117) | KERNEL-PROVED (`exec_accepts_unit`) | n/a |
| Every fixture above is a context a node could actually produce — ascending outrefs, canonical values, ledger-ordered withdrawals, redeemer map agreeing with the purpose, balanced | ESTABLISHED (`spend_fixtures_are_ledger_shaped`, `rewarding_fixture_is_ledger_shaped`, via CardanoLedgerApiBlaster's `validSpendingContext` / `validRewardingContext`) | n/a |
| The pipeline can tell working code from broken code: mutant rebuilt through the real Aiken pipeline, nine theorems flip, the three acceptances survive (broken, not bricked), the five rejections the mutation does not reach are unchanged | ESTABLISHED (`scripts/falsification-control.sh`, legs 0-5; leg 4b a declared skip) | — |
| Axiom drift reddens the build: every `#print axioms` is pinned by `#guard_msgs` | ESTABLISHED (claim-integrity gate, CI-enforced) | — |

Prep fuel 1600 is measured, not chosen: the largest accepting step count
over the eight accepting families prepped is 1314, and
`scripts/fuel-probe.lean` reproduces the whole table (and re-checks that
halting is monotone in the fuel, which is what makes the bisection
sound). Note that the step count is NOT monotone in the withdrawal index
walked — it runs 1168, 1241, 1222, 1295, 1276, 1349 for indices 0..5 —
so no other artifact may inherit this number.

### Not established

| Claim | Why not |
|---|---|
| `transfer`, `third_party`, `unfracking`, `registry_mint` prep | Each needs a concrete ACCEPTING context first. Unshaped symbolic prep blows up exponentially in the fuel well below their accepting step counts (see `Cip113Spike/PrepTransfer.lean`); the fully concrete families used for PLB show the prep itself is cheap once a context exists |
| ANY universally-quantified (SMT) claim about PLB | `PropsBase.lean` preps concrete families, so its `.prop` is a single run. The `∀`-quantified forwarding property needs a family with a genuine symbolic leaf, built for it |
| Controls for the params-authentication, inline-datum and `wdrl_idx`-bounds rejections | Each needs its own seeded bug; listed at the bottom of `controls/MutantControl.lean` |

### Superseded claim table (pre-#110) — VOID, retained as the re-derivation target list

Every row below cites a theorem module that no longer exists, or the
dissolved `programmable_logic_global` artifact. They are **all
COULD-NOT-EVALUATE** until re-derived against the current surface. Do not
quote any of them. The PLB rows that HAVE been re-derived are gone from
this table and live in the Live claims table above.

| Claim (superseded) | Former label |
|---|---|
| ∀ deployment param, ∀ 1/2/4-entry withdrawal maps (symbolic hashes + amounts): PLB acceptance forces the param to be present — the forwarding guarantee | SMT-VALID, no proof term (`base_forces_plg_withdrawal_{one,two,four}_entries`) |
| ∀ symbolic output credential + quantities in family T1 (TransferAct, 1 policy, 1 PLB input, 1 output): PLG acceptance forces the output credential to BE the PLB — tokens cannot escape the jail | SMT-VALID, no proof term (`t1_escape`; vacuity probe Expected Falsified) |
| Same family, output pinned at the PLB: acceptance forces qOut ≥ qIn | SMT-VALID, no proof term (`t1_conservation`; non-vacuity probe Expected Falsified) |
| Dropping the transfer-logic withdrawal from an otherwise-accepting T1 context rejects — the substandard-invocation guarantee on the compiled PLG | KERNEL-PROVED (`exec_rejects_no_transfer_logic`) |
| Two-owner authorization (V4/S-16): with two PLB inputs of distinct owners, an unauthorized second owner rejects on the compiled PLG (vkey and script-staked flavours, accepting twins per R1); a seeded first-input-only auth mutant ACCEPTS the same context (falsification Leg 4b) | KERNEL-PROVED (`PropsGlobalAuth.lean`, 4 controls) + ESTABLISHED (auth mutant leg) |

One pre-#110 row is retired rather than pending: redeemer-shape
independence (`exec_accepts_redeemer_*`). The pre-#110 PLB ignored its
redeemer; the current one dispatches on it, so "the redeemer does not
matter" is no longer a property to re-derive — the dispatch matrix above
is what replaced it.

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
scripts/falsification-control.sh -- harness falsification, legs 0-5
                              (leg 4b a declared skip; see below)
examples/deployment-manifest.example.json -- schema example for the closure checker
scripts/fuel-probe.lean    -- how the #prep_uplc fuel number was measured
                              (binary search for the accepting step count,
                              plus the monotonicity check that makes the
                              bisection sound; NOT part of `lake build`)
Cip113Spike.lean           -- the default build target: imports the seven
                              modules below and nothing else
Cip113Spike/Smoke.lean     -- artifact decode smoke test (all five flats)
Cip113Spike/PrepBase.lean  -- programmable_logic_base: #import_uplc +
                              parameter application, identity note. Per the
                              PrepX/PropsX convention, no prep and no
                              theorem lives here
Cip113Spike/PropsBase.lean -- programmable_logic_base: the fixtures, twenty-two
                              fully CONCRETE #prep_uplc families at fuel 1600,
                              and the theorems (dispatch matrix, forwarding,
                              params authentication, ledger realism)
Cip113Spike/PrepTransfer.lean     -- transfer: import + parameter application;
                                     carries the unshaped-prep measurements
Cip113Spike/PrepThirdParty.lean   -- third_party: import + parameter application
Cip113Spike/PrepUnfracking.lean   -- unfracking: import + parameter application
Cip113Spike/PrepRegistryMint.lean -- registry_mint: import + its THREE parameters
controls/MutantControl.lean       -- LIVE falsification control for PropsBase;
                                     NEVER in the default build (see lakefile
                                     globs) because it needs a mutant flat that
                                     is gitignored and normally absent
controls/AuthMutantControl.lean   -- still targets the dissolved PLG surface;
                                     excluded and untouched until the transfer
                                     theorems exist for it to falsify
```

CI: `.github/workflows/formal-verification.yml` (repo root) enforces the
whole chain per push — toolchain == blueprint preamble, clean rebuild
reproduces the committed blueprint byte-for-byte, flats + manifest fresh,
`lake build` re-discharges every theorem.

## Prerequisites

- Lean via elan (toolchain pinned in `lean-toolchain`)
- Z3 **4.15.2** on PATH (release binary or source build; see the
  Lean-blaster README — CI uses the GitHub release binary)
- Aiken matching the blueprint preamble (currently `v1.1.23`; check
  `jq .preamble.compiler ../plutus.json` — a different version is
  COULD-NOT-EVALUATE for the rebuild legs)
- The three Lean deps (Lean-blaster, PlutusCoreBlaster,
  CardanoLedgerApiBlaster — stock upstream, zero forks) are fetched
  automatically by `lake` at the exact revs pinned in `lakefile.lean`.

## Run (from this directory)

```sh
./scripts/extract-flats.sh --check   # identity + completeness gate first
lake build                           # decode + prep (theorems as they land)
./scripts/falsification-control.sh   # falsify the harness before trusting green
./scripts/deployment-manifest-check.sh examples/deployment-manifest.example.json
                                     # trust-root closure BEFORE any deployment
```

The falsification control never touches the working tree (temp git
worktree): it verifies toolchain identity, rebuilds the blueprint
cleanly (must reproduce committed bytes exactly), rebuilds with the base
validator's only acceptance check gutted, and requires nine theorems
that are green on the clean artifact to come back **false** on the
mutant — while the three acceptances survive and the five rejections the
mutation does not reach stay put — then restores and re-verifies the
baseline. Leg 4b (the `transfer` auth mutant) is a declared skip: a
control can only falsify a theorem that exists, and `transfer` has none
yet.

## Method lineage

Shaped-context methodology and `isHaltB` reflection from Phil DiSarro's
wsc-containment-proofs campaign (Anastasia-Labs/CardanoLedgerApiBlaster);
universally-quantified script parameters and `jq -er` extraction from
cardano-mpfs-onchain PR #51 (Paolo Veronelli); reporting and identity
discipline per paolino's aiken-blaster-verification skill; property
shapes target the aiken→Blaster bridge (aiken draft PR #1311).
