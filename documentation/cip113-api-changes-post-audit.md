# CIP-113 — Post-Audit API & Contract-Surface Changes

**Audience:** maintainers of the on-chain contracts, the Evolution SDK
(`cip113-sdk-ts`), and the platform (`cip113-programmable-tokens-platform`,
incl. the Java/Spring backend).

**Purpose:** one source of truth for every contract-surface change introduced by
the audit-fix work, plus an **actionable migration checklist** so updating the
SDK and the platform is mechanical.

**Target state:** the **`dev`** integration branch — `main` plus the two
remaining open audit PRs merged together:

| Branch / PR | Findings | Status |
|---|---|---|
| `main` | 02, 03, 04, 06, 07, 08, 09, 10, 12, 13, 19, 20 | merged |
| #82 `feat/control-and-admin-scope` | 01, 15, 16, **18** | open → merged into `dev` |
| #78 `fix/finding-17-unfracking` | **17** | open → merged into `dev` |

Items from #78/#82 are **PROVISIONAL** until those PRs merge to `main`, but they
are the shapes the SDK/platform should target. Baseline for "since" is `8143853`
(last pre-audit commit). Regenerate the mechanical diff with
`.claude/scripts/blueprint-surface.py <ref>`.

> **Systemic note — every merge re-hashes everything.** Any validator code
> change yields new script hashes, and the parameter chain cascades it
> everywhere (issuance template bytes → `IssuanceCborHex` → `registry_mint` →
> params datum → `programmable_logic_base`). So **every change below implies a
> full protocol redeployment** (new addresses, new `IssuanceCborHex`, new params
> NFT) even when marked "no schema change". The SDK/platform fetch the blueprint
> dynamically, so hashes flow through automatically — the break points are the
> **hand-coded datum/redeemer builders, parsers, and parameter arity/order**,
> plus the **transaction-shape** rules. Those are what this document lists.

---

## 1. TL;DR — the breaking changes

