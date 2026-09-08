//// Tests for the upgrade authority: config genesis (`mint`), config update
//// (`spend`), the trampoline decision (`withdraw`) and registration
//// (`publish`).
////
//// The tree semantics themselves — what `satisfied` and `well_formed` mean —
//// are tested in `lib/multisig.ak`, unit and property. Here the question is
//// only whether each handler feeds the tree the right evidence and holds the
//// structural rails around the config UTxO. Every failure test is one delta
//// against a happy-path fixture.

use aiken/collection/list
use aiken/interval
use aiken/primitive/bytearray
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{Value, ada_asset_name, ada_policy_id}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use multisig.{After, AllOf, AtLeast, MultisigScript, Signature, max_size}
use upgrade_multisig.{upgrade_multisig_token}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const alice: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const bob: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

const carol: ByteArray =
  #"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3"

const mallory: ByteArray =
  #"dededededededededededededededededededededededededededede"

/// This script's own hash: the config NFT policy, the config address's payment
/// credential and the withdraw-0 credential, all at once.
const own_hash: ByteArray =
  #"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e"

/// A different withdraw-0 script, for the `Script` leaf.
const governance_hash: ByteArray =
  #"6060606060606060606060606060606060606060606060606060606060"

const seed_ref: OutputReference =
  OutputReference {
    transaction_id: #"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd0000",
    output_index: 0,
  }

const own_ref: OutputReference =
  OutputReference {
    transaction_id: #"ababababababababababababababababababababababababababababab0001",
    output_index: 0,
  }

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The federation as deployed: 2-of-3.
fn two_of_three() -> MultisigScript {
  AtLeast {
    required: 2,
    scripts: [
      Signature { key_hash: alice },
      Signature { key_hash: bob },
      Signature { key_hash: carol },
    ],
  }
}

/// A rotated federation: bob out, mallory in. Still 2-of-3.
fn rotated() -> MultisigScript {
  AtLeast {
    required: 2,
    scripts: [
      Signature { key_hash: alice },
      Signature { key_hash: carol },
      Signature { key_hash: mallory },
    ],
  }
}

/// Ill-formed: threshold above the member count.
fn unsatisfiable() -> MultisigScript {
  AtLeast {
    required: 3,
    scripts: [Signature { key_hash: alice }, Signature { key_hash: bob }],
  }
}

/// Exactly `address.from_script(own_hash)`: no stake credential, which is what
/// the mint handler pins.
fn config_address() -> Address {
  Address { payment_credential: Script(own_hash), stake_credential: None }
}

fn config_value() -> Value {
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)
    |> assets.add(own_hash, upgrade_multisig_token, 1)
}

fn config_output(tree: MultisigScript) -> Output {
  Output {
    address: config_address(),
    value: config_value(),
    datum: InlineDatum(as_data(tree)),
    reference_script: None,
  }
}

fn config_input(tree: MultisigScript) -> Input {
  Input { output_reference: own_ref, output: config_output(tree) }
}

fn seed_input() -> Input {
  Input {
    output_reference: seed_ref,
    output: Output {
      address: Address {
        payment_credential: VerificationKey(alice),
        stake_credential: None,
      },
      value: assets.from_lovelace(5_000_000),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

// -- genesis -----------------------------------------------------------------

fn genesis_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [seed_input()],
    mint: assets.from_asset(own_hash, upgrade_multisig_token, 1),
    outputs: [config_output(two_of_three())],
  }
}

fn call_mint(tx: Transaction) -> Bool {
  upgrade_multisig.upgrade_multisig.mint(seed_ref, Void, own_hash, tx)
}

// -- update ------------------------------------------------------------------

/// Rotate bob out for mallory, signed by alice + bob (the OLD tree's 2-of-3).
fn update_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [config_input(two_of_three())],
    outputs: [config_output(rotated())],
    extra_signatories: [alice, bob],
  }
}

