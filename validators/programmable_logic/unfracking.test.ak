//// Tests for the Unfracking action — v2 (registry-gated,
//// third-party-shaped). See `documentation/design/unfracking-v2-registry-hook.md`.
////
//// The fixtures sit at the top of the file (per CLAUDE.md), every test
//// is built by spreading a known-good fixture and overriding one field
//// to expose the invariant under test. Names read as specs.
////
//// Script composition: a real unfracking transaction carries up to
//// THREE withdraw-0s (`fixture.withdrawals_unfracking`):
////
////   * programmable_logic_base.spend (SpendViaUnfracking) — per PLB input;
////     requires unfracking's withdraw-0 at the witnessed index. The
////     transfer validator is NOT part of an unfracking transaction.
////   * unfracking.withdraw — enforces the v2 invariants tested here,
////     including that the acted-on policy's issuer hook withdraw-0
////     (registry node field 5, `credential_unfracking_hook` in the
////     fixture) is present. No script, no party.
////   * the owner's stake-script withdraw-0 (transfer logic in the
////     default fixture) — or a vkey signature instead.

use cardano/address.{Credential, VerificationKey}
use cardano/assets.{
  AssetName, PolicyId, ada_asset_name, ada_policy_id, from_asset, merge,
}
use cardano/transaction.{DatumHash, InlineDatum, Input, Output, Transaction}
use programmable_logic/fixture
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use programmable_logic_base
use registry_node.{RegistryNode, empty_vkey, sentinel_next_key}
use types.{SpendViaUnfracking, UnfrackingRedeemer}
use unfracking

// --------------------------------------------------------------------- consts

/// The acted-on policy: the one the unfracking action names via its
/// registry node and regroups into its own UTxO(s).
const policy_a: ByteArray =
  #"00000000000000000000000000000000000000000000000000000a00"

/// A co-resident registered policy that must remain byte-identical in
/// the paired continuing output.
const policy_b: ByteArray =
  #"00000000000000000000000000000000000000000000000000000b00"

/// A non-programmable / unregistered policy parked in the fracked UTxO.
/// Non-acted byte-identity pins it in place like any other policy.
const policy_unrelated: ByteArray =
  #"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"

/// A vkey holder, for the signature-authorised owner path.
const second_vkey_pkh: ByteArray =
  #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

/// A third-party (Eve) credential the owner has NOT authorised.
const eve_vkey_pkh: ByteArray =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const unfracking_redeemer =
  UnfrackingRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

// ----------------------------------------------------------------- fixtures

/// The canonical "happy path" v2 unfracking transaction, from the
/// shared fixture: ONE fracked PLB input (100 A + 100 B) at the default
/// script stake credential; the paired continuing output keeps B
/// byte-for-byte while all of A regroups into an extra output at the
/// same owner address. Reference inputs: protocol params (0) and the
/// acted policy's registry node with the hook set (1).
fn valid_unfracking_tx() -> Transaction {
  let (tx, _) = fixture.some_unfracking(
    policy_a,
    [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
    [(policy_b, "BAR", 100)],
    [(policy_a, "FOO", 100)],
  )
  tx
}

/// Withdrawals WITHOUT the issuer hook — the composition a pre-v2
/// transaction would carry. Used by the hook-invocation negative.
const withdrawals_without_hook: Pairs<Credential, Int> =
  [
    Pair(fixture.credential_validator_unfracking, 0),
    Pair(fixture.credential_transfer_logic, 0),
  ]

/// Withdrawals for a vkey-staked owner (no transfer-logic withdraw-0
/// needed — the owner signs instead).
const withdrawals_vkey_owner: Pairs<Credential, Int> =
  [
    Pair(fixture.credential_validator_unfracking, 0),
    Pair(fixture.credential_unfracking_hook, 0),
  ]

/// The acted policy's registry node ref input with a caller-chosen hook
/// credential. Spread base is the shared fixture node; the only delta
/// is the `unfracking_logic_script` value.
fn node_ref_with_hook(hook: Credential) -> Input {
  let base = fixture.some_reference_input_unfracking_registry_node(
    policy_a,
    "unfracking registry node",
  )
  Input {
    ..base,
    output: Output {
      ..base.output,
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: policy_a,
            next: sentinel_next_key,
            transfer_logic_script: fixture.credential_transfer_logic,
            third_party_transfer_logic_script: fixture.credential_3rd_party_logic,
            minting_logic_script: empty_vkey,
            unfracking_logic_script: hook,
            global_state_cs: "",
          },
        ),
      ),
    },
  }
}

