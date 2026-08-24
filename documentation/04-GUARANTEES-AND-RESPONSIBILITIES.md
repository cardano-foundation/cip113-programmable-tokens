# Guarantees & Responsibilities

Who enforces what, in a CIP-113 deployment: what the shared core validators check, what a
substandard must check because nothing else will, and what nobody checks at all.

This document exists because the boundary is not obvious from either side. Substandards in the
wild re-implement structural checks the core already performs — and the same substandards omit
duties the core never had. Both mistakes come from the same missing document.

## 1. How to read this

### Two layers: the standard, and this implementation

Every entry states which layer it belongs to, because they carry different weight:

| Layer | Meaning | What it is safe to build on |
|---|---|---|
| **SPEC** | Required by CIP-113 of any conforming implementation. | The property, as stated. Another implementation of the standard owes you the same guarantee. |
| **IMPL** | What *this reference implementation* enforces today, at the commit and deployment you are pointed at. | The property *for the deployment you verified*. It may be tightened, loosened, or relocated by a future version. |

The document therefore says "the current spec and the current implementation guarantee X",
never "X is true". Where the two diverge — the implementation enforcing more than the standard
demands, or the standard requiring something this implementation leaves to a substandard — the
entry says so.

### IMPL guarantees are scoped to a deployment, not to an address

This matters more than it looks. `programmable_logic_base` reads the three delegate credentials
**live, from the protocol-params datum**, on every spend; `coordination_spend` lets the sitting
upgrade authority rewrite them. The base validator's hash — and therefore every programmable
token address — is unchanged by that rewrite.

So "tokens at this address are governed by the audited transfer validator" is **not** something
an address can tell you. An `IMPL` guarantee is a property of a *params-NFT policy plus the
datum state it currently points at*. An integrator whose risk model depends on a particular
delegate must read that datum, pin what it found, and re-check it — not derive it from the
address. `ASSUME-*` entries collect the deployment conditions the `CORE-*` entries rest on.

### Identifier namespaces

| Prefix | Meaning |
|---|---|
| `CORE-PLB-nn` | Enforced by `programmable_logic_base` (custody + dispatch) |
| `CORE-TR-nn` | Enforced by the `transfer` validator |
| `CORE-TP-nn` | Enforced by the `third_party` validator |
| `CORE-UF-nn` | Enforced by the `unfracking` validator |
| `CORE-IM-nn` | Enforced by `issuance_mint` |
| `CORE-REG-nn` | Enforced by `registry_mint` / `registry_spend` |
| `CORE-PAR-nn` | Enforced by `protocol_params_mint` / `coordination_spend` |
| `SUB-nn` | The substandard author's duty — nothing else performs it |
| `RESIDUAL-nn` | Enforced by nobody. Accepted risk, with its mitigation |
| `ASSUME-nn` | A deployment or operational condition the `CORE-*` entries depend on |

Identifiers are **append-only**. One is never reused and never renumbered: an entry that stops
being true is marked withdrawn in place, because other documents, substandard source comments,
and audit correspondence cite these strings. When another document cites an id it carries the
one-line statement alongside it — a reader deciding whether to delete a check must never have
to follow a link to find out what they are relying on.

### Evidence is a test name, not a line number

Each `CORE-*` entry cites the test that locks it, so the claim is checkable:

```bash
aiken check -m <test-name>
```

Line numbers were considered and rejected: nothing in CI reads prose, so a `file:line`
reference rots silently on the next refactor and the document keeps being cited as normative.
A test name is a string the build can be made to assert still exists. Entries whose invariant
has no covering test say so — that is a real signal, not an omission.

Convention, so the citation can be checked mechanically: **inside an Evidence cell, a
backticked name is a test name and nothing else.** `.github/scripts/check-doc-citations.py`
enforces both halves — that every cited id is defined here, and that every cited test still
exists.

### Duplicating a guarantee is allowed

This document is not a licence to delete code. Re-checking something the core already enforces
is **defence in depth**, and a reasonable engineering choice: it costs execution units and buys
independence from exactly the deployment-scoping caveat above. What this document is for is
*allocation* — so that the checks you keep are chosen, and the ones only you can perform are
not missing. The observed failure in the field is not duplication; it is duplicating the cheap
structural checks while omitting the recipient, certificate and companion-asset duties that no
other party performs.