fn call_spend(old: MultisigScript, tx: Transaction) -> Bool {
  upgrade_multisig.upgrade_multisig.spend(
    seed_ref,
    Some(old),
    Void,
    own_ref,
    tx,
  )
}

// -- authorisation -----------------------------------------------------------

fn config_reference(tree: MultisigScript) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c",
      output_index: 0,
    },
    output: config_output(tree),
  }
}

fn withdraw_tx(
  tree: MultisigScript,
  signatories: List<ByteArray>,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [config_reference(tree)],
    extra_signatories: signatories,
  }
}

fn call_withdraw(tx: Transaction) -> Bool {
  upgrade_multisig.upgrade_multisig.withdraw(
    seed_ref,
    Void,
    Script(own_hash),
    tx,
  )
}

// ---------------------------------------------------------------------------
// Genesis
// ---------------------------------------------------------------------------

test genesis_valid() {
  call_mint(genesis_tx())
}

// Lovelace above the minimum is fine: the NFT rail is strict about assets,
// not about ada.
test genesis_allows_extra_ada() {
  let richer = Output {
    ..config_output(two_of_three()),
    value: config_value()
      |> assets.add(ada_policy_id, ada_asset_name, 3_000_000),
  }
  call_mint(Transaction { ..genesis_tx(), outputs: [richer] })
}

// One-shot: the seed UTxO must be consumed.
test genesis_fails_without_consuming_seed() fail {
  call_mint(Transaction { ..genesis_tx(), inputs: [] })
}

test genesis_fails_minting_two_tokens() fail {
  call_mint(
    Transaction {
      ..genesis_tx(),
      mint: assets.from_asset(own_hash, upgrade_multisig_token, 2),
    },
  )
}

test genesis_fails_wrong_token_name() fail {
  call_mint(
    Transaction {
      ..genesis_tx(),
      mint: assets.from_asset(own_hash, "Other", 1),
    },
  )
}

// The NFT must be locked at THIS script, wearing its spending hat.
test genesis_fails_nft_at_foreign_address() fail {
  let elsewhere = Output {
    ..config_output(two_of_three()),
    address: Address {
      payment_credential: VerificationKey(mallory),
      stake_credential: None,
    },
  }
  call_mint(Transaction { ..genesis_tx(), outputs: [elsewhere] })
}

// `address.from_script` carries no stake credential; an address with one is a
// different address, and a UTxO there would not be found by consumers deriving
// the config address from the hash alone.
test genesis_fails_with_stake_credential() fail {
  let staked = Output {
    ..config_output(two_of_three()),
    address: Address {
      ..config_address(),
      stake_credential: Some(Inline(VerificationKey(alice))),
    },
  }
  call_mint(Transaction { ..genesis_tx(), outputs: [staked] })
}

test genesis_fails_reference_script_attached() fail {
  let with_script = Output {
    ..config_output(two_of_three()),
    reference_script: Some(governance_hash),
  }
  call_mint(Transaction { ..genesis_tx(), outputs: [with_script] })
}

// Born well-formed: the rail every update satisfies applies at genesis too, so
// the authority can never START as an unsatisfiable one.
test genesis_fails_malformed_tree() fail {
  call_mint(
    Transaction { ..genesis_tx(), outputs: [config_output(unsatisfiable())] },
  )
}

test genesis_fails_missing_inline_datum() fail {
  let hashed = Output {
    ..config_output(two_of_three()),
    datum: DatumHash(governance_hash),
  }
  call_mint(Transaction { ..genesis_tx(), outputs: [hashed] })
}

// `has_nft_strict` matches only a value whose non-ADA half is exactly the NFT,
// so an output bundling a second asset is never found.
test genesis_fails_junk_token_alongside_nft() fail {
  let bundled = Output {
    ..config_output(two_of_three()),
    value: config_value() |> assets.add(governance_hash, "junk", 1),
  }
  call_mint(Transaction { ..genesis_tx(), outputs: [bundled] })
}