/// Spread a programmable-tokens output and add `delta` lovelace on top
/// of the fixture's min-ada value (negative delta = drain). Ada is
/// deliberately unconstrained in unfracking pairs — both directions
/// must PASS (cf. the ThirdPartyAct lovelace ratchet, issue #96, where
/// only the increase is legal).
fn output_with_extra_lovelace(
  tokens: List<(PolicyId, AssetName, Int)>,
  delta: Int,
) -> Output {
  let base = fixture.some_output_with_programmable_tokens(tokens)
  Output {
    ..base,
    value: base.value
      |> merge(from_asset(ada_policy_id, ada_asset_name, delta)),
  }
}

/// Dispatch helper — drives the standalone `unfracking.withdraw`
/// validator with an explicit redeemer.
fn run_unfracking_with(tx: Transaction, redeemer: UnfrackingRedeemer) -> Bool {
  unfracking.unfracking.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_unfracking,
    tx,
  )
}

/// Dispatch helper with the canonical redeemer (node ref at index 1,
/// paired outputs from index 0).
fn run_unfracking(tx: Transaction) -> Bool {
  run_unfracking_with(tx, unfracking_redeemer)
}

/// Dispatch helper — drives `programmable_logic_base.spend` with a
/// `SpendViaUnfracking` redeemer witnessing the unfracking withdrawal at
/// index 0 (where `fixture.withdrawals_unfracking` puts it). PLB only
/// requires the withdraw-0 of the credential named by the protocol-params
/// datum's `unfracking_cred` field at that index and checks nothing else.
fn run_plb_unfracking_dispatch(tx: Transaction) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    fixture.policy_protocol_params,
    None,
    SpendViaUnfracking { params_idx: 0, wdrl_idx: 0 },
    Void,
    tx,
  )
}

// --------------------------------------------------------------- happy paths

// v2 canonical case: the fracked A+B UTxO is acted on for A; the paired
// continuing output keeps B untouched, all of A regroups into its own
// UTxO at the same owner address, the issuer hook withdraw-0 is present.
test unfracking_split_acted_policy_from_fracked_utxo_succeeds() {
  run_unfracking(valid_unfracking_tx())
}

// v2: consolidation across multiple fracked UTxOs of the same owner —
// N inputs, N paired continuing outputs (each keeping its non-acted
// remainder), one extra output collecting ALL the acted tokens.
test unfracking_multi_utxo_consolidation_succeeds() {
  let input_2 = fixture.some_input_with_programmable_tokens(
    [(policy_a, "FOO", 50), (policy_b, "BAR", 50)],
    "unfracking input 2",
  )
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
        "unfracking input",
      ),
      input_2,
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 50)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 150)]),
    ],
  }
  run_unfracking(tx)
}

// A destination output (a freshly created PLB UTxO receiving the regrouped
// acted tokens) carrying a datum HASH is rejected: it would be unspendable
// without the preimage, so it could never be seized. One delta against the
// consolidation happy path: the acted-policy destination is datum-hashed.
test unfracking_rejects_datum_hash_destination() fail {
  let input_2 = fixture.some_input_with_programmable_tokens(
    [(policy_a, "FOO", 50), (policy_b, "BAR", 50)],
    "unfracking input 2",
  )
  let destination_with_hash = Output {
    ..fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 150)]),
    datum: DatumHash(
      #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef00",
    ),
  }
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
        "unfracking input",
      ),
      input_2,
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 50)]),
      destination_with_hash,
    ],
  }
  run_unfracking(tx)
}