## 2. Guarantees by transaction kind

A CIP-113 transaction is one of six kinds. **The kind is chosen per spent input**, in the
`BaseSpendRedeemer` of each `programmable_logic_base` input, so a single transaction may mix
arms — in which case every named delegate runs and every one of their invariants applies, and
the result is the intersection, never the union. A guarantee below holds for the kind it is
listed under; it does not carry across.

| Question | Transfer | Third-party action | Unfracking |
|---|---|---|---|
| Delegate invoked | `transfer` | `third_party` | `unfracking` |
| Base redeemer arm | `SpendViaTransfer` | `SpendViaThirdParty` | `SpendViaUnfracking` |
| Substandard script the core requires | each registered input policy's `transfer_logic_script` | the subject policy's `third_party_transfer_logic_script` | the acted policy's `unfracking_logic_script` (**unset = forbidden**) |
| Holder's consent required? | **Yes** — every PLB input's stake credential | **No**, by design | **Yes** — the single owner's |
| Recipient constrained? | **No** — any PLB address with an inline stake credential | Paired outputs preserve the holder's address; other PLB outputs are unconstrained | Outputs must return to the same owner address |
| Output datums pinned? | **No** | Only on *paired* outputs | Only on *paired* outputs |
| Tokens can leave the PLB? | **No** — per-policy lower bound over PLB outputs | **No** — aggregate superset over PLB outputs, reconciled against mint/burn | **No** — strict equality over the owner's outputs |
| Lovelace | unconstrained by this path | ratcheted `>=` per pair — may be topped up, never drained | unconstrained by this path |
| Mint / burn of the acted policy | pure mints are excluded from transfer accounting and belong to issuance | permitted, and reconciled into the conservation check | **forbidden** — the mint field must be empty |
| Policies per transaction | many | **exactly one** | **exactly one** |

The remaining three kinds do not spend programmable tokens through the dispatcher:

| Question | Issuance (mint / burn) | Registry lifecycle | Protocol upgrade |
|---|---|---|---|
| Entry point | `issuance_mint` | `registry_mint` (insert) / `registry_spend` (update) | `coordination_spend` |
| Authorised by | the policy's `minting_logic_script` withdraw-0 | the node's `minting_logic_script` withdraw-0 — **`Script` credentials only** | the **current** datum's `upgrade_cred` withdraw-0 |
| Core constrains the amount? | **No** — presence of your minting logic is the whole check | n/a | n/a |
| Custody of what is minted | pinned at the PLB, unless a delegate covering the same registry node is running | n/a | n/a |
| May mint the node's own token | n/a | **No** — lifecycle and issuance are always separate transactions | n/a |

> Reading the matrix: a row that says **No** is a duty, not an absence. Every "No" in the
> *constrained?* rows is a `SUB-*` entry in §4, because it is a decision the core has left to
> the only party that can make it.

## 3. Core guarantees

Load-bearing entries only — the ones a substandard would otherwise re-implement, or wrongly
assume. `Evidence` names the test that locks the invariant; run it with `aiken check -m <name>`.
An entry reading **no covering test** is a guarantee the code makes that no test currently
protects: true today, unguarded against tomorrow's refactor. Treat those as weaker than the rest.

### Custody and dispatch — `programmable_logic_base`

| id | Guarantee | Layer | Evidence |
|---|---|---|---|
| `CORE-PLB-01` | Every programmable token lives at the base validator's payment credential, and any spend of one must invoke a delegate's withdraw-0. | SPEC | `plb_fails_with_empty_withdrawals` |
| `CORE-PLB-02` | The delegate credential is read **live** from the protocol-params datum at the redeemer's `params_idx`, authenticated by the one-shot params NFT. | IMPL | `plb_fails_without_params_reference_input` |
| `CORE-PLB-03` | The withdrawal at the redeemer's `wdrl_idx` must carry exactly the credential the chosen arm names; every other index is rejected. | IMPL | `plb_fails_when_wdrl_idx_points_at_wrong_entry`; property `plb_transfer_arm_accepts_only_the_recomputed_index` |
| `CORE-PLB-04` | An arm cannot be satisfied by another arm's delegate — a transfer redeemer is not satisfied by the third-party or unfracking credential, and vice versa. | IMPL | `plb_fails_third_party_arm_witnessing_transfer_cred` and its four siblings |
| `CORE-PLB-05` | After an in-place upgrade the retired delegate credential no longer authorises anything. | IMPL | `plb_rejects_stale_transfer_cred_after_upgrade` |