// ---------------------------------------------------------------------------
// Config update
// ---------------------------------------------------------------------------

test update_valid() {
  call_spend(two_of_three(), update_tx())
}

// Lovelace is unconstrained relative to the input, as on `protocol_params`.
test update_allows_ada_change() {
  let leaner = Output {
    ..config_output(rotated()),
    value: assets.zero
      |> assets.add(ada_policy_id, ada_asset_name, 1_500_000)
      |> assets.add(own_hash, upgrade_multisig_token, 1),
  }
  call_spend(two_of_three(), Transaction { ..update_tx(), outputs: [leaner] })
}

// The whole point of the update path: a rotation is a datum change and the
// authority's credential does not move. Proven by re-running the trampoline
// against the ROTATED tree with the new member signing.
test update_then_withdraw_with_new_member() {
  and {
    call_spend(two_of_three(), update_tx()),
    call_withdraw(withdraw_tx(rotated(), [alice, mallory])),
    !call_withdraw_soft(withdraw_tx(rotated(), [bob, mallory])),
  }
}

test update_fails_missing_datum() fail {
  upgrade_multisig.upgrade_multisig.spend(
    seed_ref,
    None,
    Void,
    own_ref,
    update_tx(),
  )
}

// Below the OLD tree's threshold.
test update_fails_old_tree_unsatisfied() fail {
  call_spend(
    two_of_three(),
    Transaction { ..update_tx(), extra_signatories: [alice] },
  )
}

// The rail that makes rotation safe: the INCOMING tree has no say. Here the
// signatories satisfy the new tree (alice + mallory) but not the old one.
test update_fails_authorised_by_new_tree_only() fail {
  call_spend(
    two_of_three(),
    Transaction { ..update_tx(), extra_signatories: [alice, mallory] },
  )
}

// An authority cannot configure itself into a state it can never satisfy.
test update_fails_malformed_new_tree() fail {
  call_spend(
    two_of_three(),
    Transaction { ..update_tx(), outputs: [config_output(unsatisfiable())] },
  )
}

test update_fails_dropping_nft() fail {
  let without_nft = Output {
    ..config_output(rotated()),
    value: assets.from_lovelace(2_000_000),
  }
  call_spend(
    two_of_three(),
    Transaction { ..update_tx(), outputs: [without_nft] },
  )
}

test update_fails_injecting_token() fail {
  let bundled = Output {
    ..config_output(rotated()),
    value: config_value() |> assets.add(governance_hash, "junk", 1),
  }
  call_spend(two_of_three(), Transaction { ..update_tx(), outputs: [bundled] })
}

test update_fails_moving_address() fail {
  let moved = Output {
    ..config_output(rotated()),
    address: Address {
      payment_credential: VerificationKey(mallory),
      stake_credential: None,
    },
  }
  call_spend(two_of_three(), Transaction { ..update_tx(), outputs: [moved] })
}

/// An ada-only UTxO parked at the config address by anyone, with a datum of
/// the parker's choosing — here a tree mallory alone satisfies.
fn junk_at_config_address() -> Input {
  Input {
    output_reference: OutputReference { ..own_ref, output_index: 1 },
    output: Output {
      ..config_output(
        AtLeast { required: 1, scripts: [Signature { key_hash: mallory }] },
      ),
      value: assets.from_lovelace(2_000_000),
    },
  }
}

// Double satisfaction, genuine half: the config's own run passes with junk
// alongside. No input-count rail exists, and this test says so on purpose.
test update_passes_alongside_junk_input() {
  call_spend(
    two_of_three(),
    Transaction {
      ..update_tx(),
      inputs: [config_input(two_of_three()), junk_at_config_address()],
    },
  )
}