// The reference-script half of the same guard: a large one would bloat every
// future seizure of the restructured UTxO, which must reproduce it byte-for-byte.
test unfracking_rejects_reference_script_destination() fail {
  let input_2 = fixture.some_input_with_programmable_tokens(
    [(policy_a, "FOO", 50), (policy_b, "BAR", 50)],
    "unfracking input 2",
  )
  let destination_with_ref_script = Output {
    ..fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 150)]),
    reference_script: Some(
      #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2",
    ),
  }
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
        "unfracking input",
      ),
      input_2,
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 50)]),
      destination_with_ref_script,
    ],
  }
  run_unfracking(tx)
}

// Full strip: a PARTIAL strip leaving acted residue in the continuing
// output is rejected. Requirements-driven: in the freeze case the
// residue keeps the continuing UTxO needing the frozen policy's
// transfer proof (still stuck), and partial same-owner rebalancing is
// a transfer's job — with transfer logic as the proper bouncer — not
// this bypass's.
test unfracking_fails_partial_strip_residue_in_pair() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(policy_a, "FOO", 40), (policy_b, "BAR", 100)],
      ),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 60)]),
    ],
  }
  run_unfracking(tx)
}

// Full strip: a no-change pair (the acted balance stays put entirely)
// is rejected for the same reason as the partial residue above — and it
// would be pure churn besides.
test unfracking_fails_acted_tokens_unmoved_in_pair() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
      ),
    ],
  }
  run_unfracking(tx)
}

// v2: paired outputs may start later in the outputs list; earlier
// owner-address outputs (here: the regrouped acted tokens) are counted
// by the drop-accumulate walk. Mirrors third_party_act_prog_outputs_skipped.
test unfracking_paired_outputs_skipped_succeeds() {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
    ],
  }
  run_unfracking_with(
    tx,
    UnfrackingRedeemer {
      params_idx: 0,
      registry_node_idx: 1,
      outputs_start_idx: 1,
    },
  )
}

// v2: ada is deliberately UNCONSTRAINED per pair — an increase passes.
// (Contrast: ThirdPartyAct ratchets, issue #96 — here the single owner
// authorised the action and ada is not a programmable asset.)
test unfracking_pair_ada_increase_succeeds() {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      output_with_extra_lovelace([(policy_b, "BAR", 100)], 2),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
    ],
  }
  run_unfracking(tx)
}

// v2: ada decrease passes too — the owner is free to rebalance min-ADA
// across the restructured layout (and a min-ADA parameter rise can
// never brick the action).
test unfracking_pair_ada_decrease_succeeds() {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      output_with_extra_lovelace([(policy_b, "BAR", 100)], -2),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
    ],
  }
  run_unfracking(tx)
}

// v2: vkey-staked owner authorises by signing; no transfer-logic
// withdraw-0 needed. Hook and validator withdrawals remain.
test unfracking_vkey_owner_succeeds() {
  let vkey_cred = VerificationKey(second_vkey_pkh)
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_with_programmable_tokens_with(
        vkey_cred,
        [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
        "vkey input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens_with(
        vkey_cred,
        [(policy_b, "BAR", 100)],
      ),
      fixture.some_output_with_programmable_tokens_with(
        vkey_cred,
        [(policy_a, "FOO", 100)],
      ),
    ],
    extra_signatories: [second_vkey_pkh],
    withdrawals: withdrawals_vkey_owner,
  }
  run_unfracking(tx)
}

// v2: an unregistered token parked in the fracked UTxO is pinned by the
// same non-acted byte-identity as any registered policy — it stays in
// the continuing output, and the action still succeeds.
test unfracking_preserves_unregistered_token_succeeds() {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [
          (policy_a, "FOO", 100), (policy_b, "BAR", 100),
          (policy_unrelated, "RAND", 1),
        ],
        "unfracking input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(policy_b, "BAR", 100), (policy_unrelated, "RAND", 1)],
      ),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
    ],
  }
  run_unfracking(tx)
}

