# CIP-113 Programmable Tokens — Audit-Era API Changes

A reference for off-chain integrators (transaction builders, indexers,
custodial software, wallet teams) covering every breaking change to the public
on-chain surface between the pre-audit baseline and current `main`.

If your code reads or writes any of:

- Validator script parameters
- Redeemer types
- Datum types
- Validator script bytecode (because any parameter change shifts the policy id
  / script hash, and hence every address derived from it)

…then this document tells you what changed and how to update.

---

## Baseline and scope

| | Commit | Date | Description |
|---|---|---|---|
| **Pre-audit baseline** | `8143853` | 2026-04-28 | "chore: removed unwanted build script" — last commit before audit findings started landing |
| **Current `main`** | `ebd9ffa` | 2026-05-26 | "chore: added ref script validation (#69)" — latest at time of writing |

Four PRs land between them:

```
0a04cc2 Fix audit findings 3, 8 and 9 (#51)
2f6cd90 feat(registry): Separation of Concerns — Register / Register-and-Mint (#52)
1687209 chore: flattened and updated find in issuance (#68)
ebd9ffa chore: added ref script validation (#69)
```

Validators with **no public-surface changes** in this window (no off-chain
impact):

- `programmable_logic_global.ak`
- `programmable_logic_base.ak`
- `programmable_logic/transfer.ak` *(internal refactor only)*
- `registry_spend.ak`
- `protocol_params_mint.ak`
- `issuance_cbor_hex_mint.ak`
- `always_fail.ak`

The rest of this document walks through the components that did change.

---

## TL;DR — action items for integrators

| Area | Action |
|---|---|
| `registry_mint` parameters | **Add** a 3rd parameter `registry_spend_cred: Credential` when applying parameters. Your registry-mint policy id will change. |
| `registry_mint.RegistryInsert` redeemer | **Reshape**: `{key, hashed_param}` → `{key, minting_logic_script, mode}`. Drop `hashed_param`; supply the substandard's `minting_logic_script` credential and a `mode` (`RegisterOnly` or `RegisterAndMint`). |
| `issuance_mint` parameters | **Add** a 4th parameter `plg_stake_cred: Credential` when applying parameters. Your programmable-token policy ids will change. |
| `issuance_mint.mint` redeemer | **Simplify**: was `SmartTokenMintingAction { minting_logic_cred, minting_registry_proof }`, now just `MintingRegistryProof` directly. The `minting_logic_cred` field is gone — it's baked into the validator's parameters. |
| `RegistryNode` datum | **Add** a new field `minting_logic_script: Credential` at position #3 (after `key` and `next`). Datum CBOR shape changed. |
| `RegistryInsert` withdrawal requirement | The substandard's withdraw-0 (`minting_logic_script` credential) **must** appear in `tx.withdrawals`, even for `RegisterOnly` mode. |
| `issuance_mint` delegation signal | `issuance_mint` now consults `tx.withdrawals` (looking for `plg_stake_cred`), not `tx.inputs` (looking for PLB spends), to decide whether to delegate output-custody to PLGlobal. |
| `ThirdPartyAct` continuing outputs | Must now preserve `reference_script` of the paired input (in addition to address and datum). Tx builders that strip ref scripts on seize-style outputs will be rejected. |