// Double satisfaction, the half that matters: the JUNK input's run fails even
// with mallory signing, because the one continuing output carries the NFT and
// the junk does not. Exact non-ADA conservation is the rail; the input count
// never was.
test update_fails_junk_run_alongside_genuine() fail {
  let junk = junk_at_config_address()
  upgrade_multisig.upgrade_multisig.spend(
    seed_ref,
    Some(AtLeast { required: 1, scripts: [Signature { key_hash: mallory }] }),
    Void,
    junk.output_reference,
    Transaction {
      ..update_tx(),
      inputs: [config_input(two_of_three()), junk],
      extra_signatories: [alice, bob, mallory],
    },
  )
}

test update_fails_two_continuing_outputs() fail {
  call_spend(
    two_of_three(),
    Transaction {
      ..update_tx(),
      outputs: [config_output(rotated()), config_output(rotated())],
    },
  )
}

test update_fails_reference_script_attached() fail {
  let with_script = Output {
    ..config_output(rotated()),
    reference_script: Some(governance_hash),
  }
  call_spend(
    two_of_three(),
    Transaction { ..update_tx(), outputs: [with_script] },
  )
}

test update_fails_missing_inline_datum() fail {
  let hashed = Output {
    ..config_output(rotated()),
    datum: DatumHash(governance_hash),
  }
  call_spend(two_of_three(), Transaction { ..update_tx(), outputs: [hashed] })
}

test update_fails_own_ref_not_among_inputs() fail {
  call_spend(
    two_of_three(),
    Transaction { ..update_tx(), inputs: [seed_input()] },
  )
}

// ---------------------------------------------------------------------------
// Authorisation (the trampoline target)
// ---------------------------------------------------------------------------

/// `satisfied` returns False rather than aborting, so a negative can be read
/// as a Bool when a test needs to combine it with positives.
fn call_withdraw_soft(tx: Transaction) -> Bool {
  call_withdraw(tx)
}

test withdraw_authorises_at_threshold() {
  call_withdraw(withdraw_tx(two_of_three(), [alice, carol]))
}

test withdraw_fails_below_threshold() fail {
  call_withdraw(withdraw_tx(two_of_three(), [alice]))
}

test withdraw_fails_non_members() fail {
  call_withdraw(withdraw_tx(two_of_three(), [mallory, alice]))
}

// No config UTxO among the reference inputs: nothing to evaluate.
test withdraw_fails_without_config_reference() fail {
  call_withdraw(
    Transaction {
      ..withdraw_tx(two_of_three(), [alice, bob]),
      reference_inputs: [],
    },
  )
}

test withdraw_fails_config_datum_not_inline() fail {
  let hashed = Input {
    ..config_reference(two_of_three()),
    output: Output {
      ..config_output(two_of_three()),
      datum: DatumHash(governance_hash),
    },
  }
  call_withdraw(
    Transaction {
      ..withdraw_tx(two_of_three(), [alice, bob]),
      reference_inputs: [hashed],
    },
  )
}

// The reward account must be THIS script; a key-hash account has no config.
test withdraw_fails_key_account() fail {
  upgrade_multisig.upgrade_multisig.withdraw(
    seed_ref,
    Void,
    VerificationKey(own_hash),
    withdraw_tx(two_of_three(), [alice, bob]),
  )
}

// The finder keys on the NFT, not on position: a junk reference input ahead of
// the config is skipped, and a UTxO at the config address WITHOUT the NFT is
// not mistaken for it.
test withdraw_finds_config_behind_lookalikes() {
  let junk = Input {
    ..seed_input(),
    output_reference: OutputReference { ..seed_ref, output_index: 7 },
  }
  let impostor = Input {
    ..config_reference(two_of_three()),
    output: Output {
      ..config_output(
        AtLeast { required: 1, scripts: [Signature { key_hash: mallory }] },
      ),
      value: assets.from_lovelace(2_000_000),
    },
  }
  call_withdraw(
    Transaction {
      ..withdraw_tx(two_of_three(), [alice, bob]),
      reference_inputs: [junk, impostor, config_reference(two_of_three())],
    },
  )
}

