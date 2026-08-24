<!--
DOC-KIND: migration-guide
AUDIENCE: substandard implementors upgrading an EXISTING pre-audit substandard to post-audit main
FORMAT: agentic-first (stable anchors, before→after tables, code anchors, verifiable checklists) — also human-readable
BASELINE: 8143853 (pre-audit, 2026-04-28)
TARGET:   3a6d8d6 (main, 2026-07-16) + re-audit R-01..R-05
COMPANION: cip113-api-changes-post-audit.md  (the field-level API/CBOR surface; this doc is the conceptual/behavioural layer)
CANONICAL-SOURCE: the validators in validators/ and types in lib/ always win over this doc; every claim below is anchored to file:symbol
-->

# CIP-113 Substandard Upgrade Guide (pre-audit → post-audit)

This document is for one specific reader: **an implementor who already built a
CIP-113 substandard against the pre-audit framework and now needs to upgrade it
to current `main`.** It is the *conceptual/behavioural* companion to
[`cip113-api-changes-post-audit.md`](./cip113-api-changes-post-audit.md), which
carries the exact field-level / CBOR surface. Read this one to understand *what
changed in meaning and what you must do about it*; read that one for the exact
types, parameters, and redeemer shapes.

It also serves as a fast orientation for a *new* substandard author — the mental
models in §1 are the framework's current contract, not just a diff.

---

## 0. How to use this document

**If you are an agent** performing or planning the upgrade:

- Treat §2 (LOUD vs SILENT breakage) as the triage table: every behavioural
  change is classified by whether it fails a transaction *loudly* (you will see
  a script error) or drifts *silently* (the transaction succeeds but does the
  wrong thing). Silent items are the ones a diff/test sweep will miss — prioritise
  them.
- Each upgrade step in §3 is written as `WHAT CHANGED → WHY → WHAT YOU MUST DO →
  HOW TO VERIFY`. The VERIFY line is a concrete, checkable condition.
- Anchors of the form `file:symbol` (e.g. `lib/registry_node.ak:RegistryNode`)
  point at the authoritative source. When this doc and the source disagree, the
  source is correct — open an issue.
- The §5 checklist is the definition of done.

**If you are a human**: read §1 for the model, skim §2 to see what will break,
work §3 top-to-bottom, tick §5.

---

## 1. The six mental-model shifts

These are the conceptual changes. Everything in §3 follows from one of them.

### 1.1 Registration is now decoupled from issuance

Pre-audit, creating a programmable token and minting its first supply were one
inseparable act. Post-audit they are **two distinct capabilities** that a
transaction may combine or separate:

- **Registration** inserts a `RegistryNode` into the on-chain registry
  (linked list), reserving the policy id and publishing the substandard's
  script credentials. Redeemer: `registry_mint.RegistryInsert`.
- **Issuance** mints/burns tokens of an already-registered policy. Redeemer:
  `issuance_mint.mint` with `MintingRegistryProof`.

A registration transaction may take either shape — there is no redeemer tag
selecting between them, and `registry_mint` does not inspect the first-mint
entries under the new key at all:

- **Register only** — reserve the slot now, mint later (or never in this tx).
  `tx.mint` carries no entries under the new policy.
- **Register and mint** — register and mint the first batch atomically (this is
  the pre-audit behaviour). The first mint triggers `issuance_mint`, which
  validates it as usual.

**Why your substandard cares:** if your substandard relied on "register implies
mint", that assumption is gone. A supply-aware substandard can now initialise
its global state at registration time *before any token exists*; an RWA-style
substandard can reserve the policy id and defer issuance. Critically, your
`minting_logic_script` withdraw-0 must run **in both shapes** (proof of
instance), even when nothing is minted. And because the base layer does not
constrain the shape, **enforcing a strict register-then-mint lifecycle is your
job**: if your policy forbids minting during registration, your minting logic
must reject it itself. See §3.2.

### 1.2 The registry node is *the* binding between your scripts and the policy id

Pre-audit there was no first-class, on-chain object tying a policy id to the
scripts that govern it. Post-audit, `lib/registry_node.ak:RegistryNode` is that
object and is the single source of truth for a policy:

```
RegistryNode {
  key                                : ByteArray    -- the policy id this node governs
  next                               : ByteArray    -- linked-list successor
  minting_logic_script               : Credential   -- your issuance withdraw-0
  transfer_logic_script              : Credential   -- your transfer withdraw-0
  third_party_transfer_logic_script  : Credential   -- your admin/seizure withdraw-0
  global_state_cs                    : ByteArray     -- optional global-state policy (28B or empty)
  protected_prefixes                 : List<ByteArray> -- CIP-67 labels the admin can't touch
}
```