> **`CORE-PLB-04` rests on `ASSUME-01`.** The arms are distinguishable only while the three
> delegate credentials in the params datum differ. Nothing on-chain enforces that.

### Transfers — `transfer`

| id | Guarantee | Layer | Evidence |
|---|---|---|---|
| `CORE-TR-01` | Every spent PLB input's stake credential authorises the transaction: a signature for a verification key, a withdrawal keyed by that script for a script credential. | SPEC | `owner_consent_rejects_unsigned_vkey`, `owner_consent_rejects_script_without_withdrawal` (kernel-level) |
| `CORE-TR-02` | Each registered policy among the inputs has its `transfer_logic_script` withdraw-0 invoked. | SPEC | `fails_transfer_without_token_transfer_logic` |
| `CORE-TR-03` | Registered tokens cannot leave the base address: for each input policy, the total across PLB outputs is at least the total across PLB inputs, reconciled against mint and burn. | SPEC | `transfer_act_mint_insufficient_output_fails` |
| `CORE-TR-04` | A claim that a policy is *unregistered* must be proved by a covering node that genuinely brackets it (`key < policy < next`). | SPEC | `fails_absence_proof_when_node_starts_above_policy`, `fails_absence_proof_when_node_ends_below_policy` |
| `CORE-TR-05` | Proofs are consumed exactly — one per distinct input policy, no leftovers. | IMPL | `transfer_act_pure_mint_with_unnecessary_proof_must_fail` |
| `CORE-TR-06` | A policy that appears only in `mint` (a pure mint) is outside the transfer path entirely; its custody belongs to `issuance_mint`. | IMPL | `transfer_act_with_only_minting_succeeds` |
| `CORE-TR-07` | The registry node resolved by a proof is authenticated by the registry NFT policy. | IMPL | property `prop_registry_lookup_fail_wrong_policy` |
| `CORE-TR-08` | A `TokenExists` proof's node must have `key` equal to the proven policy. | IMPL | **no covering test** |

> **What `CORE-TR-01` does NOT imply.** For a **script** stake credential the check is that a
> withdrawal keyed by that script is present — which, because a failing withdraw-0 kills the
> transaction, does prove the script *ran and approved this transaction*. It does not prove the
> script was written with these tokens in mind. If you hold programmable tokens under a script,
> that script is your ownership authority for everything staked to it (see `SUB-06`, and
> [`08-INTEGRATION-GUIDES.md`](./08-INTEGRATION-GUIDES.md)).
>
> **What `CORE-TR-02` does NOT imply.** It is a *presence* test. It does not scope the
> invocation to a policy, an input, or an output; two policies sharing one logic hash are both
> satisfied by one invocation (`SUB-10`), and nothing stops a third party placing your
> withdraw-0 in an unrelated transaction (`SUB-09`).
>
> **What `CORE-TR-03` does NOT imply.** It is a per-policy **lower bound** over the aggregate.
> It binds no input to any output, constrains no recipient beyond "a PLB address with an inline
> stake credential", pins no output datum, and says nothing about lovelace. Who may receive is
> `SUB-01`; datums are `SUB-11`.

### Administrative actions — `third_party`