// Adversarial-review coverage: a negative outputs_start_idx behaves
// exactly like 0 (the drop walk treats n <= 0 as "drop nothing") — an
// off-chain builder bug cannot unlock a different pairing.
test unfracking_negative_outputs_start_idx_behaves_as_zero() {
  run_unfracking_with(
    valid_unfracking_tx(),
    UnfrackingRedeemer {
      params_idx: 0,
      registry_node_idx: 1,
      outputs_start_idx: -1,
    },
  )
}

// Layout freedom promised by the design: the stripped tokens may split
// across SEVERAL owner-address outputs — the conservation fold sums them.
test unfracking_regroup_across_multiple_outputs_succeeds() {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 60)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 40)]),
    ],
  }
  run_unfracking(tx)
}

// The acted policy may carry several asset names — the full strip moves
// the ENTIRE per-policy entry, and conservation compares whole dicts.
test unfracking_multi_asset_name_acted_policy_succeeds() {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_a, "FOO2", 7), (policy_b, "BAR", 100)],
        "unfracking input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_a, "FOO2", 7)],
      ),
    ],
  }
  run_unfracking(tx)
}

// Non-PLB inputs (fee fuel etc.) interleave freely: they are skipped by
// the owner pinning and by the pair walk without consuming an output.
test unfracking_interleaved_non_plb_input_succeeds() {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_fuel("fee fuel"),
      fixture.some_input_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
        "unfracking input",
      ),
    ],
  }
  run_unfracking(tx)
}

// --------------------------------------------------------------- failure cases
//
// One delta per failure test (CLAUDE.md test conventions). Each test
// builds on `valid_unfracking_tx()` and overrides exactly one field.

// v2 default-deny: the acted policy's registry node has NO hook set
// (`empty_vkey`) — unfracking is forbidden outright. There is no
// explicit sentinel check: the invocation lookup itself is
// unsatisfiable, because no ledger tx can carry a withdrawal keyed by
// an empty hash. The hook withdrawal is still present in the tx; the
// ONE delta is the registry field.
test unfracking_fails_when_hook_unset() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      node_ref_with_hook(empty_vkey),
    ],
  }
  run_unfracking(tx)
}

// v2: the hook is set but its withdraw-0 is NOT invoked — the action
// must fail. ONE delta: the hook withdrawal is removed.
test unfracking_fails_when_hook_not_invoked() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    withdrawals: withdrawals_without_hook,
  }
  run_unfracking(tx)
}

// v2: acted tokens may ONLY land at the owner address. ONE delta: the
// regrouped output carries Eve's stake credential — the owner-side
// conservation total comes up short and the equality rejects.
test unfracking_fails_acted_tokens_to_other_stake_cred() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens_with(
        VerificationKey(eve_vkey_pkh),
        [(policy_a, "FOO", 100)],
      ),
    ],
  }
  run_unfracking(tx)
}

// v2: every NON-acted policy must be byte-identical across the pair.
// ONE delta: the continuing output keeps only 90 of the 100 B.
test unfracking_fails_non_acted_delta_in_pair() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 90)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
    ],
  }
  run_unfracking(tx)
}

// v2: the paired continuing output must preserve the datum — a
// co-resident policy's stateful datum cannot be disturbed by another
// policy's unfracking. ONE delta: an inline datum appears on the
// continuing output (the input has NoDatum).
test unfracking_fails_pair_datum_changed() fail {
  let cont = fixture.some_output_with_programmable_tokens(
    [(policy_b, "BAR", 100)],
  )
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      Output { ..cont, datum: InlineDatum(as_data(Void)) },
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
    ],
  }
  run_unfracking(tx)
}

// v2: the paired continuing output must preserve the reference script
// (Finding 13 applies to unfracking too). ONE delta: a reference
// script appears on the continuing output.
test unfracking_fails_pair_reference_script_changed() fail {
  let cont = fixture.some_output_with_programmable_tokens(
    [(policy_b, "BAR", 100)],
  )
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      Output {
        ..cont,
        reference_script: Some(
          #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1",
        ),
      },
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
    ],
  }
  run_unfracking(tx)
}