The framework **cryptographically binds `key` to `minting_logic_script`**: the
issuance template parameterised with your minting-logic credential must hash to
`key` (`registry_mint` via `is_programmable_token_id_valid`), and the registry
NFT's asset name equals `key`. You cannot register a node whose datum lies about
which scripts govern the policy.

**Why your substandard cares:** the node is now the integration point. Anything
that needs to know "which transfer logic governs policy X?" reads it from the
node — at build time, freshly. Do not hardcode the mapping.

### 1.3 Registry nodes are UPGRADABLE (and that changes token semantics after mint)

This is the highest-impact and most subtle change. A registered node's
*governance fields* can be changed after holders already hold the token, by
re-spending the node UTxO through `validators/registry_spend.ak`
(`is_field_updated_registry_node` in `lib/linked_list.ak` defines the rules):

| Field | Mutable? | Notes |
|---|---|---|
| `key` | **No** | Immutable — the policy identity. |
| `next` | **No** (via update) | Only re-linked by insert, never by update. |
| `minting_logic_script` | **No** | Immutable — it is bound to `key`; changing it would break the binding. |
| `transfer_logic_script` | **Yes** | The rules governing ordinary transfers can change. |
| `third_party_transfer_logic_script` | **Yes** | The admin/seizure rules can change. |
| `global_state_cs` | **Yes** | 28-byte credential or empty. |
| `protected_prefixes` | **Yes, APPEND-ONLY** | May add CIP-67 labels; may never drop one. Protection cannot be revoked. |

Authority to update is **the `minting_logic_script` itself**: the update is only
valid if `minting_logic_script` is a `Script` credential *and* its withdraw-0 is
invoked in the update transaction (`registry_spend.ak`). A `VerificationKey`
minting logic can never update — updates are script-gated by construction.

**Why your substandard cares — two consequences:**

1. **You gained an upgrade lever.** Your minting-logic script *is* your
   governance mechanism. If you want your token's transfer or admin rules to be
   changeable (e.g. rotate a compliance provider, tighten seizure rules), encode
   that policy in your minting-logic withdraw-0 — it is the gatekeeper of node
   updates. If you want them *immutable*, make your minting-logic script refuse
   all node-update transactions (or make it a verification key).
2. **Every integrator must treat governance fields as live, not frozen.** A
   holder who cached "policy X uses transfer logic L" at mint time can have that
   silently invalidated by a later update. This is the marquee SILENT breakage
   (§2). The rule for everyone downstream: **resolve the node fresh at
   transaction-build time; never cache transfer/third-party/global-state creds
   as immutable.**

### 1.4 The admin path has a defined, bounded custody scope

> **Superseded on `feat/upgradability-in-place`** by the validator split — see
> `cip113-api-changes-post-audit.md` §17. The third-party path is no longer a
> `programmable_logic_global` redeemer arm; it is the **standalone `third_party`
> validator** (redeemer `ThirdPartyRedeemer { params_idx, registry_node_idx,
> outputs_start_idx }`), dispatched by `programmable_logic_base` via
> `SpendViaThirdParty`. (`programmable_logic_global` itself is renamed
> **`transfer`**, redeemer `TransferRedeemer`, and handles transfers only.) The
> custody guarantees below are unchanged — only the validator that hosts them
> and the redeemer that carries the action moved.

Pre-audit, the third-party/seizure path was under-specified. It is now a
first-class action with structural guarantees the base layer enforces regardless
of your substandard (`validators/programmable_logic/third_party.ak`):

- Your `third_party_transfer_logic_script` MUST be invoked (withdraw-0) — the
  admin cannot act without your logic authorising it.
- Each spent PLB UTxO is paired 1:1 with a continuing output that preserves
  **address, datum, and reference script** byte-for-byte (Finding 13).
- The paired input MUST already hold the subject policy — no injecting a policy
  onto an innocent UTxO (Finding 12).
- Non-subject policies are conserved per pair, byte-for-byte.
- The subject total across all outputs reconciles against `tx.mint`; nothing
  escapes the PLB.
- Exactly **one policy per `ThirdPartyAct`** transaction (Finding 15) — batch a
  multi-policy seizure as sequential transactions.