| id | Guarantee | Layer | Evidence |
|---|---|---|---|
| `CORE-TP-01` | The subject policy's `third_party_transfer_logic_script` withdraw-0 must be invoked — the sole authorisation for the administrative path. | SPEC | **no covering test** |
| `CORE-TP-02` | Each spent PLB input is paired positionally with a continuing output, starting at `outputs_start_idx`. | IMPL | `third_party_act_missing_prog_output`, `third_party_act_prog_outputs_out_of_order` |
| `CORE-TP-03` | The paired output preserves the holder's **address** and **datum** byte-for-byte. | SPEC | positive coverage only — no test varies either |
| `CORE-TP-04` | The paired output preserves the input's **reference script** byte-for-byte. | IMPL | `third_party_act_reference_script_added_fails`, `third_party_act_reference_script_swapped_fails` (Finding 13) |
| `CORE-TP-05` | The paired output's lovelace is ratcheted `>=`, never equal: it may be topped up, never drained. | IMPL | `third_party_act_pair_ada_drain_fails`, `third_party_act_pair_ada_topup_succeeds` (issue #96) |
| `CORE-TP-06` | The paired input must already hold the subject policy — the administrator cannot conjure it onto an untouched UTxO, nor drag one into the action. | SPEC | `third_party_act_paired_input_missing_acted_on_policy_fails` (Finding 12) |
| `CORE-TP-07` | Every **non-subject** policy is byte-identical across the pair — none can be injected, redirected, split or destroyed. | SPEC | `third_party_act_pair_foreign_policy_injection_still_fails` |
| `CORE-TP-08` | The subject policy's total across all PLB outputs is a superset of the total across all PLB inputs, seeded by mint and burn — seized tokens cannot escape the base address. | SPEC | `third_party_act_seized_tokens_escape_prog_cred_must_fail`, `third_party_act_delta_insufficient_remaining_fails` |
| `CORE-TP-09` | Exactly one registry node, therefore exactly one policy, per administrative transaction. | IMPL | structural — the redeemer carries a single registry_node_idx |

> **What the third-party guarantees do NOT imply.** No holder consent is required — that is the
> point of the path. `CORE-TP-03` pins **paired** outputs only: a token routed to any *other* PLB
> output carries whatever datum and stake credential that output declares, so an administrator can
> re-home tokens under a datum they choose. No token of the subject policy is exempt, companion
> assets included (`SUB-02`). Whether the action is a freeze or an extraction is invisible to the
> base layer (`SUB-05`), and who is a legitimate target is not decided here (`SUB-06`).

### Restructuring — `unfracking`

| id | Guarantee | Layer | Evidence |
|---|---|---|---|
| `CORE-UF-01` | The acted policy's `unfracking_logic_script` withdraw-0 must be invoked; an unset hook is unsatisfiable, so unfracking is **denied by default**. | SPEC | `unfracking_fails_when_hook_unset`, `unfracking_fails_when_hook_not_invoked` |
| `CORE-UF-02` | Every PLB input shares one owner address, pinned from the first, and that owner authorises the transaction. | SPEC | `unfracking_fails_two_stake_creds_among_inputs`, `unfracking_fails_missing_owner_authorisation` |
| `CORE-UF-03` | The transaction mints and burns nothing at all. | SPEC | `unfracking_fails_with_mint`, `unfracking_fails_with_burn` |
| `CORE-UF-04` | The acted policy is conserved **exactly** across the owner's outputs — no surplus, no shortfall. | SPEC | `unfracking_fails_acted_surplus`, `unfracking_fails_acted_shortfall` |
| `CORE-UF-05` | The acted policy leaves each paired output entirely — no partial strip — while every non-acted policy stays byte-identical. | IMPL | `unfracking_fails_partial_strip_residue_in_pair`, `unfracking_fails_non_acted_delta_in_pair` |
| `CORE-UF-06` | Acted tokens may regroup only at the owner's own address. | SPEC | `unfracking_fails_acted_tokens_to_other_stake_cred` |

> Unfracking does not constrain lovelace at all: it is dropped before comparison. The holder
> authorises the whole transaction, so this is a consent question, not a custody one.

### Issuance — `issuance_mint`

| id | Guarantee | Layer | Evidence |
|---|---|---|---|
| `CORE-IM-01` | The policy's `minting_logic_script` withdraw-0 must be invoked for any mint or burn. | SPEC | `minting_logic_not_invoked_fails` |
| `CORE-IM-02` | The registry node named by the redeemer is authenticated and its `key` equals the minting policy — a policy cannot mint against another's node. | SPEC | `wrong_registry_key_fails`, `registry_nft_missing_fails`, `wrong_registry_cs_nft_fails` |
| `CORE-IM-03` | No token of the minted policy may sit at a non-PLB output, and every PLB output carries an inline stake credential. | SPEC | `output_not_at_plb_fails`, `output_missing_stake_cred_fails`, `output_partial_escape_to_non_plb_fails` |
| `CORE-IM-04` | Custody may be **delegated**, but only to a delegate whose own redeemer names the *same* registry node. | IMPL | `refinput_mint_third_party_wrong_node_no_delegation_fails` (Finding 04) |
| `CORE-IM-05` | Delegation tracks the live delegate credentials; a retired one cannot cover a mint. | IMPL | `launch_era_transfer_cred_cannot_delegate_after_upgrade_fails` |