// v2: minting is forbidden — unfracking is strictly value-preserving.
// The outputs are adjusted so ONLY the mint-zero rule can reject
// (isolation: with the mint accepted, conservation would balance).
test unfracking_fails_with_mint() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    mint: from_asset(policy_a, "FOO", 50),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 150)]),
    ],
  }
  run_unfracking(tx)
}

// v2: burning is forbidden for the same reason.
test unfracking_fails_with_burn() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    mint: from_asset(policy_a, "FOO", -50),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 50)]),
    ],
  }
  run_unfracking(tx)
}

// The mint-zero rule is TOTAL: even a mint of an unrelated policy is
// rejected — unfracking is pure restructuring and no mint has any
// business riding it. ONE delta: an unrelated mint appears.
test unfracking_fails_with_unrelated_policy_mint() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    mint: from_asset(policy_unrelated, "RAND", 5),
  }
  run_unfracking(tx)
}

// v2 single-owner invariant: a second PLB input with a DIFFERENT stake
// credential is rejected — cross-owner restructuring is a transfer in
// disguise. Both creds are authorised (signature + script withdrawal),
// so the only rejection can come from the single-owner rule; the
// paired outputs mirror each input to keep the pair checks satisfied.
test unfracking_fails_two_stake_creds_among_inputs() fail {
  let vkey_cred = VerificationKey(second_vkey_pkh)
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
        "unfracking input",
      ),
      fixture.some_input_with_programmable_tokens_with(
        vkey_cred,
        [(policy_a, "FOO", 50)],
        "second owner input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens_with(vkey_cred, []),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 150)]),
    ],
    extra_signatories: [second_vkey_pkh],
  }
  run_unfracking(tx)
}

// v2: a paired input must already hold the acted policy — a UTxO with
// none of it has no business in this action (spend it via a transfer).
// ONE delta: a second input holding only B joins the action.
test unfracking_fails_input_without_acted_policy() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
        "unfracking input",
      ),
      fixture.some_input_with_programmable_tokens(
        [(policy_b, "BAR", 50)],
        "no acted policy input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 50)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
    ],
  }
  run_unfracking(tx)
}

// v2: script-staked owner requires the stake script's withdraw-0. ONE
// delta: the transfer-logic withdrawal is removed (the unfracking and
// hook withdrawals remain — they are plumbing, not owner authorisation).
test unfracking_fails_missing_owner_authorisation() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    withdrawals: [
      Pair(fixture.credential_validator_unfracking, 0),
      Pair(fixture.credential_unfracking_hook, 0),
    ],
  }
  run_unfracking(tx)
}

// v2 conservation is a strict EQUALITY: fabricated surplus (150 out
// where 100 came in, no mint) is rejected, not just leakage.
test unfracking_fails_acted_surplus() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 150)]),
    ],
  }
  run_unfracking(tx)
}

// v2 conservation, other direction: a shortfall means acted tokens
// leaked somewhere off the owner address.
test unfracking_fails_acted_shortfall() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 60)]),
    ],
  }
  run_unfracking(tx)
}

// v2: the registry node reference must carry the registry NFT — a
// forged node (right shape, wrong NFT policy) is rejected at lookup.
test unfracking_fails_registry_node_wrong_nft() fail {
  let genuine = fixture.some_reference_input_unfracking_registry_node(
    policy_a,
    "unfracking registry node",
  )
  let forged = Input {
    ..genuine,
    output: Output {
      ..genuine.output,
      value: fixture.min_ada_value
        |> merge(from_asset(policy_unrelated, "FAKE", 1)),
    },
  }
  let tx = Transaction {
    ..valid_unfracking_tx(),
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      forged,
    ],
  }
  run_unfracking(tx)
}

// ------------------------------------------------------- PLB dispatch
//
// Under SpendViaUnfracking, programmable_logic_base does not validate the
// unfracking invariants itself — it only requires the unfracking withdraw-0
// at the witnessed index (its credential read from the params datum).