**Why your substandard cares:** your third-party logic decides *whether* an
action is authorised; the framework guarantees *what shape* it can take. You no
longer have to (and cannot) re-implement custody preservation — but you also
cannot exceed this scope. See §1.5 for what you can carve out of it.

### 1.5 Companion assets stay inside the PLB — and you protect them with prefixes

The framework never lets a registered policy's tokens leave the PLB (no
carve-out). Companion assets (CIP-68 reference NFTs label 100, CIP-102 royalty
tokens label 500) therefore live *inside* the PLB under the same policy, and you
shield them from admin seizure via `protected_prefixes` on the node:

`ThirdPartyAct` may **not extract or burn** any token whose CIP-67 asset-name
label prefix is on `protected_prefixes` — on each pair those tokens must be
byte-equal across input and output ("preserve, not fail":
`third_party.ak:protected_subset`). The unprotected remainder is still fully
seizable.

**Why your substandard cares:** if your token has CIP-68/102 companion assets,
declaring their label prefixes as protected is now *your* responsibility at
registration (and you can only ever *add* more later — §1.3). Metadata/royalty
management itself is out of framework scope and lives in your
CIP-68/102-aware minting/transfer logic. See
[`03-CONTROL-SCOPE-AND-ADMIN-AUTHORITY.md`](./03-CONTROL-SCOPE-AND-ADMIN-AUTHORITY.md).

### 1.6 Holders can restructure their own UTxOs (Unfracking)

> **Superseded on `feat/upgradability-in-place`** by the validator split — see
> `cip113-api-changes-post-audit.md` §17. There is no `UnfrackingAct` any more:
> `programmable_logic_base` dispatches straight to the `unfracking` validator
> via `SpendViaUnfracking`, and the transfer validator is not part of an
> unfracking transaction at all. Everything below about *what* unfracking does
> and why your substandard cares still holds.

New action `ProgrammableLogicGlobalRedeemer.UnfrackingAct` (Finding 17) lets a
holder redistribute the programmable tokens they already hold across their own
PLB UTxOs — value-preserving, same-owner, **no substandard logic invoked**. Its
purpose is to split multi-policy UTxOs into single-policy UTxOs, so a freeze on
one policy cannot collaterally freeze unrelated policies sharing a UTxO. The
invariants live in a standalone `unfracking` withdraw-0 validator whose
credential is the protocol-params datum's `unfracking_cred` field; PLG only
checks that validator is invoked.

**Why your substandard cares:** two points. (a) Unfracking runs *without* your
transfer logic, so do not assume your transfer logic sees every movement of your
token between a holder's own UTxOs. (b) Your issuance logic must **not** trust
unfracking for mint custody — the framework already denies that delegation
(`issuance_mint.ak:plgl_scope_covers` returns `False` for `UnfrackingAct`); just
don't design around unfracking as a custody path.

---

## 2. Breakage triage: LOUD vs SILENT

Every behavioural change classified. **LOUD** = the transaction fails with a
script error the first time you hit it (a test will catch it). **SILENT** = the
transaction succeeds but behaves wrongly, or a stale assumption goes unnoticed —
these are the dangerous ones.