> **What `CORE-IM-01` does NOT imply.** Presence is the entire check. `issuance_mint` constrains
> no quantity, no asset name and no cap — supply policy is `SUB-08`.
>
> **`CORE-IM-04` fails safe but silently.** With no coordination reference input, or a delegate
> whose redeemer names a different node, delegation simply does not happen and local custody
> applies instead. The transaction does not fail; it gets stricter. Do not read a successful
> mint as evidence that delegation occurred.

### Registry — `registry_mint`, `registry_spend`

| id | Guarantee | Layer | Evidence |
|---|---|---|---|
| `CORE-REG-01` | A policy id is cryptographically bound to the `minting_logic_script` it registers with: only that substandard can ever register that policy. | SPEC | `registry_insert_fails_wrong_minting_logic_for_key` |
| `CORE-REG-02` | Insertion preserves the sorted list — the covering node must genuinely cover the new key. | SPEC | `registry_insert_fails_key_not_covered` and siblings |
| `CORE-REG-03` | The covering node is re-emitted unchanged except for `next` — an insertion cannot tamper with a neighbour's governance fields. | IMPL | `is_updated_directory_node_rejects_transfer_logic_swap` and siblings |
| `CORE-REG-04` | A node update may change only `transfer_logic_script`, `third_party_transfer_logic_script`, `unfracking_logic_script`, `global_state_cs`; `key`, `next` and `minting_logic_script` are frozen. | SPEC | `fails_update_changes_minting_logic` |
| `CORE-REG-05` | A node update is authorised by that node's own `minting_logic_script` withdraw-0. | SPEC | `fails_update_without_minting_logic_withdrawal`, `fails_update_wrong_withdrawal_credential` |
| `CORE-REG-06` | A registry-node spend may not mint or burn that node's own policy: lifecycle and issuance are always separate transactions. | SPEC | `fails_update_mints_own_programmable_token` (R-01) |

> A `VerificationKey` `minting_logic_script` can never satisfy `CORE-REG-05`, so such a node can
> never be updated — irreversibly, since that field is frozen (`SUB-07`). **no covering test**.

### Protocol parameters and upgrade — `protocol_params_mint`, `coordination_spend`

| id | Guarantee | Layer | Evidence |
|---|---|---|---|
| `CORE-PAR-01` | The protocol-params NFT is one-shot: exactly one, minted against a consumed reference, locked at the coordination address with a well-formed inline datum. | SPEC | `fails_when_utxo_not_consumed`, `fails_when_quantity_is_not_one`, `fails_with_invalid_datum_type` |
| `CORE-PAR-02` | An upgrade preserves the coordination UTxO exactly — one in, one out, non-ADA value identical, ADA ratcheted, no reference script attached. | IMPL | `coord_fails_dropping_nft`, `coord_fails_injecting_tokens`, `coord_fails_draining_ada`, `coord_fails_reference_script_attached` |
| `CORE-PAR-03` | `prog_logic_cred` and `registry_node_cs` are frozen forever: no upgrade can move token custody or repoint the registry. | SPEC | `coord_fails_changing_prog_logic_cred`, `coord_fails_changing_registry_node_cs` |
| `CORE-PAR-04` | Every mutable credential written by an upgrade must be a well-formed 28-byte hash — a one-way-brick guard. | IMPL | `coord_fails_unsatisfiable_transfer_cred`, `coord_fails_unsatisfiable_unfracking_cred` — third_party_cred: **no covering test** |
| `CORE-PAR-05` | The **sitting** authority approves every change, including its own replacement: the check reads the old datum's `upgrade_cred`. | SPEC | `coord_handover_needs_current_authority` |

> `CORE-PAR-04` checks the *length* of a credential, not its kind. A verification-key credential
> of the right length is accepted, which would make a delegate a key-controlled reward account
> (`ASSUME-02`).

## 4. Substandard duties

Each entry is something **no other party performs**. Skipping one is not a smaller version of
your substandard; it is a hole. The "if you skip it" column is the observable consequence, not
a hypothetical.

### SUB-01 — Decide who may receive · MUST

The core constrains nothing about the recipient of a transfer beyond *"a `programmable_logic_base`
address carrying some inline stake credential"*. Containment is a per-policy **lower bound** over
all PLB outputs: it never binds a particular input to a particular output, and never inspects
whose stake credential the output carries. Any PLB address is a valid destination — including one
whose stake credential is an unspendable script.