A dedicated walkthrough of the new RegisterOnly vs RegisterAndMint flows is in
[§6](#6-registeronly-vs-registerandmint--flow-walkthrough).

---

## 1. `lib/types.ak` — redeemer / shared type changes

### 1.1 `SmartTokenMintingAction` — REMOVED

```aiken
// Before
pub type SmartTokenMintingAction {
  minting_logic_cred: Credential,
  minting_registry_proof: MintingRegistryProof,
}

// After
(removed)
```

The wrapper is gone. Its `minting_logic_cred` field was redundant in the
redeemer because the validator already carries it as a compile-time parameter
— passing it again per-transaction was both pointless and a place for callers
to lie. `MintingRegistryProof` is now used directly as the `issuance_mint.mint`
redeemer.

### 1.2 `MintingRegistryProof` — unchanged shape, new role

```aiken
pub type MintingRegistryProof {
  RefInput { index: Int }
  OutputIndex { index: Int }
}
```

Shape preserved; **now the top-level redeemer** for `issuance_mint.mint(...)`.

### 1.3 `RegistrationMode` — NEW

```aiken
pub type RegistrationMode {
  RegisterOnly
  RegisterAndMint
}
```

New tag selecting the registration flow shape. See [§6](#6-registeronly-vs-registerandmint--flow-walkthrough).

### 1.4 `RegistryRedeemer.RegistryInsert` — RESHAPED

```aiken
// Before
pub type RegistryRedeemer {
  RegistryInit
  RegistryInsert { key: ByteArray, hashed_param: ByteArray }
}

// After
pub type RegistryRedeemer {
  RegistryInit
  RegistryInsert {
    key: ByteArray,
    minting_logic_script: Credential,
    mode: RegistrationMode,
  }
}
```

Changes:

- **Dropped** `hashed_param: ByteArray`. The validator now derives the inner
  28-byte hash from `minting_logic_script` itself. Callers can no longer
  mis-supply it.
- **Added** `minting_logic_script: Credential` — the substandard's withdraw-0
  minting-logic credential that the new policy id is parameterised by. The
  validator cryptographically binds this to `key` via
  `is_programmable_token_id_valid` (audit Finding 3).
- **Added** `mode: RegistrationMode` — tells the validator whether to expect a
  mint of the new policy in the same transaction.

### 1.5 `IssuanceCborHex` — unchanged

Shape preserved.

---

## 2. `lib/registry_node.ak` — datum gained a field

`RegistryNode` (the inline datum of every registry linked-list UTxO) gained a
field at position **#3**, between `next` and `transfer_logic_script`.

```aiken
// Before
pub type RegistryNode {
  key: ByteArray,
  next: ByteArray,
  transfer_logic_script: Credential,
  third_party_transfer_logic_script: Credential,
  global_state_cs: ByteArray,
}

// After
pub type RegistryNode {
  key: ByteArray,
  next: ByteArray,
  minting_logic_script: Credential,   // NEW (position #3)
  transfer_logic_script: Credential,
  third_party_transfer_logic_script: Credential,
  global_state_cs: ByteArray,
}
```

Off-chain impact:

- Anyone constructing a `RegistryNode` datum CBOR must include the new field
  at index 2 (between `next` and `transfer_logic_script`).
- Anyone parsing legacy pre-audit registry UTxOs will need to handle both
  shapes during migration (no automatic ledger migration — new nodes are
  inserted with the new shape).
- `registry_mint` enforces that this field equals the `minting_logic_script`
  supplied in the `RegistryInsert` redeemer, and that both are cryptographically
  bound to `key`. The field cannot lie.

---

## 3. `validators/registry_mint.ak` — new parameter, reshaped redeemer

### 3.1 Script parameters

```aiken
// Before
validator registry_mint(
  utxo_ref: OutputReference,
  issuance_cbor_hex_cs: PolicyId,
) { ... }

// After
validator registry_mint(
  utxo_ref: OutputReference,
  issuance_cbor_hex_cs: PolicyId,
  registry_spend_cred: Credential,    // NEW (3rd parameter)
) { ... }
```

**Impact on off-chain code:**

- When applying parameters to the `registry_mint` blueprint, supply all three.
  Your registry policy id (and every registry NFT address) changes.
- `registry_spend_cred` should be the credential of the `registry_spend`
  validator that holds the linked-list UTxOs. It is consumed by
  `validate_directory_init` (audit Finding 3) to confirm the origin node lands
  at the right address at `RegistryInit`. By inductive reasoning every
  subsequently inserted node also lands at the same address (Insert binds new
  outputs' addresses to the covering input's address; the covering input is at
  `registry_spend_cred` by induction from Init).

### 3.2 `mint` handler signature

Unchanged in shape:

```aiken
mint(redeemer: RegistryRedeemer, policy_id: PolicyId, self: Transaction)
```

Only the `RegistryRedeemer.RegistryInsert` *variant* changed (see §1.4).

### 3.3 New required withdrawal at `RegistryInsert` time

The substandard's `minting_logic_script` credential (from the redeemer) **must**
appear as a withdraw-0 in `tx.withdrawals`.

This is the *proof of instance* check. It replaces the old indirect proof
(which came for free from `issuance_mint` running, because the old flow always
co-minted the first batch). It is required **in both modes** — and particularly
important in `RegisterOnly`, where `issuance_mint` is not invoked at all.

---

## 4. `validators/issuance_mint.ak` — new parameter, simplified redeemer, delegation-signal change

### 4.1 Script parameters

```aiken
// Before
validator issuance_mint(
  programmable_logic_base: Credential,
  registry_node_cs: PolicyId,
  minting_logic_cred: Credential,
) { ... }

// After
validator issuance_mint(
  programmable_logic_base: Credential,
  registry_node_cs: PolicyId,
  minting_logic_cred: Credential,
  plg_stake_cred: Credential,   // NEW (4th parameter)
) { ... }
```

**Impact on off-chain code:**

- When applying parameters to the `issuance_mint` blueprint, supply all four.
  Every programmable-token policy id derived from this template changes.
- `plg_stake_cred` should be the stake credential of `programmable_logic_global`.
  It is the new delegation signal — see §4.3.

### 4.2 `mint` handler redeemer simplified

```aiken
// Before
mint(
  redeemer: SmartTokenMintingAction,  // { minting_logic_cred, minting_registry_proof }
  own_policy: PolicyId,
  self: Transaction,
)

// After
mint(
  redeemer: MintingRegistryProof,     // RefInput | OutputIndex
  own_policy: PolicyId,
  self: Transaction,
)
```

Pass `MintingRegistryProof` directly:

- `RefInput { index: Int }` — for subsequent mints/burns of an already-registered
  policy. `index` points at the registry-node reference input.
- `OutputIndex { index: Int }` — for the first mint paired with registration in
  the same transaction (RegisterAndMint flow). `index` points at the
  registry-node *output* being created.

The old `minting_logic_cred` field is gone — the validator already knows its
parameter at compile time. Passing it in the redeemer was redundant.

### 4.3 Delegation signal: input-based → withdrawal-based (Finding 9)

`issuance_mint` decides whether to delegate its output-custody check to
PLGlobal. The way it makes that decision changed:

- **Before**: "does any input have payment credential ==
  `programmable_logic_base`?" — i.e., a PLB input was the delegation signal.
- **After**: "is PLGlobal's stake credential (`plg_stake_cred`) being invoked
  as a withdraw-0?" — direct delegation signal via withdrawals.

For typical tx builders this is transparent (PLGlobal is invoked via withdraw-0
in any tx that needs the transfer path). The difference matters at the corners:

- A pure-mint tx that incidentally spends an unrelated PLB UTxO **no longer**
  triggers delegation (which is correct — PLGlobal isn't validating anything
  about that mint).
- A tx that explicitly invokes PLGlobal **does** trigger delegation (which is
  also correct — PLGlobal is the validator vouching for the transfer).

This signal change applies only on the `RefInput` arm. The `OutputIndex` arm
(first-mint case) always validates output custody itself via
`validate_mint_outputs` — there is no delegation choice on first mints.

### 4.4 Removed redundant `single_mint_with_credential` check (Finding 10)

The pre-audit validator carried an explicit check that the redeemer's
credential matched the policy's mint redeemer (`single_mint_with_credential`).
That invariant is already implied by the per-policy redeemer scoping in
Plutus; the check was removed. **No off-chain impact.**

---

## 5. `validators/programmable_logic/third_party.ak` — additional invariant

`ThirdPartyAct` now enforces `output.reference_script == input.reference_script`
on the continuing PLB output, in addition to the existing address and datum
equality checks (audit Finding 13).

**Off-chain impact:** transaction builders that strip or replace reference
scripts on the continuing output of a seize-style action will now be rejected.

- If your input has no reference script, your continuing output must have no
  reference script.
- If your input has one, the continuing output must carry the same one.

No validator-signature change; this is an internal invariant added to
`check_seized_tokens`.

---

## 6. RegisterOnly vs RegisterAndMint — flow walkthrough

The `RegistrationMode` field introduced in `RegistryInsert` (§1.4) lets
integrators pick between two flow shapes. Both share the same registry-update
invariants; they differ in **whether `tx.mint` carries entries under the new
policy id** and **which validators run as a consequence**.

### 6.1 Invariants common to both modes

Regardless of mode, a `RegistryInsert` transaction must:

1. **Spend exactly one covering registry node** — the linked-list node whose
   `key < new_key < next`. `registry_mint` filters inputs by the registry NFT
   policy and asserts exactly one such input exists.
2. **Mint exactly one new registry NFT** under the registry policy, with asset
   name = `new_key`.
3. **Produce exactly two registry-node outputs** at the `registry_spend`
   address:
   - the *updated covering node* (its `next` repointed to `new_key`);
   - the *newly inserted node* with the linked-list invariants
     `covering.key < new_key < covering.next`.
4. **Include the substandard's `minting_logic_script` as a withdraw-0** in
   `tx.withdrawals`. *(This is the proof-of-instance check — required in both
   modes, see §3.3.)*
5. **Carry an `IssuanceCborHex` reference input** under `issuance_cbor_hex_cs`.
   The validator uses its `prefix_cbor_hex` and `postfix_cbor_hex` to verify
   `is_programmable_token_id_valid(new_key, prefix, postfix, minting_logic_script)`
   — the cryptographic binding between `new_key` and the credential being
   registered.
6. **Use a 28-byte `key`** (the validator asserts `bytearray.length(key) == 28`).

`registry_spend` runs (because the covering node is being consumed) and is
satisfied automatically: it requires exactly one positive-amount entry under
the registry NFT policy in `tx.mint`, which both modes produce.

### 6.2 RegisterOnly

| | |
|---|---|
| **Caller intent** | Reserve a policy id in the registry **without** minting any tokens of it yet. |
| **`tx.mint` for `new_key`** | Must contain **no entries**. Validator asserts `!mint_has_policy(tx.mint, new_key)`. |
| **`issuance_mint` invocation** | Not invoked. No tokens of `new_key` are minted, so the issuance policy never runs. |
| **PLGlobal involvement** | None — PLGlobal is not part of this flow. |
| **Use case** | Two-stage flow where a partner wants to publish the registry entry (claim the policy id slot, publish the substandard's credentials) and mint the first tokens in a *later* transaction using the `RefInput` redeemer of `issuance_mint`. Useful when registration and first-mint are performed by different signers, or when the registration must occur before the substandard is ready to mint. |

**Minimum withdrawals for a RegisterOnly transaction:**

```text
- minting_logic_script (the substandard's withdraw-0 — proof of instance)
```

### 6.3 RegisterAndMint

| | |
|---|---|
| **Caller intent** | Reserve the policy id **and** mint its first tokens atomically. This is the all-in-one flow that matches pre-audit behaviour. |
| **`tx.mint` for `new_key`** | Must contain entries. Validator asserts `mint_has_policy(tx.mint, new_key)`. |
| **`issuance_mint` invocation** | Required. Runs with redeemer `MintingRegistryProof.OutputIndex { index }` where `index` points at the new registry-node *output* being created. |
| **PLGlobal involvement** | **Not required by `issuance_mint`** for the first mint — the `OutputIndex` arm always validates output custody itself via `validate_mint_outputs` (mandates all minted tokens land at PLB). You may still invoke PLGlobal in the same transaction for unrelated reasons (e.g., transferring another already-registered token); doing so is harmless. |
| **Use case** | Standard "create a programmable token and issue the initial supply" — single atomic on-chain action. |

**Minimum withdrawals for a RegisterAndMint transaction:**

```text
- minting_logic_script (the substandard's withdraw-0 — proof of instance)
```

(PLGlobal not required; see the table row above.)

### 6.4 Mode ↔ mint consistency

The mode field is **asserted both directions** inside `registry_mint`:

```aiken
when mode is {
  RegisterOnly    -> !mint_has_policy(self.mint, key)
  RegisterAndMint -> mint_has_policy(self.mint, key)
}
```

Equivalently: you cannot

- Claim `RegisterOnly` but mint anyway (registration rejected), nor
- Claim `RegisterAndMint` but skip the mint (registration rejected).

This bidirectional check (audit Finding 7 — Separation of Concerns) prevents
the redeemer's stated intent from quietly diverging from the actual `tx.mint`
shape.

### 6.5 Off-chain decision tree

```text
Need to:
├─ Reserve a policy slot only (no first mint, yet)
│     → use RegisterOnly
│     → tx.mint has NO entries under new_key
│     → required withdrawals: [substandard's minting_logic_script]
│     → invoke registry_mint + the substandard's minting-logic withdraw-0
│     → issuance_mint is NOT invoked
│
└─ Reserve a policy slot AND mint the first batch in the same tx
      → use RegisterAndMint
      → tx.mint has entries under new_key
      → required withdrawals: [substandard's minting_logic_script]
      → invoke registry_mint + issuance_mint + substandard's withdraw-0
      → use MintingRegistryProof.OutputIndex { index } for issuance_mint
      → `index` points at the new registry-node output being created
      → first-mint tokens must land at PLB (validate_mint_outputs always runs
        on the OutputIndex arm; no PLGlobal delegation on first mints)

For SUBSEQUENT mints/burns of an already-registered policy
(i.e., NOT in the same tx as registration):
   → don't use registry_mint
   → use issuance_mint.mint with MintingRegistryProof.RefInput { index }
   → `index` points at the existing registry-node REFERENCE input
   → if PLGlobal is invoked in the same tx (e.g., you're also transferring),
     issuance_mint will delegate output-custody to it; otherwise issuance_mint
     validates custody itself
```

---

## 7. Audit findings referenced

| Finding | Title | Affected component |
|---|---|---|
| 3 | Registry init does not bind origin node to registry_spend | `registry_mint` parameters (new `registry_spend_cred`) |
| 7 | Separation of Concerns | new `RegistrationMode` enum, `RegistryInsert` reshape |
| 8 | Inefficient membership check | `registry_mint` internal |
| 9 | Indirect delegation signal | `issuance_mint` parameters (new `plg_stake_cred`) + withdrawal-based delegation |
| 10 | Redundant single-mint redeemer check | removed from `issuance_mint` |
| 13 | Reference script preservation in ThirdPartyAct | `third_party.ak` reference-script equality |

The findings themselves live under `audit/` in the repo. This document
captures the *resulting public-API surface* — refer to the audit text for
threat models and remediation rationale.

---

## 8. Migration checklist

When upgrading off-chain integration:

- [ ] Re-fetch the deployed blueprints from your backend — every policy id and
      address derived from `registry_mint` and `issuance_mint` has shifted
      because both validators gained a parameter.
- [ ] Update transaction builders that call `RegistryInsert`: replace
      `hashed_param` with `minting_logic_script` and add a `mode` field.
- [ ] Decide per call site whether you want `RegisterOnly` or
      `RegisterAndMint`. If you don't have a deferred-mint use case, pick
      `RegisterAndMint` to keep behaviour analogous to pre-audit.
- [ ] Update `RegistryNode` datum constructors to insert `minting_logic_script`
      at field position #3.
- [ ] Update parsers reading existing registry UTxOs to handle both pre- and
      post-audit datum shapes during the migration window.
- [ ] Update transaction builders that call `issuance_mint.mint`: pass
      `MintingRegistryProof` directly, not the old `SmartTokenMintingAction`
      wrapper.
- [ ] Where you previously included a PLB input purely as a delegation signal
      to `issuance_mint`, include the PLGlobal withdraw-0 explicitly instead.
      Stop adding extraneous PLB inputs for signalling.
- [ ] In `RegisterOnly` flows, include the substandard's `minting_logic_script`
      withdraw-0 even though no programmable tokens are being minted — the
      registry validator now requires it explicitly.
- [ ] If your tx builder uses the `ThirdPartyAct` path, ensure the continuing
      PLB outputs preserve the input's reference script verbatim.

---

## 9. Coming next (not yet in `main`)

The team is preparing a fix for **audit Finding 02** (transfer-logic
enforcement contradiction for purely-minted tokens) on a separate branch.
When it lands, additional off-chain consequences for `TransferAct` callers
will be documented in a follow-up update. The key forthcoming change:

- Pure-mint policies (in `tx.mint` but absent from any PLB input) will no
  longer be subjected to the transfer-logic enforcement or require a
  `TransferAct` proof.
- The strict 1-proof-per-input-policy contract will be preserved: callers
  must **not** supply a `TransferAct` proof for a pure-mint policy — doing so
  will be rejected as a surplus proof.

This document will be updated when that lands in `main`.

---

*This document tracks `main` at the time of writing. For the most current
surface, always cross-check the validator declarations in `validators/` and
type definitions in `lib/types.ak` / `lib/registry_node.ak`.*
