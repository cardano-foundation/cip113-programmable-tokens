# Contract Surface Changes Since the Pre-Audit Baseline

Tracking document for every **breaking change to the contract surface**
(validator set, blueprint parameters, redeemer schemas, off-chain-built
datums, and transaction-shape requirements) introduced by the audit-fix
work. Purpose: drive the documentation rewrite and the migration of the
Evolution CIP-113 SDK (`/Users/giovanni/Development/workspace/cip113-sdk-ts`)
once the audit branch work settles.

- **Baseline**: `8143853` ("chore: removed unwantes build script") — the
  last commit on `main` before the first audit-fix merge (#51,
  2026-05-19). Everything earlier (incl. #50 publish handlers) is
  considered pre-audit surface.
- **Method**: `plutus.json` is committed at every merge, so validator
  titles, parameters, and redeemer schemas were diffed mechanically
  commit-by-commit along `main` (first-parent) and for each open PR
  head. Off-blueprint datums (`RegistryNode`, the protocol-params
  datum) were tracked through `lib/registry_node.ak` /
  `programmable_logic/params.ak` type definitions. Semantic/tx-shape
  changes come from the PR diffs.
- Open PRs are listed as **PROVISIONAL — subject to change** until
  merged. Last refreshed: **2026-06-11**.

## Systemic note: every merge re-hashes everything

Independent of schema changes, ANY validator code change produces new
script hashes, and the protocol's parameter chaining cascades it
everywhere: `issuance_mint`'s template bytes feed the `IssuanceCborHex`
reference datum (prefix/postfix), `registry_mint` is parameterised by
`issuance_cbor_hex_cs` and `registry_spend_cred`, the protocol-params
datum embeds `prog_logic_cred`, and `programmable_logic_base` is
parameterised by PLG's credential. Consequently **every merged PR below
implies a full protocol redeployment** (new addresses, new
IssuanceCborHex data, new params NFT) even when marked "no schema
change". The SDK fetches blueprints from the backend API so hashes flow
through automatically — the breakage points are the **hand-coded
builders** (datums, redeemers, parameter application arity/order) and
**tx-shape requirements** listed below.

---

## Merged on `main`

### PR #51 — Findings 03, 08, 09 (`0a04cc2`, 2026-05-19)

| Surface | Change | Breaking? |
|---|---|---|
| `issuance_mint` params | **Added 4th parameter** `plg_stake_cred: Credential` (after `programmable_logic_base`, `registry_node_cs`, `minting_logic_cred`) | **YES** — parameter application arity |
| `registry_mint` params | **Added 3rd parameter** `registry_spend_cred: Credential` (after `utxo_ref`, `issuance_cbor_hex_cs`) | **YES** — parameter application arity |
| Tx shape | Finding 03: registry **origin node must be created at the `registry_spend` address** (Init flow) | YES for registry-init builders |

### PR #52 — Finding 07 (`2f6cd90`)

| Surface | Change | Breaking? |
|---|---|---|
| `registry_mint` redeemer | `RegistryInsert { key, hashed_param: ByteArray }` → `RegistryInsert { key, minting_logic_script: Credential, mode: RegistrationMode }`; new type `RegistrationMode = RegisterOnly \| RegisterAndMint` | **YES** — redeemer builder |
| `RegistryNode` datum (NFT inline datum, built off-chain) | **Inserted `minting_logic_script: Credential` at field index 2** → now `{ key, next, minting_logic_script, transfer_logic_script, third_party_transfer_logic_script, global_state_cs }` (6 fields) | **YES** — positional datum builder/parser |
| Tx shape | Register-only flow (no first mint) now exists alongside register-and-mint | Additive |

### PR #68 — Finding 10 (`1687209`)

| Surface | Change | Breaking? |
|---|---|---|
| `issuance_mint` redeemer | `SmartTokenMintingAction { minting_logic_cred, minting_registry_proof }` wrapper **removed** → redeemer is now `MintingRegistryProof = RefInput { index } \| OutputIndex { index }` directly | **YES** — mint redeemer builder |

### PR #69 — Finding 13 (`ebd9ffa`) — no schema change

- Tx shape: under `ThirdPartyAct`, paired continuation outputs must
  **preserve `reference_script`** (in addition to address and datum).
  3P transaction builders must copy the field. Hash-cascade only
  otherwise.

### PR #70 — Finding 19 (`11d74f0`) — no schema change

- Internal redundant length/ordering checks removed from
  `RegistryInsert` (relaxation; no off-chain action). Hash cascade.

### PR #77 — Finding 02 (`a5ed95c`) — no schema change

- Pure mints (mint without spending PLB inputs) are **no longer subject
  to transfer-logic enforcement** under `TransferAct`. Relaxation:
  pure-mint txs no longer need the substandard transfer-logic
  withdrawal. Hash cascade.

### Re-audit R-06 — `RegistryInsert` mode removal (working tree, no PR yet) — PROVISIONAL

| Surface | Change | Breaking? |
|---|---|---|
| `registry_mint` redeemer | `RegistryInsert { key, minting_logic_script, mode }` → `RegistryInsert { key, minting_logic_script }`; type `RegistrationMode` (`RegisterOnly \| RegisterAndMint`) **deleted** | **YES** — redeemer builder (reverts the `mode` half of #52's reshape) |
| Tx shape | None — both flows (register-only and register-and-mint) remain valid; `registry_mint` simply no longer asserts `mode` against `tx.mint` (relaxation) | No |

Rationale: the mode was caller-selected, so the mode ↔ `tx.mint`
consistency check enforced no invariant (R-06). The proof-of-instance
withdrawal (substandard's `minting_logic_script` withdraw-0) remains
required in both flows. Hash cascade as usual.

### Upgradability in place — changes #1+#2 (`feat/upgradability-in-place`, working tree) — PROVISIONAL

| Surface | Change | Breaking? |
|---|---|---|
| `programmable_logic_base` params | Parameter changed from `stake_cred: Credential` (PLG's credential) to `params_policy: PolicyId` (protocol-params NFT policy) | **YES** — parameter application type/value; PLB hash no longer depends on PLG's hash |
| Protocol-params datum (`ProgrammableLogicGlobalParams`) | **Appended field 3 `prog_logic_global_cred: Credential`** → now `{ registry_node_cs, prog_logic_cred, unfracking_cred, prog_logic_global_cred }` (4 fields) | **YES** — params-datum builder (deploy) and any parser |
| Tx shape | Every PLB spend now requires the protocol-params NFT as a **reference input** (previously only PLG required it — same txs, so no practical builder change) | No (already mandatory via PLG) |
| Deployment order | PLB is parameterised by the params NFT policy instead of PLG's credential: PLB can now be built **before** PLG; PLG's credential is written into the params datum at mint time | Deploy-pipeline change |

Rationale (AL call 2026-07-20): PLG becomes swappable in place — an
upgrade rewrites `prog_logic_global_cred` in the coordination UTxO
datum instead of redeploying PLB (whose hash anchors every programmable
token address). Cost impact recorded in `UPGRADABILITY_BENCHMARKS.md`
(~+26.6k mem / +8.6M cpu per PLB input).

### Upgradability in place — change #3 (trampoline 2, working tree) — PROVISIONAL

| Surface | Change | Breaking? |
|---|---|---|
| Protocol-params datum (`ProgrammableLogicGlobalParams`) | **Appended field 4 `upgrade_logic_cred: Credential`** → now 5 fields `{ registry_node_cs, prog_logic_cred, unfracking_cred, prog_logic_global_cred, upgrade_logic_cred }` | **YES** — params-datum builder (deploy) and any parser |
| Validator set | **New `coordination_spend`** (spend; param `nonce: ByteArray`) — replaces the always-fail lock as the coordination-UTxO spender | **YES** — new deploy artefact; NFT lock target moves here |
| Validator set | **New `upgrade_multisig`** (withdraw + publish; params `signers: List<VerificationKeyHash>, threshold: Int`) — reference upgrade authority, the initial `upgrade_logic_cred` target | Additive (a substandard-style deploy artefact; swappable) |
| `protocol_params_mint` | **No code change**; at deploy, lock target parameter is passed `coordination_spend`'s hash instead of always-fail (param still named `always_fail_hash`) | Deploy-wiring change |
| Tx shape | Upgrade tx: spend the coordination UTxO → one continuing output, same address, exact same value (NFT + ADA), inline well-formed datum, `prog_logic_cred`+`registry_node_cs` unchanged, carry `upgrade_logic_cred` withdraw-0 | New capability (upgrades) |

Hot path unaffected: field 4 is append-last, PLB reads field 3 →
benches byte-identical to #1+#2. `coordination_spend` is cold-path
(upgrade txs only): ~184k mem / ~66M cpu. Remaining: #4 lock-target
deploy wiring; authority model (multisig composition / GA handover) is a
committee decision (decision-doc-in-place-upgradability.md).

---

### Upgradability in place — PLG split (`feat/plg-third-party-split`, PR vs `feat/upgradability-in-place`) — PROVISIONAL

Third-party (seize/clawback) logic pulled out of `programmable_logic_global`
into a standalone validator; `programmable_logic_base` becomes a dispatcher.

| Surface | Change | Breaking? |
|---|---|---|
| Validator set | **New `third_party`** (withdraw + publish; param `params_policy: PolicyId`) — hosts `validate_3rd_party`; new deploy artefact + reference script | **YES** — new deploy artefact; seize txs invoke it instead of PLG |
| `programmable_logic_base.spend` redeemer | `Int` (params index, §16) → **`BaseSpendRedeemer { SpendViaGlobal { params_idx, wdrl_idx } \| SpendViaThirdParty { params_idx, wdrl_idx } }`** — picks the delegate + witnesses its withdrawal index (O(1), no scan) | **YES** — every PLB spend redeemer builder |
| `ProgrammableLogicGlobalRedeemer` | **`ThirdPartyAct` constructor removed** → `TransferAct \| UnfrackingAct`; `UnfrackingAct` constr index 2 → 1 | **YES** — PLG redeemer builders; third-party now uses `third_party`'s `ThirdPartyRedeemer` (same 3 fields) |
| Protocol-params datum (`ProgrammableLogicGlobalParams`) | **Appended field 5 `third_party_cred: Credential`** → now 6 fields; read by PLB on `SpendViaThirdParty`; `coordination_spend` 28-byte-guards it | **YES** — params-datum builder (deploy) and any parser |
| `issuance_mint` | **No param/redeemer change**; mint-custody delegation now also accepts coverage from the `third_party` validator's `ThirdPartyRedeemer` (same-registry-node), not only PLG's `TransferAct` | Semantic (delegation recognises the new validator) |
| Tx shape | Seize tx: PLB spend uses `SpendViaThirdParty`; invoke `third_party` withdraw-0 (+ its ref script) instead of PLG; carry `ThirdPartyRedeemer` at `third_party_cred`; issuer's `third_party_transfer_logic_script` withdrawal still required | Reshaped seize tx |

Reference-script footprint per tx (measured): transfer `PLB+PLG` 3659 →
3072 B (**−587**), seize `PLB+third_party` 3659 → 2565 B (**−1094**); PLG
3163 → 2313 B (−27%). Execution ~neutral (PLB 2-arm dispatch, reclaimed
by the O(1) withdrawal lookup off-first-position). Off-chain: SDK
(`cip113-sdk-ts`) + Java backend need the new PLB sum-type redeemer,
`third_party` deploy, and `wdrl_idx`/`params_idx` derivation — tracked
separately.

---

## Open PRs — PROVISIONAL, subject to change

> NOTE: four PRs are currently open (#78, #79, #80, #81), not three —
> confirm whether all four are in scope.

### PR #78 — Finding 17, Unfracking (`fix/finding-17-unfracking`)

| Surface | Change | Breaking? |
|---|---|---|
| Validator set | **New validator `unfracking`** (withdraw-0 + publish), blueprint title `unfracking.unfracking.withdraw`, parameter `params_policy: PolicyId`. Must be deployed as a reference script and its stake credential registered | **YES** — new deploy artefact + blueprint lookup key |
| `programmable_logic_global` redeemer | `ProgrammableLogicGlobalRedeemer` gains **`UnfrackingAct`** (constructor index 2, no fields) | Additive (existing TransferAct/ThirdPartyAct builders unaffected) |
| Protocol-params datum (`ProgrammableLogicGlobalParams`, built off-chain at deploy) | **Appended field 2 `unfracking_cred: Credential`** → now `{ registry_node_cs, prog_logic_cred, unfracking_cred }` (3 fields) | **YES** — params-datum builder (deploy) and any parser |
| Tx shape | New unfracking tx pattern: PLB inputs same stake cred; withdrawals = PLG (`UnfrackingAct`) + `unfracking` script + holder authorisation; no mint; per-policy PLB conservation | Additive feature |

### PR #79 — Finding 12 (`fix/finding-12-utxo-contamination`) — no schema change

- `validate_3rd_party` semantics tightened to prevent UTxO
  contamination; constrains 3P output construction further. 3P builders
  must be re-validated against the merged rules. Hash cascade.

### PR #80 — Finding 04 (`feat/finding-04-issuance-mint-precise-delegation`) — no schema change

- `issuance_mint` delegation scope made precise per redeemer; changes
  which transaction shapes validate for mints (notably mint-during-3P
  combinations). Mint builders must be re-validated. Hash cascade
  (including new `IssuanceCborHex` prefix/postfix bytes).

### PR #81 — Finding 20 / issue #75 (`feat/75-registry-design-limitation`) — no schema change

- `registry_spend` gains a **no-mint update path**: a registry node's
  fields can be updated in place (key/next immutable, address + NFT
  preserved, enforced via `is_field_updated_registry_node`), authorised
  by the node's `minting_logic_script` (withdraw-0 invocation, or
  signature if vkey). New additive tx pattern: "update registry node".
  Redeemer remains untyped.

---

## Consolidated surface: baseline → main + open PRs

| Validator | Params (baseline → now) | Redeemer (baseline → now) | Changed by |
|---|---|---|---|
| `issuance_mint` | 3 → **4** (+`plg_stake_cred`) | `SmartTokenMintingAction{...}` → **`MintingRegistryProof`** | #51, #68 (+semantics #80) |
| `registry_mint` | 2 → **3** (+`registry_spend_cred`) | `RegistryInsert` fields **replaced** (`hashed_param` → `minting_logic_script`; `mode` added by #52, removed by R-06) | #51, #52, R-06 |
| `registry_spend` | 1 (unchanged) | untyped (unchanged) | #81 semantics only |
| `programmable_logic_global` | 1 (unchanged — went 1→2→1 during #78 development; final is 1) | +`UnfrackingAct` | #78 |
| `programmable_logic_base` | 1 (unchanged) | untyped (unchanged) | hash cascade only |
| `protocol_params_mint` | 2 (unchanged) | untyped (unchanged) | datum it mints changed (#78) |
| `issuance_cbor_hex_mint` | 2 (unchanged) | untyped (unchanged) | its datum content (template bytes) changes with every `issuance_mint` change |
| `unfracking` | — → **new** (1 param) | untyped | #78 |
| `always_fail` | unchanged | — | — |

Off-chain-built datums:

| Datum | Baseline → now | Changed by |
|---|---|---|
| `RegistryNode` (registry NFT) | 5 → **6 fields** (`minting_logic_script` inserted at index 2) | #52 |
| `ProgrammableLogicGlobalParams` (params NFT) | 2 → **3 fields** (`unfracking_cred` appended) | #78 (provisional) |
| `IssuanceCborHex` | shape unchanged; **content** (prefix/postfix bytes) changes with every issuance_mint change | #51, #68, #80 |

---

## SDK impact map (`cip113-sdk-ts`)

Observed touchpoints (grep, 2026-06-11) — each is a migration checklist
item once the open PRs land:

- `src/standard/blueprint.ts` — resolves validators **by title**; must
  add the `unfracking.unfracking` title (#78). Verify param-application
  arity for `issuance_mint` (4) and `registry_mint` (3) (#51).
- `src/core/evo-utils.ts` — `RegistryNode` datum builder: **already on
  the 6-field post-#52 shape** (verified: `minting_logic_script` at
  index 2). Needs the 3-field `ProgrammableLogicGlobalParams` parser /
  builder if it touches the params datum (#78).
- `src/core/registry.ts` — `RegistryInsert` redeemer: verify
  `minting_logic_script` support (#52) and that no `mode` field is
  encoded (R-06 removed it); verify mint redeemer is bare
  `MintingRegistryProof` (#68).
- `src/substandards/*` (`freeze-and-seize` especially) — `ThirdPartyAct`
  builders: must preserve `reference_script` on paired outputs (#69)
  and be re-validated against #79's contamination rules and #80's
  issuance scope.
- New (optional) feature: unfracking tx builder (#78) — PLG
  `UnfrackingAct` redeemer (constr index 2), `unfracking` script
  withdrawal + ref script, composition documented in
  `documentation/design/finding-17-unfracking-w0-delegation.md`.

Other consumers to migrate in the same pass: the Java backend
(`programmable-tokens-offchain-java`) receives `plutus.json` via
`build.sh` and builds the params datum at deploy time (3-field change,
#78) and applies validator parameters (#51 arity changes).

## Maintenance

When a new PR lands on `main` (or an open PR's surface changes), rerun
the comparison: extract titles/params/redeemers from `plutus.json` at
the new merge commit, diff against the previous merge, and append a
section here. The extraction script used for this document is kept at
`.claude/scripts/blueprint-surface.py` (usage:
`python3 .claude/scripts/blueprint-surface.py <commit-or-ref>`); it
normalises a blueprint into comparable per-validator signatures —
diff two outputs to see the surface delta.