*If you skip it:* your token transfers to anyone, including addresses your compliance model
forbids. A denylist that checks only the *sender* — the shape of at least one deployed
substandard — permits a blocked party to receive without limit.

### SUB-02 — Protect your own companion assets · MUST, if the policy has any

The base layer applies control at the **policy** level and models no CIP-67 token roles, so a
CIP-68 reference NFT (label 100) or CIP-102 royalty token (label 500) is exactly as reachable by
an administrative action as the user token. There is no field to declare and no list to append to.
Full duty and the implementable sketch: [`03-CONTROL-SCOPE-AND-ADMIN-AUTHORITY.md`](./03-CONTROL-SCOPE-AND-ADMIN-AUTHORITY.md) §2.2.

*If you skip it:* an administrator can burn your collection's reference NFT, or re-home it to an
output whose datum they choose — and for CIP-68 that datum *is* the metadata.

### SUB-03 — Constrain the certificates your withdraw-0 scripts will endorse · MUST

A stake validator is invoked for **certificate** purposes too, not only withdrawals. The core's
three delegates each accept `RegisterCredential` and reject everything else. A substandard whose
`publish` handler returns `True` unconditionally endorses any certificate presented — including
its own **de-registration**.

*If you skip it:* anyone can get your logic script's stake credential de-registered; its
withdraw-0 then fails, and every transfer of every token governed by it halts until someone
re-registers and re-pays the deposit. Recoverable, cheap to trigger, and it is the current shape
of more than one published substandard.

### SUB-04 — Rule on unfracking deliberately · MUST

`unfracking_logic_script` is **default-deny**: a node registered with the field unset forbids
unfracking for that policy, permanently, until the node is updated — and it cannot be updated at
all if the policy's `minting_logic_script` is a `VerificationKey` (SUB-07).

*If you skip it:* your holders can never split a "fracked" multi-policy UTxO. That is precisely
the collateral damage unfracking exists to prevent — a freeze on someone else's policy sharing
their UTxO becomes a freeze on yours.

### SUB-05 — Decide what "frozen" means on all three paths · MUST

There is no freeze primitive and no action tag: `ThirdPartyRedeemer` carries only indices, and the
core requires merely that your third-party logic *is invoked*, never inspecting what it decided.
"Frozen" is therefore three independent decisions — declining transfers (transfer logic),
permitting or refusing administrative action (third-party logic), and permitting or refusing
restructuring (the unfracking hook).

*If you skip it:* a holder you believe frozen retains whichever of the three paths you did not
consider. The freeze-versus-extract asymmetry is yours to implement; the framework has no opinion.

### SUB-06 — Decide who is seizable · MUST, if you support administrative action