// `Script` leaf: another withdraw-0 script in the transaction satisfies it.
// This is the composition point for a governance-shaped authority.
test withdraw_honours_script_leaf() {
  let tree = multisig.Script { script_hash: governance_hash }
  call_withdraw(
    Transaction {
      ..withdraw_tx(tree, []),
      withdrawals: [Pair(Script(governance_hash), 0)],
    },
  )
}

test withdraw_fails_script_leaf_without_withdrawal() fail {
  let tree = multisig.Script { script_hash: governance_hash }
  call_withdraw(withdraw_tx(tree, [alice, bob, carol]))
}

// `After` leaf: approve now, execute only once the validity range starts at or
// after the configured time. This is the approve-then-delay shape from J2.
test withdraw_honours_after_timelock() {
  let tree = AllOf {
    scripts: [After { time: 1_000 }, Signature { key_hash: alice }],
  }
  call_withdraw(
    Transaction {
      ..withdraw_tx(tree, [alice]),
      validity_range: interval.after(1_000),
    },
  )
}

test withdraw_fails_before_timelock() fail {
  let tree = AllOf {
    scripts: [After { time: 1_000 }, Signature { key_hash: alice }],
  }
  call_withdraw(
    Transaction {
      ..withdraw_tx(tree, [alice]),
      validity_range: interval.after(999),
    },
  )
}

// An unbounded validity range never satisfies a time leaf: the transaction
// has to COMMIT to a window for the tree to have anything to check.
test withdraw_fails_timelock_with_unbounded_range() fail {
  let tree = AllOf {
    scripts: [After { time: 1_000 }, Signature { key_hash: alice }],
  }
  call_withdraw(withdraw_tx(tree, [alice]))
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

// MINR-057: a withdraw-0 credential must be registered before it can withdraw,
// and after Conway that needs the script's consent. Registration is allowed
// with no further condition — it grants nothing.
test publish_allows_registration() {
  upgrade_multisig.upgrade_multisig.publish(
    seed_ref,
    Void,
    RegisterCredential { credential: Script(own_hash), deposit: Never },
    transaction.placeholder,
  )
}

// Deregistering the authority's credential would make every future upgrade
// unauthorisable. Nothing legitimate needs it; it is refused outright.
test publish_rejects_deregistration() {
  !upgrade_multisig.upgrade_multisig.publish(
    seed_ref,
    Void,
    UnregisterCredential { credential: Script(own_hash), refund: Never },
    transaction.placeholder,
  )
}

// ---------------------------------------------------------------------------
// Cost ceiling
// ---------------------------------------------------------------------------

/// The most expensive tree the rail allows: `max_size` nodes, every leaf a
/// signature, threshold = every member, every member signing — so `AtLeast`
/// evaluates all leaves and each leaf scans the whole signatory list. Its
/// execution units in the test output are the authority's worst case per
/// upgrade; keep them in view when `max_size` is ever revisited.
fn worst_case_members() -> List<ByteArray> {
  list.map(
    list.range(1, max_size - 1),
    fn(i) {
      bytearray.push(
        bytearray.drop(
          #"00000000000000000000000000000000000000000000000000000000",
          1,
        ),
        i,
      )
    },
  )
}

test withdraw_at_max_size_tree() {
  let members = worst_case_members()
  let tree = AtLeast {
    required: list.length(members),
    scripts: list.map(members, fn(k) { Signature { key_hash: k } }),
  }
  call_withdraw(withdraw_tx(tree, members))
}

test update_at_max_size_tree() {
  let members = worst_case_members()
  let tree = AtLeast {
    required: list.length(members),
    scripts: list.map(members, fn(k) { Signature { key_hash: k } }),
  }
  call_spend(
    tree,
    Transaction {
      ..update_tx(),
      inputs: [config_input(tree)],
      outputs: [config_output(tree)],
      extra_signatories: members,
    },
  )
}