// The dispatch accepts as soon as the unfracking withdraw-0 is where the
// redeemer says it is.
test plb_unfracking_dispatch_accepts_when_unfracking_script_invoked() {
  run_plb_unfracking_dispatch(valid_unfracking_tx())
}

// SpendViaUnfracking without the unfracking withdraw-0 must be rejected by
// PLB — otherwise the redeemer would unlock PLB inputs with NO invariant
// checks at all. ONE delta: the unfracking withdrawal is removed (the
// transfer-logic withdrawal now sits at index 0 and fails the equality).
test plb_unfracking_dispatch_rejects_when_unfracking_script_not_invoked() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    withdrawals: [
      Pair(fixture.credential_transfer_logic, 0),
      Pair(fixture.credential_unfracking_hook, 0),
    ],
  }
  run_plb_unfracking_dispatch(tx)
}

// Responsibility boundary: PLB deliberately does NOT check the unfracking
// invariants — a conservation-violating tx still passes the PLB dispatch
// because the unfracking withdraw-0 is present. The same tx is rejected by
// unfracking itself (`unfracking_fails_acted_surplus`); on-chain BOTH
// scripts must pass.
test plb_unfracking_dispatch_delegates_invariants_to_unfracking_script() {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 150)]),
    ],
  }
  run_plb_unfracking_dispatch(tx)
}

// The dispatch's target credential is READ FROM the protocol-params datum
// (`unfracking_cred`, field 4) — not baked into the validator. ONE delta:
// the params datum names Eve's credential as the unfracking script; the
// genuine withdraw-0 no longer matches and PLB rejects.
test plb_unfracking_dispatch_sources_cred_from_protocol_params() fail {
  let tx = Transaction {
    ..valid_unfracking_tx(),
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          unfracking_cred: VerificationKey(eve_vkey_pkh),
        },
        "protocol params",
      ),
      fixture.some_reference_input_unfracking_registry_node(
        policy_a,
        "unfracking registry node",
      ),
    ],
  }
  run_plb_unfracking_dispatch(tx)
}

/// Replica of the protocol-params datum shape BEFORE Finding 17 added
/// `unfracking_cred`. Used to pin which dispatch arms require the extended
/// datum.
type LegacyTwoFieldParams {
  registry_node_cs: ByteArray,
  prog_logic_cred: Credential,
}

// A legacy 2-field params datum cannot authorise a SpendViaUnfracking — the
// arm extracts datum field 4 and crashes when it is absent.
test plb_unfracking_dispatch_fails_on_legacy_two_field_params() fail {
  let modern = fixture.some_reference_input_protocol_params(
    fixture.protocol_params,
    "protocol params",
  )
  let legacy = Input {
    ..modern,
    output: Output {
      ..modern.output,
      datum: InlineDatum(
        as_data(
          LegacyTwoFieldParams {
            registry_node_cs: fixture.policy_tokens_registry,
            prog_logic_cred: fixture.credential_validator_logic_base,
          },
        ),
      ),
    },
  }
  let tx = Transaction {
    ..valid_unfracking_tx(),
    reference_inputs: [
      legacy,
      fixture.some_reference_input_unfracking_registry_node(
        policy_a,
        "unfracking registry node",
      ),
    ],
  }
  run_plb_unfracking_dispatch(tx)
}

// ------------------------------------------------------- end-to-end composition

// The full on-chain composition of a v2 unfracking transaction — every
// framework script that runs on-chain must accept the same tx:
//
//   * programmable_logic_base.spend (SpendViaUnfracking) for the fracked
//     PLB input — dispatching straight to the unfracking validator,
//   * unfracking.withdraw (invariants + issuer-hook gating).
//
// The transfer validator is not invoked. (The issuer's hook script itself is
// substandard territory; the framework's obligation — that its withdrawal is
// present — is what the unfracking validator asserts.)
test unfracking_full_composition_succeeds() {
  let tx = valid_unfracking_tx()
  and {
    run_plb_unfracking_dispatch(tx),
    run_unfracking(tx),
  }
}