- **`RegistryNode` datum: 5 → 7 fields.** `minting_logic_script` inserted at
  index 2 (#52); `protected_prefixes` appended at index 6 (#82).
- **`ProgrammableLogicGlobalParams` datum: 2 → 3 fields.** `unfracking_cred`
  appended at index 2 (#78).
- **`ProgrammableLogicGlobalRedeemer`:** `ThirdPartyAct` simplified to
  `{ registry_node_idx, outputs_start_idx }`; new **`UnfrackingAct`**
  (constructor 2, no fields) (#78).
- **`registry_mint` redeemer:** `RegistryInsert` is now
  `{ key, minting_logic_script, mode }` (+ `RegistrationMode`) (#52).
- **`issuance_mint` redeemer:** the `SmartTokenMintingAction` wrapper is gone —
  the redeemer is bare `MintingRegistryProof = RefInput | OutputIndex` (#68).
- **Validator parameters:** `issuance_mint` 3 → **4** (+`plg_stake_cred`),
  `registry_mint` 2 → **3** (+`registry_spend_cred`) (#51).
- **New validator:** `unfracking` (`unfracking.unfracking.withdraw` + `publish`),
  1 parameter `params_policy: PolicyId` (#78).
- **New / changed transaction shapes:** ref-script preservation in
  `ThirdPartyAct` (#69); protected-prefix preservation + mandatory amount-change
  in `ThirdPartyAct` (#82); in-place registry-node update (#81); unfracking (#78);
  pure-mint transfer-logic relaxation (#77); precise issuance delegation (#80);
  UTxO-contamination guard (#79).
- **Everything re-hashes → full redeploy.**

---

## 2. Final contract surface (authoritative reference)

The current shapes on `dev`. **CBOR field order and constructor indices are
load-bearing** — builders/parsers are positional.

### 2.1 Datums (built/parsed off-chain)

**`RegistryNode`** — inline datum on each registry NFT. `Constr(0, [...])`,
**7 fields**:

| idx | field | type | notes |
|---|---|---|---|
| 0 | `key` | bytes | policy id of the registered token (origin = `#""`) |
| 1 | `next` | bytes | next key in lex order |
| 2 | `minting_logic_script` | Credential | **added #52**; substandard minting-logic cred, crypto-bound to `key` |
| 3 | `transfer_logic_script` | Credential | |
| 4 | `third_party_transfer_logic_script` | Credential | admin / seizure logic |
| 5 | `global_state_cs` | bytes | optional global-state policy id (`#""` = none) |
| 6 | `protected_prefixes` | List\<bytes\> | **added #82**; see rules below |

`protected_prefixes` rules (enforced on-chain at insert **and** update): each
entry is a **4-byte CIP-67 label prefix**, the list is **strictly ascending**
(sorted, no duplicates), and on update it is **append-only** (`new ⊇ old`).
`ThirdPartyAct` may not extract or burn tokens whose asset-name label prefix is
in this list. Typical entries: `000643b0` (label 100, CIP-68 reference NFT),
`001f4d70` (label 500, CIP-102 royalty).

**`ProgrammableLogicGlobalParams`** — inline datum on the protocol-params NFT.
`Constr(0, [...])`, **3 fields**:

| idx | field | type | notes |
|---|---|---|---|
| 0 | `registry_node_cs` | PolicyId (bytes) | |
| 1 | `prog_logic_cred` | Credential | programmable_logic_base payment cred |
| 2 | `unfracking_cred` | Credential | **added #78**; the `unfracking` validator's credential |

**`IssuanceCborHex`** — reference datum. Shape **unchanged**
(`Constr(0, [prefix_cbor_hex: bytes, postfix_cbor_hex: bytes])`) but its
**content changes with every `issuance_mint` code change** (#51/#68/#80) — must
be re-deployed each release.

### 2.2 Redeemers

**`ProgrammableLogicGlobalRedeemer`** (the PLG withdraw-0 redeemer):

| constr | variant | fields |
|---|---|---|
| 0 | `TransferAct` | `{ proofs: List<RegistryProof> }` |
| 1 | `ThirdPartyAct` | `{ registry_node_idx: Int, outputs_start_idx: Int }` |
| 2 | `UnfrackingAct` | _(none)_ — **added #78** |

`RegistryProof`: `TokenExists { node_idx: Int }` = `Constr(0,[int])`,
`TokenDoesNotExist { node_idx: Int }` = `Constr(1,[int])`.

**`RegistryRedeemer`** (registry_mint): `RegistryInit` = `Constr(0,[])`;
`RegistryInsert { key: bytes, minting_logic_script: Credential, mode }` =
`Constr(1,[bytes, Credential, RegistrationMode])`. `RegistrationMode`:
`RegisterOnly` = `Constr(0,[])`, `RegisterAndMint` = `Constr(1,[])`.

**`MintingRegistryProof`** (issuance_mint): `RefInput { index: Int }` =
`Constr(0,[int])`, `OutputIndex { index: Int }` = `Constr(1,[int])`. (The old
`SmartTokenMintingAction` wrapper was removed in #68.)

**`unfracking`**, **`registry_spend`**, **`programmable_logic_base`** redeemers
are untyped (`Data`).

### 2.3 Validators & parameters

| Validator | Blueprint title | Params (in order) |
|---|---|---|
| `always_fail` | `always_fail.always_fail.spend` | `nonce` |
| `protocol_params_mint` | `protocol_params_mint.…mint` | `utxo_ref`, `always_fail_hash` |
| `programmable_logic_global` | `programmable_logic_global.…withdraw` | `params_policy: PolicyId` |
| `programmable_logic_base` | `programmable_logic_base.…spend` | `stake_cred: Credential` (PLG) |
| `issuance_cbor_hex_mint` | `issuance_cbor_hex_mint.…mint` | `utxo_ref`, `always_fail_hash` |
| `registry_spend` | `registry_spend.…spend` | `protocol_params_cs: PolicyId` |
| `registry_mint` | `registry_mint.…mint` | `utxo_ref`, `issuance_cbor_hex_cs`, **`registry_spend_cred`** (3, #51) |
| `issuance_mint` | `issuance_mint.…mint` | `programmable_logic_base`, `registry_node_cs`, `minting_logic_cred`, **`plg_stake_cred`** (4, #51) |
| **`unfracking`** | **`unfracking.unfracking.withdraw`** / `.publish` | `params_policy: PolicyId` — **new #78** |

---

## 3. Change log by PR (why each change exists)

**Merged on `main`:**

- **#51 — Findings 03/08/09.** `issuance_mint` +`plg_stake_cred` (4th param);
  `registry_mint` +`registry_spend_cred` (3rd param); registry **origin node
  must be created at the `registry_spend` address** at Init.
- **#52 — Finding 07.** `RegistryInsert` redeemer reshaped to
  `{ key, minting_logic_script, mode }`; `RegistryNode` gains
  `minting_logic_script` at index 2; register-only flow added alongside
  register-and-mint.
- **#68 — Finding 10.** Issuance redeemer flattened to bare
  `MintingRegistryProof` (wrapper removed).
- **#69 — Finding 13.** `ThirdPartyAct` paired continuation outputs must
  preserve **`reference_script`** (in addition to address & datum).
- **#70 — Finding 19.** Redundant length/ordering checks dropped from
  `RegistryInsert` (relaxation; no off-chain action).
- **#77 — Finding 02.** Pure mints (no PLB inputs spent) are **no longer subject
  to transfer-logic enforcement** — pure-mint txs no longer need the substandard
  transfer-logic withdrawal.
- **#79 — Finding 12.** `validate_3rd_party` tightened against UTxO
  contamination — non-subject tokens conserved byte-for-byte per paired UTxO.
- **#80 — Finding 04.** Issuance delegation made precise per PLG redeemer
  (closes the mint-escape during ThirdPartyAct).
- **#81 — Finding 20.** `registry_spend` gains a **no-mint update path**: a
  node's mutable fields (`transfer_logic_script`,
  `third_party_transfer_logic_script`, `global_state_cs`, and growth of
  `protected_prefixes`) can be updated in place — `key`/`next`/
  `minting_logic_script` frozen; address + NFT preserved; authorised by the
  node's `minting_logic_script` withdraw-0. No de-registration.

**Merged into `dev` (open PRs):**

- **#82 — Findings 01/15/16/18.**
  - **F18 (code):** `RegistryNode.protected_prefixes` (above) + `ThirdPartyAct`
    "preserve, not fail" (protected labels can't be extracted/burned) + a
    re-introduced **mandatory amount-change** check (anti-DDoS: a third-party
    action must change the subject balance — no-op forced respends rejected).
  - **F01/F15/F16 (docs):** scope of programmable control (companion CIP-68/102
    assets stay in the PLB, substandard-handled, no escape); `ThirdPartyAct` is a
    general administrative/compliance action (forced transfer / seizure / freeze
    / burn), bounded by protected prefixes, freeze-vs-extract, holder-scope; one
    policy per `ThirdPartyAct` (won't-fix limitation); seizure is per-UTxO and
    fragmentation is not prevented.
- **#78 — Finding 17 (Unfracking).** New `unfracking` validator; PLG redeemer
  gains `UnfrackingAct`; params datum gains `unfracking_cred`. New tx pattern:
  holder-driven, same-owner PLB restructuring with **no mint**, per-policy value
  conservation, withdrawals = PLG (`UnfrackingAct`) + `unfracking` script +
  holder authorisation. (Integration note: `UnfrackingAct` never mints, so
  `issuance_mint.plgl_scope_covers` returns `False` for it — issuance validates
  its own outputs.)

---

## 4. Migration — Evolution SDK (`cip113-sdk-ts`)

The SDK is positional/CBOR-coupled. Checklist (file paths verified):

| # | Change | Where in the SDK | Action |
|---|---|---|---|
| 1 | `RegistryNode` 6 → **7 fields** (`protected_prefixes` @6) | `src/core/evo-utils.ts` (`RegistryNodeData`, `registryNodeDatum`, ~L220–261); field extractors in `src/substandards/freeze-and-seize/index.ts` (~L340–351) and `src/substandards/bafin/index.ts` (~L727–735) | Add `protectedPrefixes: HexString[]` to the model; append `Data.list(...)` at index 6 in the builder; keep extractors reading 0–5 unchanged (append-only field at the end) |
| 2 | New **`ProgrammableLogicGlobalParams`** 3-field datum (`unfracking_cred`) | not currently modeled in the SDK | Add a params-datum parser/builder: `Constr(0, [registry_node_cs, prog_logic_cred, unfracking_cred])` |
| 3 | New **`UnfrackingAct`** redeemer (constr 2) + `unfracking` validator | `src/core/evo-utils.ts` (redeemer builders); `src/standard/blueprint.ts` (`STANDARD_VALIDATORS`); `src/standard/scripts.ts` (param graph) | Add `unfrackingActRedeemer()` = `Constr(2, [])`; add title `unfracking.unfracking.withdraw`; parameterize `unfracking(params_policy)`; build the unfracking tx (PLG `UnfrackingAct` + `unfracking` ref-script withdrawal + holder auth) |
| 4 | `ThirdPartyAct` builder — protected prefixes + must-change + ref-script | `thirdPartyActRedeemer` (`src/core/evo-utils.ts` ~L313); callers in `src/substandards/freeze-and-seize/index.ts` (~L581) | Redeemer shape unchanged (`{registry_node_idx, outputs_start_idx}`), but builders must: preserve `reference_script` on paired outputs (#69), leave protected-prefix tokens byte-equal (#82), and ensure the seized amount actually changes (#82 anti-DDoS) |
| 5 | Confirm already-applied deltas | `src/core/evo-utils.ts`, `src/core/registry.ts`, `src/standard/scripts.ts` | Verify: `RegistryNode` minting_logic @2 (#52, already done); `RegistryInsert {key, minting_logic_script, mode}` (#52); bare `MintingRegistryProof` (#68); `issuance_mint` 4 params + `registry_mint` 3 params (#51) |
| 6 | Blueprint hashes | `src/standard/blueprint.ts` | If fetched from the backend API, hashes flow automatically; if any blueprint is vendored, refresh it from the `dev` build |

## 5. Migration — platform (`cip113-programmable-tokens-platform` + Java backend)

The Java backend currently lags the merged surface — it still models the
**pre-#52 5-field `RegistryNode`** and the **2-field params datum**. It needs to
catch up to 7 / 3 fields. Checklist (by component; confirm exact paths in the
platform repo):

| # | Change | Component | Action |
|---|---|---|---|
| 1 | `RegistryNode` 5 → **7 fields** | `RegistryNodeParser`, `RegistryNode` model + `toPlutusData()`, `RegistryNodeEntity` (DB) | Insert `mintingLogicScript` at index **2** (catch up to #52) **and** `protectedPrefixes: List<bytes>` at index **6** (#82); shift transfer→3, third_party→4, global_state→5; add DB columns + migration |
| 2 | `ProgrammableLogicGlobalParams` 2 → **3 fields** | `ProtocolParamsEntity`, params-datum builder, bootstrap/deploy | Add `unfrackingCred` at index 2; build the 3-field datum at deploy (#78) |
| 3 | New `unfracking` validator | bootstrap / parameterization service | Resolve `unfracking.unfracking.withdraw` from blueprint, apply `params_policy`, deploy as reference script, register its stake credential |
| 4 | `UnfrackingAct` redeemer | tx-builder layer | Add `Constr(2, [])`; build the unfracking tx shape |
| 5 | `ThirdPartyAct` tx-builders | seize/third-party builder service | Preserve `reference_script` on paired outputs (#69); preserve protected-prefix tokens (#82); ensure subject amount changes (#82) |
| 6 | Validator parameter arity | parameterization service (`applyParamToScript`) | `issuance_mint` 4 params, `registry_mint` 3 params (#51) — positional, order in §2.3 |
| 7 | Registry resync endpoint | the util/admin endpoint that parses `RegistryNode` datums | Will fail on 7-field datums until the parser is updated (item 1) |

> The Next.js frontend reads registry/params data via the backend API, so it
> mostly inherits the backend changes — but any place it renders or constructs
> `RegistryNode` / params fields needs the new fields.

---

## 6. Deployment

Because every change re-hashes the whole protocol, a release is a **full
redeploy**: rebuild `plutus.json`, re-bootstrap protocol params (new params NFT
with the 3-field datum), re-deploy `IssuanceCborHex` (new template bytes), and
publish the new reference scripts (incl. `unfracking`). Consumers that fetch the
blueprint/addresses dynamically pick up hashes automatically; hand-coded
datum/redeemer/parameter builders are the only manual break points (§4–§5).

## 7. Provenance

- Generated from the `dev` integration branch (`main` + #82 + #78). aiken check:
  274/274.
- Mechanical surface diff tool: `.claude/scripts/blueprint-surface.py <ref>`
  (normalises `plutus.json` into per-validator signatures; diff two refs).
- When a PR lands on `main`, re-run the tool against the new merge and update §2–§3.
</content>