The core authorises a third-party action by your issuer-control script and inspects nothing about
the target. A `VerificationKey`-staked UTxO is a user wallet, where extraction is meaningful; a
**script**-staked UTxO is ambiguous — a smart wallet, or a DeFi pool holding other people's
deposits. Two reference patterns gate extraction from script-staked inputs: an issuer **allowlist**
of known protocols, or **consent** (the script's own withdraw-0 must fire in the same transaction).

*If you skip it:* an administrative action can extract tokens a protocol holds on behalf of
uninvolved third parties.

### SUB-07 — Separate registration from issuance if they are different powers · SHOULD

One credential, `minting_logic_script`, authorises **both** minting and registry-node lifecycle.
Whoever can mint can also reconfigure the node — retroactively, for all existing holders. If those
must be distinct authorities, split them inside your issuance logic; nothing upstream will.

Related and **irreversible**: if that credential is a `VerificationKey`, the node can never be
updated, because `registry_spend` requires its withdraw-0 and only a `Script` can supply one.
Decide before you register.

### SUB-08 — Enforce your own supply and naming policy · MUST

`issuance_mint` checks that your minting logic's withdraw-0 is *present*. It does not check the
quantity minted, the asset names used, or any cap. Custody it does enforce; supply it does not.

*If you skip it:* your minting authority can mint any quantity under any asset name, including
names that collide with your own companion-asset labels.

### SUB-09 — Do not assume the core invoked you · MUST

The core requires that your script's withdrawal be **present**. Nothing prevents anyone from
placing your withdraw-0 into an unrelated transaction of their own. "I am running, therefore a
legitimate CIP-113 action on my policy is happening" is false.

*If you skip it:* logic with side effects on your own state — supply counters, claim roots,
pause flags — can be driven from a transaction that has nothing to do with your token. Anchor
your state transitions on something you verify yourself.

### SUB-10 — Scope your checks per policy if you serve more than one · MUST

The core requires the registered `transfer_logic_script` of each input policy to be invoked. It is
a **presence** test. Two policies that register the *same* logic script hash are both satisfied by
that one invocation.

*If you skip it:* a transaction moving policy A satisfies the framework's requirement for policy B
as well, and your single invocation must therefore validate every policy it governs, not just the
one it happens to look at.

### SUB-11 — Own your datums · MUST, if your token uses them

The transfer path pins **no** output datums at all. The third-party and unfracking paths pin datums
only on *paired* outputs; a token routed to any other PLB output carries whatever datum that output
declares.

*If you skip it:* datum-carrying tokens can be re-emitted with attacker-chosen datums. For CIP-68
this is the metadata itself.

## 5. Enforced by nobody, and deployment assumptions

### Residual risks

#### `RESIDUAL-01` — a no-op forced respend is not prevented
 An administrator can re-spend a
holder's UTxO without changing its subject balance, and can restore a balance through an
unpaired output that the per-pair walk never inspects. A pair-local guard existed and was
removed (re-audit R-03): it was pair-local, so it never delivered the aggregate property it
appeared to, and a per-owner aggregate check measured ~+22% in size, CPU and memory on the hot
path. *Mitigation:* each respend costs the administrator real fees, so sustained churn is
self-limiting. A substandard may add its own rule. Documented by `third_party_act_no_op_seize_succeeds`.

#### `RESIDUAL-02` — your withdraw-0 can be invoked by anyone, in any transaction
 The framework
requires your script's withdrawal to be *present*; nothing prevents a third party including it
in a transaction of their own. *Mitigation:* `SUB-09` — anchor any state transition yourself.

#### `RESIDUAL-03` — one policy per administrative transaction
 Multi-policy seizure was
prototyped and deliberately not adopted (execution-cost and script-size tax on the common
single-policy path). A compliance operation spanning policies needs sequential transactions and
accepts the exposure window between them. Permanent.

#### `RESIDUAL-04` — no registry removal
 `RegistryRedeemer` offers `Init` and `Insert` only. A
registered policy is registered forever; the remedy for a retired token is a node update, not a
removal.

#### `RESIDUAL-05` — no on-chain timelock on upgrades
 A valid upgrade transaction takes effect
in the block that carries it. The seam exists (validity intervals) but nothing enforces a delay,
so the sole protection against a hostile upgrade is the authority behind `upgrade_cred`.

### Deployment assumptions

These are conditions the `CORE-*` guarantees rest on and that **nothing on-chain enforces**. They
are the deployer's and the upgrade authority's responsibility, and an integrator relying on the
guarantees above should verify them against the deployment they are pointed at.

#### `ASSUME-01` — the three delegate credentials are pairwise distinct
 If any two of
`transfer_cred`, `third_party_cred` and `unfracking_cred` are equal, the corresponding
`BaseSpendRedeemer` arms collapse into one and `CORE-PLB-04` is vacuous. Neither
`protocol_params_mint` nor `coordination_spend` checks it. Pinned by
`plb_equal_delegate_creds_collapse_the_arms`, which documents the collapse rather than
preventing it.

#### `ASSUME-02` — the delegate credentials are script credentials
 `CORE-PAR-04` checks length,
not kind. A 28-byte verification-key credential would pass, making the "delegate" a reward
account any holder of that key can satisfy.

#### `ASSUME-03` — the registry NFT policy is genuinely one-shot, and `registry_mint` is its only minter
 Every reader of a registry node authenticates it by policy id alone and trusts
`registry_mint`'s binding rather than re-deriving it. A second minter of that policy would forge
nodes that every delegate accepts.

#### `ASSUME-04` — the deployment wiring is correct and was verified once
 The params datum's
`prog_logic_cred` must be the base validator actually holding the tokens, and each delegate
credential the script actually deployed at that hash. Nothing on-chain cross-checks the wiring;
`CORE-PAR-03` freezes it only *after* genesis has set it.