| # | Change | Loud/Silent | Symptom / Risk | Fix → step |
|---|---|---|---|---|
| B1 | `RegistryNode` datum grew to 7 fields | **LOUD** | Datum CBOR decode/con­struct mismatch; registration or node read fails | §3.1 |
| B2 | Protocol-params datum gained `unfracking_cred` (field #3) | **LOUD** | Params decode fails / deploy tooling writes wrong datum | §3.1 |
| B3 | PLG redeemer gained `UnfrackingAct`; `ThirdPartyAct` reshaped to `{registry_node_idx, outputs_start_idx}` | **LOUD** | Redeemer encode mismatch on the admin path | §3.1 |
| B4 | `issuance_mint` / `registry_mint` gained parameters → new policy ids & addresses | **LOUD** | Every derived policy id/address shifts; old blueprints point at dead scripts | §3.7 |
| B5 | `RegistryInsert` reshaped: `{key, hashed_param}` → `{key, minting_logic_script}` | **LOUD** | Redeemer encode mismatch on registration | §3.2 |
| B6 | `minting_logic_script` withdraw-0 required whether or not the registration carries a first mint | **LOUD** | Register-only tx rejected for missing proof-of-instance withdrawal | §3.2 |
| B7 | `TransferAct` proof contract is exact — pure mints must NOT carry a proof (Finding 02) | **LOUD** | Surplus-proof or missing-proof rejection | §3.3 |
| B8 | `ThirdPartyAct` continuing output must preserve `reference_script` (Finding 13) | **LOUD** | Seize-style tx rejected if it strips/replaces a ref script | §3.4 |
| B9 | `ThirdPartyAct` paired input must already hold the subject policy (Finding 12) | **LOUD** | Seizure of a UTxO that never held the policy is rejected | §3.4 |
| S1 | **Node governance fields are upgradable** — cached transfer/third-party/global-state creds go stale | **SILENT** | Integrator enforces old rules after an update; holders governed by rules they can't see | §3.5 |
| S2 | `issuance_mint` delegation signal moved input→withdrawal (Finding 09) | **SILENT** | Incidental PLB inputs no longer trigger delegation; custody validated by a different party than before | §3.6 |
| S3 | Companion assets are seizable unless you declare `protected_prefixes` | **SILENT** | Admin can seize/burn your CIP-68/102 assets you assumed were safe | §3.4 |
| S4 | Unfracking moves your token between a holder's UTxOs without your transfer logic | **SILENT** | Transfer-logic-based accounting misses same-owner restructuring | §3.5 |
| S5 | Net-positive mints must land at PLB even when pre-existing supply exists (re-audit R-04) | **SILENT** (until R-04 lands) | Mint routed outside PLB can escape custody | §3.6 |

---

## 3. Upgrade steps

Ordered so that CBOR/parameter breakage (which blocks everything) comes first.

### 3.1 Rebuild your datum/redeemer/params encoders (B1, B2, B3)

- **WHAT CHANGED.** `RegistryNode` is 7 fields (§1.2); protocol-params datum is
  3 fields (`registry_node_cs, prog_logic_cred, unfracking_cred` —
  `validators/programmable_logic/params.ak`); the PLG redeemer added
  `UnfrackingAct` and reshaped `ThirdPartyAct`
  (`lib/types.ak:ProgrammableLogicGlobalRedeemer`).
- **WHY.** Findings 17/18 added `unfracking_cred` and `protected_prefixes`; the
  admin path was made batch-capable.
- **WHAT YOU MUST DO.** Regenerate every off-chain constructor/parser for these
  three CBOR shapes. Field order matters — match `lib/registry_node.ak` and
  `params.ak` exactly. If you parse *existing* pre-audit registry UTxOs, handle
  both shapes during the migration window (no automatic ledger migration).
- **HOW TO VERIFY.** Round-trip a node datum through your encoder and Aiken's
  decoder (or a known-good on-chain node) and assert byte-equality; the same for
  params and for a `ThirdPartyAct` redeemer.

### 3.2 Rebuild the registration redeemer and always invoke your minting logic (B5, B6)

- **WHAT CHANGED.** `RegistryInsert { key, minting_logic_script }` — no
  `hashed_param`. `registry_mint` does not inspect the first-mint entries
  under the new key: whether a registration co-mints is purely a property of
  the tx you build. Your `minting_logic_script` withdraw-0 is required
  *whether or not* the registration carries a first mint (`registry_mint.ak`;
  walkthrough in the API doc §6).
- **WHY.** Finding 07 (Separation of Concerns) decoupled registration from
  issuance and made the proof-of-instance withdrawal explicit.
- **WHAT YOU MUST DO.** Encode the two-field redeemer. Decide per registration
  whether to co-mint the first batch (validated by `issuance_mint` +
  `MintingRegistryProof.OutputIndex`) or defer issuance and mint later via
  `issuance_mint` + `MintingRegistryProof.RefInput`. Include your
  minting-logic withdraw-0 in the withdrawals of *both* flows.
- **IF YOU WANT A STRICT REGISTER-THEN-MINT LIFECYCLE.** The base layer will
  not enforce it for you. Your minting-logic withdraw-0 fires in both flows,
  so it must know *why* it is running — give it an explicit running mode,
  e.g. a redeemer with `Register | Mint` arms. In the `Register` arm,
  validate the registration and assert `tx.mint` carries **no entries under
  your policy id** (resolve the policy id from the registry-node output being
  created, or recompute it); in the `Mint` arm, validate issuance as usual.
  Without this, nothing stops a registration transaction from also minting —
  `issuance_mint` would run and your withdraw-0 (already present for the
  proof of instance) would be its authorisation. See
  `09-DEVELOPING-SUBSTANDARDS.md` for the pattern.
- **HOW TO VERIFY.** A registration tx with no `key` entries in `tx.mint` and
  your minting-logic withdraw-0 present passes; the same tx without that
  withdrawal fails. If you implement the strict lifecycle: a registration tx
  that also mints under your policy id is rejected *by your validator*.

### 3.3 Fix your transfer proof contract (B7)

- **WHAT CHANGED.** Pure-mint policies (present in `tx.mint`, absent from any PLB
  input) are no longer subject to transfer-logic enforcement and must **not**
  carry a `TransferAct` proof; the one-proof-per-input-policy contract is exact
  (`validators/programmable_logic/transfer.ak:verify_proofs`, Finding 02).
- **WHY.** A purely-minted token has no prior custody to transfer; enforcing
  transfer logic on it was contradictory.
- **WHAT YOU MUST DO.** In your transfer tx builder, supply exactly one proof per
  PLB *input* policy — no more, no less. Do not add a proof for a policy that
  only appears in `tx.mint`.
- **HOW TO VERIFY.** A transfer that mints a new policy and supplies a proof for
  it is rejected as surplus; removing that proof passes.

### 3.4 Preserve reference scripts, respect protected prefixes, don't inject (B8, B9, S3)

- **WHAT CHANGED.** On `ThirdPartyAct`, the continuing output must preserve the
  input's `reference_script` (Finding 13); the paired input must already hold
  the subject policy (Finding 12); protected-prefixed tokens must be byte-equal
  across the pair (Finding 18).
- **WHY.** Close reference-script tampering, UTxO contamination, and
  companion-asset seizure.
- **WHAT YOU MUST DO.** In your third-party tx builder, copy the input's
  reference script to the continuing output verbatim; only target UTxOs that
  already hold the subject policy; and at registration, declare the CIP-67 label
  prefixes of any companion assets you want shielded in `protected_prefixes`
  (remember: append-only — you can add later but never remove).
- **HOW TO VERIFY.** A seize tx that drops a ref script, or targets a UTxO
  without the policy, or reduces a protected token, is rejected; the same tx
  respecting all three passes.

### 3.5 Stop caching governance credentials; account for unfracking (S1, S4)

- **WHAT CHANGED.** Node `transfer_logic_script` / `third_party_transfer_logic_script`
  / `global_state_cs` / `protected_prefixes` are mutable post-registration
  (§1.3); unfracking moves tokens between a holder's own UTxOs without your
  transfer logic (§1.6).
- **WHY.** Node upgradability (Finding-era in-place update) and Finding 17.
- **WHAT YOU MUST DO.** Resolve the registry node **fresh at build time** for
  every transaction; never persist its governance creds as immutable config.
  If your minting-logic script is meant to freeze governance, make it reject
  node-update transactions explicitly. If your off-chain accounting tracks token
  movement via transfer-logic invocations, add a path for `UnfrackingAct`
  (same-owner, value-preserving) so restructuring isn't misread as a transfer or
  a gap.
- **HOW TO VERIFY.** Point a build at a node, update the node's transfer logic in
  a separate tx, rebuild — the builder must pick up the new credential without a
  code/config change. Confirm an unfracking tx validates without your transfer
  logic in the withdrawals.

### 3.6 Re-check issuance custody and the delegation signal (S2, S5)

- **WHAT CHANGED.** `issuance_mint` decides delegation from *withdrawals*
  (is `plg_stake_cred` invoked?) not *inputs* (Finding 09), and does so
  *precisely* per registry node (`plgl_scope_covers`, Finding 04). Re-audit R-04
  (unmerged) additionally requires net-positive mints to land at PLB even when
  pre-existing supply could mask an escape.
- **WHY.** The old input-based signal let unrelated PLB inputs trigger (or mints
  escape) custody delegation.
- **WHAT YOU MUST DO.** Don't include stray PLB inputs as a delegation "signal" —
  invoke PLGlobal's withdraw-0 explicitly when you intend delegation. For first
  mints (`OutputIndex`), custody is always validated by `issuance_mint` itself;
  route all minted tokens to PLB. Track R-04 (§4 of the API doc) and route
  net-positive mints to PLB unconditionally.
- **HOW TO VERIFY.** A subsequent-mint tx that invokes PLGlobal delegates; one
  that doesn't validates custody in `issuance_mint`; a first mint sending tokens
  off-PLB is rejected.

### 3.7 Redeploy and re-fetch blueprints (B4)

- **WHAT CHANGED.** `registry_mint` gained `registry_spend_cred` (3rd param);
  `issuance_mint` gained `plg_stake_cred` (4th param). Both change all derived
  policy ids and addresses.
- **WHY.** Findings 03 and 09.
- **WHAT YOU MUST DO.** Redeploy the framework, then re-fetch blueprints from the
  backend API — do not hardcode script bytes/addresses in static config
  (address mismatch is the classic failure). Re-derive your substandard's
  addresses from the fresh blueprint.
- **HOW TO VERIFY.** Your `registry_spend` address and programmable-token policy
  ids match the on-chain reality returned by the API, not a cached JSON.

---

## 4. IF-you-did-X → now-Y quick map

| If your pre-audit code did this | Now do this |
|---|---|
| Built one tx that registered + minted, implicitly | Still works (register + first mint in one tx); include minting-logic withdraw-0 |
| Constructed `RegistryNode` with 5 fields | Construct 7 fields; add `minting_logic_script` (#3) and `protected_prefixes` (#7) |
| Passed `SmartTokenMintingAction { minting_logic_cred, proof }` | Pass `MintingRegistryProof` directly (`RefInput`/`OutputIndex`) |
| Passed `hashed_param` in `RegistryInsert` | Pass `minting_logic_script`; the validator derives the hash |
| Added a PLB input to signal issuance delegation | Invoke PLGlobal withdraw-0 (`plg_stake_cred`) explicitly |
| Supplied a `TransferAct` proof for every minted policy | Supply proofs only for PLB *input* policies; none for pure mints |
| Cached "policy X → transfer logic L" | Read the node fresh each build; L can change |
| Assumed companion assets can't be seized | Declare their CIP-67 prefixes in `protected_prefixes` (append-only) |
| Wrote protocol-params datum with 2 fields | Write 3 fields; add `unfracking_cred` |
| Hardcoded script bytes/addresses | Fetch blueprints from the API after redeploy |

---

## 5. Verification checklist (definition of done)

- [ ] Datum/redeemer/params encoders round-trip against on-chain shapes (B1–B3).
- [ ] Registration sets `mode` correctly and includes minting-logic withdraw-0 in
      both modes; wrong-mode and missing-withdrawal txs are rejected by test
      (B5, B6).
- [ ] Transfer builder supplies exact proofs; a pure-mint proof is rejected (B7).
- [ ] Third-party builder preserves ref scripts, targets only policy-holding
      inputs, and leaves protected prefixes byte-equal; negative tests fail
      (B8, B9, S3).
- [ ] No governance credential is cached; a node update is picked up on the next
      build with no code change (S1).
- [ ] Off-chain accounting handles `UnfrackingAct` (same-owner, no transfer
      logic) (S4).
- [ ] Delegation is signalled by PLGlobal withdraw-0, not stray PLB inputs;
      first mints route all tokens to PLB (S2).
- [ ] Framework redeployed; all addresses/policy ids re-derived from
      API-fetched blueprints (B4).
- [ ] Tracking re-audit R-04 (issuance no-escape) for when it lands (S5).

---

## 6. Canonical sources

| Concept | Source |
|---|---|
| Registry node datum & field mutability | `lib/registry_node.ak:RegistryNode`, `lib/linked_list.ak:is_field_updated_registry_node` |
| Node update path & authority (R-01) | `validators/registry_spend.ak` |
| Registration flows (with/without first mint) | `lib/types.ak:RegistryRedeemer`, `validators/registry_mint.ak` |
| Issuance / delegation / custody | `validators/issuance_mint.ak:plgl_scope_covers` (`transfer_scope_covers` on `feat/upgradability-in-place`) |
| Transfer proof contract | `validators/programmable_logic/transfer.ak:verify_proofs` |
| Third-party scope & protected prefixes | `validators/programmable_logic/third_party.ak` |
| Protocol-params datum | `validators/programmable_logic/params.ak` |
| Unfracking | `validators/programmable_logic/unfracking.ak` (on `feat/upgradability-in-place`: dispatched by PLB's `SpendViaUnfracking`, no PLG branch) |
| Control scope (human narrative) | [`03-CONTROL-SCOPE-AND-ADMIN-AUTHORITY.md`](./03-CONTROL-SCOPE-AND-ADMIN-AUTHORITY.md) |
| Field-level API/CBOR surface | [`cip113-api-changes-post-audit.md`](./cip113-api-changes-post-audit.md) |
