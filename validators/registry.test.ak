//// Tests for the merged `registry` validator — both handlers in one module,
//// because they are now one script.
////
//// The single most important fixture fact in this file: `registry_script_hash`
//// is used simultaneously as
////   * the `policy_id` argument handed to the `mint` handler,
////   * the registry node NFT policy the `spend` handler works against, and
////   * the payment credential of `test_node_address`, where every node lives.
//// Pre-merge those were three separate test constants that only *happened* to
//// line up if the deployer wired them up correctly. Post-merge they cannot
//// diverge: one `validator` block, one hash.
////
//// COST RECORD — registry_mint + registry_spend → registry
//// ======================================================
////
//// "BEFORE" MEANS: this branch's pre-slice working tree
//// (`feat/dispatch-registry-merge-and-params-reduction`, post-dispatcher), NOT
//// `main@9db7e06`. On main `registry_spend` compiles to 1563 B rather than
//// 1553 B, which would make the Insert row -817 B instead of -807 B.
////
//// A. Reference-script footprint. Bytes of `compiledCode` in plutus.json,
////    unapplied / with compile-time parameters applied. One script after the
////    merge, so every "after" cell is the same number.
////
////    | path   | scripts loaded | before raw/applied | after raw/applied |  delta raw/applied |
////    |--------|----------------|--------------------|-------------------|--------------------|
////    | Init   | mint only      |      1928 / 2043   |     2674 / 2751   |  +746 /  +708      |
////    | Insert | mint + spend   |      3481 / 3631   |     2674 / 2751   |  -807 /  -880      |
////    | Update | spend only     |      1553 / 1588   |     2674 / 2751   | +1121 / +1163      |
////
////    Init and Update regress: each now carries the handler it does not use.
////    That is the accepted price. Insert — the only path that ever loaded both
////    scripts — is the row that had to improve, and does: -807 B unapplied,
////    -880 B applied, ~24% off the reference-script fee of every registration.
////
//// B. Execution units, happy paths.
////
////    | test                                | before cpu  | after cpu   | raw    | like-for-like |
////    |-------------------------------------|-------------|-------------|--------|---------------|
////    | registry_init_valid                 |  51,912,079 |  52,166,592 | +0.49% |    +0.49%     |
////    | registry_insert_valid               | 165,627,820 | 165,627,820 |  0.00% |     0.00%     |
////    | registry_insert_register_only_valid | 168,854,720 | 168,854,720 |  0.00% |     0.00%     |
////    | registry_spend_valid                |  47,544,702 |  27,859,687 | -41.40%|    -33.47%    |
////    | registry_spend_update_node          | 111,437,790 |  87,765,706 | -21.24%|    -17.02%    |
////
////    THE RAW COLUMN OVERSTATES THE SPEND ROWS. `aiken check` reports
////    execution units for the WHOLE test expression, fixture construction
////    included, and the pre-merge spend fixtures had to build a protocol-params
////    reference input carrying an inline `ProgrammableLogicGlobalParams` datum
////    — a fixture that does not exist after the merge because the validator no
////    longer demands one. Constructing it costs a MEASURED 5,667,325 cpu
////    (probe: the merged `spend_transaction()` with and without such a
////    reference input, which this handler ignores entirely — 33,527,012 vs
////    27,859,687). That is 29% of the spend saving and 24% of the update
////    saving. The like-for-like column subtracts it from the "before" figure:
////    the honest on-chain numbers are -33.5% and -17.0%. The remainder of the
////    old cost — a real saving — was the reference-input scan, the
////    inline-datum extraction and the whole-record deserialisation.
////
////    Init pays ~0.5% for building `Script(policy_id)` per invocation instead
////    of receiving a ready-made `Credential` as a parameter. The two Insert
////    rows are unchanged to the unit: the intended proof that the
////    `RegistryInsert` arm was carried over byte-for-byte.
////
////    PROVENANCE OF THE "BEFORE" COLUMN. Init and both Insert rows come
////    straight from `HEAD:validators/registry_mint.{ak,test.ak}` plus the two
////    fixture edits below, and reproduce to the unit. The two spend rows do
////    NOT come from any committed artefact: the pre-slice
////    `registry_spend.test.ak` was an UNCOMMITTED working-tree modification
////    that this slice deleted, and `HEAD`'s copy does not even compile against
////    this branch (its `ProgrammableLogicGlobalParams` literal still carries
////    `unfracking_cred` and `max_inline_datum_bytes`, which the dispatcher work
////    removed). To reproduce them: take `HEAD:validators/registry_spend.ak`
////    unchanged, rebuild the test fixture with the branch's 6-field params
////    datum, and confirm the UN-retrofitted figures first — they must read
////    42,812,458 and 111,437,790, which is the fidelity check on the
////    reconstruction. Then apply the retrofit and re-measure.
////
////    THE RETROFIT, exactly as measured (the "before" column is the pre-merge
////    validators against fixtures already moved to the merged world, so fixture
////    shape is not what moves):
////      1. mint side  — `test_node_address` payment credential becomes
////         `Script(test_policy_id)` (was a 4-byte `Script(#"cccccccc")`), and
////         both harnesses pass `Script(test_policy_id)` as
////         `registry_spend_cred`.
////      2. spend side — `test_node_addr_hash` becomes `test_registry_node_cs`,
////         collapsing address hash and node policy to one value.
////      3. spend side — every Some-branch fixture gains an input at
////         `placeholder_own_ref()` addressed to `test_node_address()`, holding
////         `min_ada + (test_registry_node_cs, "OriginNode", 1)` and an inline
////         `origin_node` datum.
////    An audit measurement of a DIFFERENT retrofit shape read 51,839,429 for
////    `registry_spend_valid`; the figure recorded here is the one produced by
////    the three edits above and nothing else.

// ===========================================================================
// Designed out by the registry merge
//
// These tests existed against `registry_spend` and have no successor here.
// They are not omissions — the code paths they covered no longer exist.
//
//   * fails_no_protocol_params_ref_input (registry_spend.test.ak:204) — the
//     spend handler reads no reference input.
//   * fails_wrong_protocol_params_cs_in_ref_input (:220) — same.
//   * fails_no_inline_datum_on_params (:235) — same.
//   * fails_invalid_datum_type (:255) — same.
//   * registry_spend_valid_multiple_ref_inputs (:189), a POSITIVE — there is
//     no reference-input scan left to disambiguate.
//   * "the params datum names the wrong registry policy" (never written) —
//     the registry policy is the handler's own script hash, read off the UTxO
//     being spent. A params datum cannot lie about it because nothing reads a
//     params datum.
//
// The discriminating pair below —
// `registry_spend_derives_node_policy_from_its_own_address` and
// `registry_spend_fails_node_mint_under_a_policy_that_is_not_its_address` —
// is the statement that replaces the whole group. It is a PAIR on purpose:
// a lone positive here would be satisfied by any constant, and so would
// assert nothing about derivation.
// ===========================================================================

use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, Transaction,
  find_input,
}
use issuance_mint
use registry
use registry_node.{RegistryNode, empty_vkey, origin_node, origin_node_tn}
use types.{
  IssuanceCborHex, MintingRegistryProof, RefInput, RegistryInit, RegistryInsert,
  RegistryRedeemer,
}
use utils.{apply_hashed_parameter}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_utxo_ref = OutputReference { transaction_id: #"00", output_index: 0 }

/// A fake issuance_cbor_hex currency symbol (28 bytes)
const test_issuance_cbor_hex_cs: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

/// THE hash. One `validator` block ⇒ one script hash, so this single constant
/// is the mint handler's `policy_id`, the registry node NFT policy the spend
/// handler derives, and the payment credential of every node UTxO.
const registry_script_hash: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

/// Address for node outputs — the registry script's own address.
const test_node_address =
  Address {
    payment_credential: Script(registry_script_hash),
    stake_credential: None,
  }

/// Address for a generic input. Deliberately NOT the registry script hash —
/// the Finding 03 negatives send node outputs here.
const test_input_address =
  Address { payment_credential: Script(#"dddddddd"), stake_credential: None }

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

/// Prefix / postfix for issuance script reconstruction
const test_prefix = #"0102"

const test_postfix = #"0304"

/// The 28-byte hash that the issuance template is parameterised with.
/// Doubles as:
///   * the inner hash of `test_inserted_minting_logic_cred` (see below),
///   * the `hashed_param` value used by `apply_hashed_parameter` to derive
///     `computed_key()`.
/// Keeping a single constant for both forces the cryptographic-binding
/// invariant `hash(minting_logic_script) == apply_hashed_parameter input`
/// to hold by construction in every test.
const test_hashed_param =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

/// Substandard minting-logic credential placed in the new RegistryNode's
/// `minting_logic_script` field AND in the matching `RegistryInsert`
/// redeemer. Its inner 28-byte hash equals `test_hashed_param`, so the
/// `is_programmable_token_id_valid` check passes.
const test_inserted_minting_logic_cred: Credential = Script(test_hashed_param)

// CIP-67 label 333 (FT) prefix + "MyToken" hex
const cip68_ft_name = #"000f41414d79546f6b656e"

// CIP-67 label 100 (reference) prefix + "MyToken" hex
const cip68_ref_name = #"000643b04d79546f6b656e"

// ---------------------------------------------------------------------------
// Mint-side helpers
// ---------------------------------------------------------------------------

/// Build the 28-byte key that `is_programmable_token_id_valid` expects.
fn computed_key() -> ByteArray {
  apply_hashed_parameter(test_prefix, test_postfix, test_hashed_param)
}

/// Origin node output: key=#"", next=0xff…ff, empty credentials
fn origin_node_output() -> Output {
  Output {
    address: test_node_address,
    value: min_ada
      |> assets.add(registry_script_hash, origin_node_tn, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: #"",
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
          minting_logic_script: empty_vkey,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

/// Build a covering node input (origin node as input)
fn covering_node_input() -> Input {
  Input {
    output_reference: OutputReference { transaction_id: #"01", output_index: 0 },
    output: Output {
      address: test_node_address,
      value: min_ada
        |> assets.add(registry_script_hash, origin_node_tn, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: #"",
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: empty_vkey,
            third_party_transfer_logic_script: empty_vkey,
            minting_logic_script: empty_vkey,
            unfracking_logic_script: empty_vkey,
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    },
  }
}

/// Updated covering node output after insert: next → computed_key
fn updated_covering_node_output() -> Output {
  let key = computed_key()
  Output {
    address: test_node_address,
    value: min_ada
      |> assets.add(registry_script_hash, origin_node_tn, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: #"",
          next: key,
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
          minting_logic_script: empty_vkey,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

/// Inserted node output: key=computed_key, next=0xff…ff
fn inserted_node_output() -> Output {
  let key = computed_key()
  Output {
    address: test_node_address,
    value: min_ada
      |> assets.add(registry_script_hash, key, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key,
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: Script(
            #"55555555555555555555555555555555555555555555555555555555",
          ),
          third_party_transfer_logic_script: Script(
            #"66666666666666666666666666666666666666666666666666666666",
          ),
          minting_logic_script: test_inserted_minting_logic_cred,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

/// Reference input carrying the IssuanceCborHex NFT
fn issuance_ref_input() -> Input {
  Input {
    output_reference: OutputReference { transaction_id: #"02", output_index: 0 },
    output: Output {
      address: test_input_address,
      value: min_ada
        |> assets.add(test_issuance_cbor_hex_cs, #"00", 1),
      datum: InlineDatum(
        as_data(
          IssuanceCborHex {
            prefix_cbor_hex: test_prefix,
            postfix_cbor_hex: test_postfix,
          },
        ),
      ),
      reference_script: None,
    },
  }
}

/// A basic input that spends test_utxo_ref (for one-shot check)
fn utxo_ref_input() -> Input {
  Input {
    output_reference: test_utxo_ref,
    output: Output {
      address: test_input_address,
      value: min_ada,
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn call_init_validator(tx: Transaction) -> Bool {
  registry.registry.mint(
    test_utxo_ref,
    test_issuance_cbor_hex_cs,
    RegistryInit,
    registry_script_hash,
    tx,
  )
}

fn call_insert_validator(redeemer: RegistryRedeemer, tx: Transaction) -> Bool {
  registry.registry.mint(
    test_utxo_ref,
    test_issuance_cbor_hex_cs,
    redeemer,
    registry_script_hash,
    tx,
  )
}

// ---------------------------------------------------------------------------
// Spend-side helpers
// ---------------------------------------------------------------------------

const test_node_key: ByteArray =
  #"11111111111111111111111111111111111111111111111111111111"

const test_node_next: ByteArray =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

const test_minting_logic_hash: ByteArray =
  #"22222222222222222222222222222222222222222222222222222222"

const test_transfer_old: ByteArray =
  #"33333333333333333333333333333333333333333333333333333333"

const test_transfer_new: ByteArray =
  #"44444444444444444444444444444444444444444444444444444444"

const test_third_party_old: ByteArray =
  #"55555555555555555555555555555555555555555555555555555555"

const test_third_party_new: ByteArray =
  #"66666666666666666666666666666666666666666666666666666666"

const test_global_new: ByteArray =
  #"77777777777777777777777777777777777777777777777777777777"

const test_attacker_addr_hash: ByteArray =
  #"99999999999999999999999999999999999999999999999999999999"

const test_other_minting_hash: ByteArray =
  #"abababababababababababababababababababababababababababab"

/// A real (non-origin) covering node spent during an insert.
const test_covering_key: ByteArray =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const test_prog_logic_hash: ByteArray =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

/// OutputReference of the registry node being spent.
fn spend_own_ref() -> OutputReference {
  OutputReference {
    transaction_id: #"3333333333333333333333333333333333333333333333333333333333333333",
    output_index: 0,
  }
}

/// The node UTxO at `spend_own_ref()`: node NFT (token name == key) + inline
/// datum, sitting at the registry script's own address. EVERY spend fixture
/// carries one — the merged handler resolves `own_ref` unconditionally, on
/// both branches, because that is where it reads the node NFT policy from.
fn registry_node_input(node: RegistryNode) -> Input {
  Input {
    output_reference: spend_own_ref(),
    output: Output {
      address: test_node_address,
      value: min_ada |> assets.add(registry_script_hash, node.key, 1),
      datum: InlineDatum(as_data(node)),
      reference_script: None,
    },
  }
}

fn registry_node_output(node: RegistryNode) -> Output {
  Output {
    address: test_node_address,
    value: min_ada |> assets.add(registry_script_hash, test_node_key, 1),
    datum: InlineDatum(as_data(node)),
    reference_script: None,
  }
}

/// Spend harness.
///
/// About the `expect Some(_) = find_input(..)` below — read this before
/// trusting it, because the obvious reading is WRONG. The handler resolves
/// `own_ref` before either branch runs, so a fixture whose `own_ref` matches no
/// input aborts before the check under test is ever reached (MINR triage #204).
/// This `expect` catches that — but only for the POSITIVE tests, where an abort
/// is a visible failure.
///
/// It does NOT protect the negatives. In Aiken a `test .. fail` passes on an
/// ABORT just as it passes on `False`, so for every `.. fail` test in this
/// module the `expect` merely relocates an unreachable-fixture abort from
/// inside the validator to inside the harness; the test still passes, and still
/// for the wrong reason. No assertion placed here can fix that — it is a
/// property of `fail` tests, not of this harness.
///
/// What actually keeps the negatives honest is FIXTURE DISCIPLINE, and it is
/// the reader's job to keep it: every spend fixture in this module obtains its
/// node input from `registry_node_input()` (or `alt_node_input()`) at
/// `spend_own_ref()`, whether it spreads a positive base transaction or builds
/// its own from `transaction.placeholder`. A new negative that builds its
/// transaction from `transaction.placeholder` without a node input would pass
/// vacuously and nothing here would catch it. When adding one, either spread an
/// existing base tx or prove the test bites by mutating the guard it targets.
fn call_spend(
  datum: Option<RegistryNode>,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  expect Some(_) = find_input(tx.inputs, own_ref)
  registry.registry.spend(
    test_utxo_ref,
    test_issuance_cbor_hex_cs,
    datum,
    as_data(Void),
    own_ref,
    tx,
  )
}

/// The node before the update.
fn old_registry_node() -> RegistryNode {
  RegistryNode {
    key: test_node_key,
    next: test_node_next,
    minting_logic_script: Script(test_minting_logic_hash),
    transfer_logic_script: Script(test_transfer_old),
    third_party_transfer_logic_script: Script(test_third_party_old),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }
}

/// The node after the update — only the 3 mutable fields change.
fn new_registry_node() -> RegistryNode {
  RegistryNode {
    ..old_registry_node(),
    transfer_logic_script: Script(test_transfer_new),
    third_party_transfer_logic_script: Script(test_third_party_new),
    unfracking_logic_script: empty_vkey,
    global_state_cs: test_global_new,
  }
}

fn covering_node() -> RegistryNode {
  RegistryNode {
    ..origin_node,
    key: test_covering_key,
    minting_logic_script: Script(test_prog_logic_hash),
  }
}

/// Base Some-branch tx: a registry node NFT is minted under the registry
/// script's own hash, so this is the covering-node spend of an insert.
fn spend_transaction() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [registry_node_input(origin_node)],
    mint: from_asset(registry_script_hash, "OriginNode", 1),
  }
}

/// A valid in-place update tx (None branch): no registry mint, single node
/// in/out, mutable fields changed, minting_logic_script invoked via withdraw-0.
fn update_transaction() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [registry_node_input(old_registry_node())],
    outputs: [registry_node_output(new_registry_node())],
    withdrawals: [Pair(Script(test_minting_logic_hash), 0)],
  }
}

/// A covering-node spend during an insert, with a real (non-origin) key so the
/// R-01 guard is not vacuous.
fn insert_covering_spend_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [registry_node_input(covering_node())],
    mint: from_asset(registry_script_hash, "InsertedNode", 1),
  }
}

// =========================================================================
// RegistryInit tests
// =========================================================================

// Shared base transaction for the RegistryInit pair. Used by:
//   * registry_init_valid             — positive
//   * registry_init_fails_wrong_origin_address — Finding 03 negative, spread
//     with the `outputs` field overridden.
// Anything that would change for one of those two tests must be edited here
// so they stay in lockstep.
fn valid_init_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [utxo_ref_input()],
    outputs: [origin_node_output()],
    mint: from_asset(registry_script_hash, origin_node_tn, 1),
  }
}

// Happy path: consume utxo_ref, one origin node output, mint origin token
test registry_init_valid() {
  call_init_validator(valid_init_tx())
}

// The one-hash invariant, stated positively: Init locks the origin node at the
// address of the very policy that mints its NFT. The address here is built
// inline from `registry_script_hash` — the same value passed as the handler's
// `policy_id` argument — rather than via `test_node_address`, so the test reads
// as the invariant rather than as a fixture lookup. Positive companion to
// `registry_init_fails_wrong_origin_address`.
test registry_init_locks_origin_at_the_minting_policys_own_address() {
  let origin_at_own_address = Output {
    ..origin_node_output(),
    address: Address {
      payment_credential: Script(registry_script_hash),
      stake_credential: None,
    },
  }
  let tx = Transaction { ..valid_init_tx(), outputs: [origin_at_own_address] }
  call_init_validator(tx)
}

// utxo_ref not consumed in inputs
test registry_init_fails_utxo_not_consumed() fail {
  let other_input = Input {
    output_reference: OutputReference {
      transaction_id: #"ff",
      output_index: 99,
    },
    output: Output {
      address: test_input_address,
      value: min_ada,
      datum: NoDatum,
      reference_script: None,
    },
  }
  let tx = Transaction { ..valid_init_tx(), inputs: [other_input] }
  call_init_validator(tx)
}

// Origin node has non-empty key
test registry_init_fails_wrong_origin_key() fail {
  let bad_origin = Output {
    ..origin_node_output(),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: #"aa",
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
          minting_logic_script: empty_vkey,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
  }
  let tx = Transaction { ..valid_init_tx(), outputs: [bad_origin] }
  call_init_validator(tx)
}

// No origin token minted
test registry_init_fails_no_mint() fail {
  let tx = Transaction { ..valid_init_tx(), mint: assets.zero }
  call_init_validator(tx)
}

// Finding 03 regression: origin output sent to an address other than the
// registry script's own credential. Pre-fix this would have passed
// (validate_directory_init did not bind the address), allowing the origin
// registry NFT to live at an attacker-controlled address.
//
// Companion to registry_init_valid — the only delta visible at the test
// body is the `outputs` override (wrong-address origin).
test registry_init_fails_wrong_origin_address() fail {
  let wrong_address_origin = Output {
    ..origin_node_output(),
    address: test_input_address,
  }
  let tx = Transaction { ..valid_init_tx(), outputs: [wrong_address_origin] }
  call_init_validator(tx)
}

// =========================================================================
// RegistryInsert tests
// =========================================================================

fn valid_insert_redeemer() -> RegistryRedeemer {
  RegistryInsert {
    key: computed_key(),
    minting_logic_script: test_inserted_minting_logic_cred,
  }
}

fn valid_insert_tx() -> Transaction {
  let key = computed_key()
  Transaction {
    ..transaction.placeholder,
    inputs: [covering_node_input()],
    outputs: [updated_covering_node_output(), inserted_node_output()],
    reference_inputs: [issuance_ref_input()],
    // Must mint both the registry node token AND a programmable token under `key` as policy
    mint: from_asset(registry_script_hash, key, 1)
      |> assets.add(key, #"746f6b656e", 100),
    // The substandard's withdraw-0 logic MUST be invoked at registration
    // (always required by the mint handler).
    withdrawals: [Pair(test_inserted_minting_logic_cred, 0)],
  }
}

// Happy path: valid covering node, computed key, both outputs, issuance ref input
test registry_insert_valid() {
  call_insert_validator(valid_insert_redeemer(), valid_insert_tx())
}

// No reference input with issuance_cbor_hex_cs token
test registry_insert_fails_no_issuance_ref_input() fail {
  let tx = Transaction { ..valid_insert_tx(), reference_inputs: [] }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Key not covered: covering node key >= insert key
test registry_insert_fails_key_not_covered() fail {
  let key = computed_key()
  // Covering node with key > insert key, so insert key is NOT covered
  let bad_covering = Input {
    output_reference: OutputReference { transaction_id: #"01", output_index: 0 },
    output: Output {
      address: test_node_address,
      value: min_ada
        |> assets.add(registry_script_hash, key, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key,
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: Script(
              #"55555555555555555555555555555555555555555555555555555555",
            ),
            third_party_transfer_logic_script: Script(
              #"66666666666666666666666666666666666666666666666666666666",
            ),
            minting_logic_script: test_inserted_minting_logic_cred,
            unfracking_logic_script: empty_vkey,
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    },
  }
  let tx = Transaction { ..valid_insert_tx(), inputs: [bad_covering] }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Key not 28 bytes
test registry_insert_fails_wrong_key_length() fail {
  let short_key = #"aabb"
  let rdmr = RegistryInsert {
    key: short_key,
    minting_logic_script: test_inserted_minting_logic_cred,
  }
  call_insert_validator(rdmr, valid_insert_tx())
}

// Covering node's transfer_logic_script changed in output (NEW-1 fix)
test registry_insert_fails_updated_node_modified() fail {
  let key = computed_key()
  // Updated covering output with modified transfer_logic_script
  let tampered_output = Output {
    ..updated_covering_node_output(),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: #"",
          next: key,
          // Changed from empty_vkey to a different script!
          transfer_logic_script: Script(
            #"99999999999999999999999999999999999999999999999999999999",
          ),
          third_party_transfer_logic_script: empty_vkey,
          minting_logic_script: empty_vkey,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
  }
  let tx = Transaction {
    ..valid_insert_tx(),
    outputs: [tampered_output, inserted_node_output()],
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Empty mint: an insert MUST mint the registry node token for the new
// key. Fails `validate_mint(self.mint, policy_id) == key` (no entry
// under the registry policy at all).
test registry_insert_fails_node_token_not_minted() fail {
  let tx = Transaction { ..valid_insert_tx(), mint: assets.zero }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Only one node output instead of two
test registry_insert_fails_single_output() fail {
  let tx = Transaction {
    ..valid_insert_tx(),
    outputs: [updated_covering_node_output()],
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Finding 03 regression (Insert side): one of the new node outputs sits at
// a different address than the covering input. Pre-fix the address binding
// only kicked in at Init; the Insert path's inductive chain was undocumented
// and untested. Post-fix `validate_directory_node_output` asserts
// `output.address == covering_input.output.address`, so any drift fails.
test registry_insert_fails_wrong_output_address() fail {
  let wrong_inserted = Output {
    ..inserted_node_output(),
    address: test_input_address,
  }
  let tx = Transaction {
    ..valid_insert_tx(),
    outputs: [updated_covering_node_output(), wrong_inserted],
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// Register-only registration (no first mint)
//
// A registration need not mint any programmable tokens of `key` in the
// same tx — useful for RWA issuance, supply-aware substandards that need
// to initialise global state before any token exists, etc. The mint
// handler does not constrain the first-mint shape under `key` at all; a
// first mint, when present, is validated by `issuance_mint` as usual. Both
// mint shapes are valid under the single RegistryInsert constructor:
// with a first mint (`registry_insert_valid` above) and without
// (`registry_insert_register_only_valid` below).
//
// In BOTH shapes the substandard's `minting_logic_script` MUST appear in
// `tx.withdrawals` (proof of instance, always required).
//
// Coverage in this block:
//   1. Register-only happy path (mirror of the register-and-mint happy
//      path above).
//   2. Substandard-not-invoked failures (per mint shape).
//   3. Datum-vs-redeemer mismatch on the `minting_logic_script` field
//      (defense-in-depth #2).
//   4. Cryptographic binding failure (correct field shape, wrong content).
// =========================================================================

/// Register-only transaction — same shape as `valid_insert_tx` but the
/// mint value carries ONLY the registry NFT (no entries under `key`).
fn valid_register_only_tx() -> Transaction {
  let key = computed_key()
  Transaction {
    ..valid_insert_tx(),
    // Register-only: just the registry node NFT is minted; no programmable
    // tokens of `key`.
    mint: from_asset(registry_script_hash, key, 1),
  }
}

// Register-only happy path: substandard invoked via withdraw-0, no
// programmable tokens of `key` in mint. Locks in that the RegistryInsert
// redeemer covers the no-first-mint shape.
test registry_insert_register_only_valid() {
  call_insert_validator(valid_insert_redeemer(), valid_register_only_tx())
}

// Substandard withdraw-0 not invoked (register-only): the mint handler MUST
// reject even though all other invariants hold. Without this check the
// registrar could pin any substandard credential into a registry node the
// substandard itself never authorised. Critical in this shape: no tokens
// are minted, so `issuance_mint` never runs and cannot enforce it
// transitively.
test registry_insert_register_only_fails_substandard_not_invoked() fail {
  let tx = Transaction { ..valid_register_only_tx(), withdrawals: [] }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Substandard withdraw-0 not invoked (register-and-mint): same protection
// when a first mint is present. In a real first-mint tx `issuance_mint`
// would also require the substandard withdrawal (transitively, because
// tokens are minted), but the mint handler MUST enforce it directly so the
// protection doesn't depend on `issuance_mint` behaviour or on tokens
// actually being minted.
test registry_insert_fails_substandard_not_invoked() fail {
  let tx = Transaction { ..valid_insert_tx(), withdrawals: [] }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Defense-in-depth #2: the new node's datum `minting_logic_script` MUST
// equal the redeemer's `minting_logic_script`. A registrar that claims
// one credential in the redeemer but writes a different one into the
// datum is rejected.
test registry_insert_fails_datum_minting_logic_mismatch() fail {
  let key = computed_key()
  let wrong_cred = Script(
    #"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead",
  )
  let mismatched_inserted = Output {
    ..inserted_node_output(),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key,
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          minting_logic_script: wrong_cred,
          transfer_logic_script: Script(
            #"55555555555555555555555555555555555555555555555555555555",
          ),
          third_party_transfer_logic_script: Script(
            #"66666666666666666666666666666666666666666666666666666666",
          ),
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
  }
  let tx = Transaction {
    ..valid_insert_tx(),
    outputs: [updated_covering_node_output(), mismatched_inserted],
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Cryptographic binding: the redeemer's `minting_logic_script`'s inner
// hash MUST be the value `apply_hashed_parameter` produces the policy id
// from. Here we supply a credential whose hash ≠ `test_hashed_param`;
// `is_programmable_token_id_valid` rejects.
//
// Both the redeemer AND the datum carry the wrong credential — that
// keeps defense-in-depth #2 satisfied so this test isolates the binding
// failure (not the datum/redeemer mismatch).
test registry_insert_fails_wrong_minting_logic_for_key() fail {
  let wrong_cred = Script(
    #"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead",
  )
  let inserted_with_wrong_cred = Output {
    ..inserted_node_output(),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: computed_key(),
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          minting_logic_script: wrong_cred,
          transfer_logic_script: Script(
            #"55555555555555555555555555555555555555555555555555555555",
          ),
          third_party_transfer_logic_script: Script(
            #"66666666666666666666666666666666666666666666666666666666",
          ),
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
  }
  let rdmr = RegistryInsert {
    key: computed_key(),
    minting_logic_script: wrong_cred,
  }
  let tx = Transaction {
    ..valid_insert_tx(),
    outputs: [updated_covering_node_output(), inserted_with_wrong_cred],
    // wrong_cred must be invoked too, otherwise the test would fail
    // at the substandard-invocation check instead of the binding check.
    withdrawals: [Pair(wrong_cred, 0)],
  }
  call_insert_validator(rdmr, tx)
}

// Finding 07: the substandard-invocation check matches BY credential —
// having *some* other substandard withdraw in the same tx does not
// authorise this registration. Companion to
// `registry_insert_fails_substandard_not_invoked` (which uses
// `withdrawals: []`) — this test uses a non-empty withdrawals list
// containing the WRONG credential, isolating the "must match
// minting_logic_script" property.
test registry_insert_fails_wrong_substandard_in_withdrawals() fail {
  let other_cred = Script(
    #"abababababababababababababababababababababababababababab",
  )
  let tx = Transaction {
    ..valid_insert_tx(),
    withdrawals: [Pair(other_cred, 0)],
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Finding 07: the substandard-invocation check uses `list.any`
// semantics — the substandard's withdrawal must be PRESENT, not SOLE.
// Multiple reward addresses withdrawing in the same tx are fine;
// registration succeeds as long as `minting_logic_script` appears
// somewhere in `tx.withdrawals`. Locks in that the new check composes
// with unrelated stake activity in the same block.
test registry_insert_succeeds_substandard_among_other_withdrawals() {
  let other_cred = Script(
    #"abababababababababababababababababababababababababababab",
  )
  let other_vk_cred = VerificationKey(
    #"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
  )
  let tx = Transaction {
    ..valid_insert_tx(),
    withdrawals: [
      Pair(other_cred, 0), Pair(test_inserted_minting_logic_cred, 0),
      Pair(other_vk_cred, 1_000_000),
    ],
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Finding 07 + post-fix tightening: substandards MUST be `Script`
// credentials. A `VerificationKey`-credentialed redeemer is rejected
// by `is_programmable_token_id_valid` (lib/utils.ak) even when all
// structural invariants are otherwise satisfied — datum/redeemer
// equality holds (both carry the same VK), the credential appears in
// `tx.withdrawals`, the inner hash equals `test_hashed_param` so the
// hash-derivation would compute the correct policy id. The only
// failure point is the `expect Script(_)` in
// `is_programmable_token_id_valid`.
test registry_insert_fails_verification_key_substandard() fail {
  let vk_cred: Credential = VerificationKey(test_hashed_param)
  let inserted_with_vk = Output {
    ..inserted_node_output(),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: computed_key(),
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          minting_logic_script: vk_cred,
          transfer_logic_script: Script(
            #"55555555555555555555555555555555555555555555555555555555",
          ),
          third_party_transfer_logic_script: Script(
            #"66666666666666666666666666666666666666666666666666666666",
          ),
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
  }
  let rdmr = RegistryInsert {
    key: computed_key(),
    minting_logic_script: vk_cred,
  }
  let tx = Transaction {
    ..valid_insert_tx(),
    outputs: [updated_covering_node_output(), inserted_with_vk],
    withdrawals: [Pair(vk_cred, 0)],
  }
  call_insert_validator(rdmr, tx)
}

// =========================================================================
// CIP-68 multi-asset registration
//
// A registration may mint multiple asset names under the new policy in
// `tx.mint` to support CIP-68 (FT label 333 + ref token label 100). The
// mint handler does not constrain the first-mint shape under `key`
// (asset names and quantities are `issuance_mint`'s concern), so
// additional CIP-68 companion assets minted in the same tx do not affect
// the registration.
// =========================================================================

// Happy path: register with CIP-68 dual-token mint (FT + ref token)
test registry_insert_cip68_dual_token_mint() {
  let key = computed_key()
  let tx = Transaction {
    ..valid_insert_tx(),
    mint: from_asset(registry_script_hash, key, 1)
      |> assets.add(key, cip68_ft_name, 1_000_000)
      |> assets.add(key, cip68_ref_name, 1),
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// Mint-shape edge cases in the first mint
//
// The mint handler places NO constraint on the `tx.mint` entries under the
// new policy `key`. Sign and quantity are enforced elsewhere: burn-only
// of a brand-new policy is ledger-impossible (no prior tokens exist to
// burn), and any first mint is validated by `issuance_mint`.
// =========================================================================

// Mixed mint+burn under the new policy: registration succeeds regardless
// of entry signs under `key`. Kept as a sanity check that mixed-sign
// entries don't break the insert path.
test registry_insert_mixed_mint_and_burn() {
  let key = computed_key()
  let tx = Transaction {
    ..valid_insert_tx(),
    mint: from_asset(registry_script_hash, key, 1)
      |> assets.add(key, cip68_ft_name, 1_000_000)
      |> assets.add(key, #"6f6c64746f6b656e", -50),
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// Finding 19: redundant ordering checks have upstream coverage
//
// These two tests pin the upstream invariants that make the explicit
// `bytearray_lt(covering_node.key, key)?` and `bytearray_lt(key,
// covering_node.next)?` checks in the mint handler redundant. Each test
// builds a scenario where the only violation is the targeted ordering
// inequality, and confirms the validator rejects via
// `validate_directory_node_output`'s `bytearray_lt(node.key, node.next)`
// check on the relevant output.
//
// If we ever drop the upstream `node.key < node.next` check in
// `validate_directory_node_output`, these tests will start passing
// (failing their `fail` assertion) — that's the alarm.
// =========================================================================

// Finding 19: covering_node.key MUST be strictly less than the insert key.
// The redundant check `bytearray_lt(covering_node.key, key)?` in the mint
// handler is implied by validate_directory_node_output on the
// updated covering output: updated.key == covering_node.key and
// updated.next == insert_key (per is_updated_directory_node), so the
// per-output `bytearray_lt(node.key, node.next)` check transitively
// asserts `covering_node.key < insert_key`.
//
// Uses bad_covering.key = 28 bytes of 0xff (the max 28-byte value,
// strictly greater than any blake2b_224 output). The updated covering
// output therefore has key = 0xff..ff (28B) and next = computed_key
// (28B hash output, < 0xff..ff). `validate_directory_node_output`
// rejects the updated output via bytearray_lt(0xff..ff, computed_key)
// = False.
test registry_insert_fails_covering_key_ge_insert_key() fail {
  let bad_covering_key = #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  let bad_covering = Input {
    output_reference: OutputReference { transaction_id: #"01", output_index: 0 },
    output: Output {
      address: test_node_address,
      value: min_ada
        |> assets.add(registry_script_hash, bad_covering_key, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: bad_covering_key,
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: empty_vkey,
            third_party_transfer_logic_script: empty_vkey,
            minting_logic_script: empty_vkey,
            unfracking_logic_script: empty_vkey,
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    },
  }
  let bad_updated = Output {
    address: test_node_address,
    value: min_ada
      |> assets.add(registry_script_hash, bad_covering_key, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: bad_covering_key,
          next: computed_key(),
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
          minting_logic_script: empty_vkey,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
  let tx = Transaction {
    ..valid_insert_tx(),
    inputs: [bad_covering],
    outputs: [bad_updated, inserted_node_output()],
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Finding 19: insert key MUST be strictly less than covering_node.next.
// The redundant check `bytearray_lt(key, covering_node.next)?` in the mint
// handler is implied by validate_directory_node_output on the
// inserted output: inserted.key == insert_key and inserted.next ==
// covering_node.next (per is_inserted_directory_node), so the per-output
// `bytearray_lt(node.key, node.next)` check transitively asserts
// `insert_key < covering_node.next`.
//
// Uses bad_covering.next = 28 bytes of 0x00 (the minimum 28-byte value,
// strictly less than any blake2b_224 output for the computed key, which
// starts with a non-zero byte). The inserted output therefore has
// key = computed_key (28B hash) and next = 0x00..00 (28B), and
// `validate_directory_node_output` rejects via
// bytearray_lt(computed_key, 0x00..00) = False.
test registry_insert_fails_insert_key_ge_covering_next() fail {
  let bad_covering_next = #"0000000000000000000000000000000000000000000000000000000000"
  let key = computed_key()
  let covering = covering_node_input()
  let bad_covering = Input {
    ..covering,
    output: Output {
      ..covering.output,
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: #"",
            next: bad_covering_next,
            transfer_logic_script: empty_vkey,
            third_party_transfer_logic_script: empty_vkey,
            minting_logic_script: empty_vkey,
            unfracking_logic_script: empty_vkey,
            global_state_cs: #"",
          },
        ),
      ),
    },
  }
  let bad_inserted = Output {
    ..inserted_node_output(),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key,
          next: bad_covering_next,
          transfer_logic_script: Script(
            #"55555555555555555555555555555555555555555555555555555555",
          ),
          third_party_transfer_logic_script: Script(
            #"66666666666666666666666666666666666666666666666666666666",
          ),
          minting_logic_script: test_inserted_minting_logic_cred,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
  }
  let tx = Transaction {
    ..valid_insert_tx(),
    inputs: [bad_covering],
    outputs: [updated_covering_node_output(), bad_inserted],
  }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// Spend: covering-node spend of an insert (Some branch)
// =========================================================================

// Happy path: a registry node NFT is minted under the registry script's own
// hash, so the spend is the covering-node leg of an insert; the mint handler
// validates the linked-list structure.
test registry_spend_valid() {
  call_spend(Some(origin_node), spend_own_ref(), spend_transaction())
}

// The spend handler only checks that *some* token is minted under the node
// policy with amount > 0; it does not prescribe the token name.
test registry_spend_valid_any_token_name() {
  let tx = Transaction {
    ..spend_transaction(),
    mint: from_asset(registry_script_hash, "AnyNodeName", 1),
  }
  call_spend(Some(origin_node), spend_own_ref(), tx)
}

// ---------------------------------------------------------------------------
// The derivation pair.
//
// The registry node NFT policy the spend handler tests `tx.mint` against comes
// from `own_input.output.address.payment_credential` and from nowhere else.
// A SINGLE positive cannot state that: every other fixture in this module uses
// one policy value, so "derived from the own input's address" and "any
// constant" are indistinguishable — replace the derivation with a hardcoded
// `registry_script_hash` and a lone positive stays green.
//
// So the statement is a PAIR, built on a node that lives at a SECOND script
// hash used nowhere else in this module. The positive mints the node NFT under
// that second hash and passes; the negative is the same transaction with one
// delta — the mint moves to the ordinary `registry_script_hash` — and is
// rejected. Together they pin the policy to the address: only a mint under the
// hash in the spent UTxO's own payment credential is recognised.
//
// Both flip under the hardcoded-constant mutation. That is the proof the pair
// exists to provide, and the justification for the six tests designed out at
// the top of this file.
// ---------------------------------------------------------------------------

/// A second registry script hash, deliberately used ONLY by the derivation
/// pair. If it ever appears elsewhere, the pair stops discriminating.
const alt_registry_script_hash: PolicyId =
  #"7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c"

/// The same node, at the alternative script's address, carrying its NFT under
/// the alternative policy.
fn alt_node_input() -> Input {
  Input {
    output_reference: spend_own_ref(),
    output: Output {
      address: Address {
        payment_credential: Script(alt_registry_script_hash),
        stake_credential: None,
      },
      value: min_ada
        |> assets.add(alt_registry_script_hash, origin_node.key, 1),
      datum: InlineDatum(as_data(origin_node)),
      reference_script: None,
    },
  }
}

/// Base transaction for the pair. The decoy reference input carries neither the
/// node policy nor a protocol-params NFT: pre-merge the handler scanned
/// `reference_inputs` for the params UTxO and read `registry_node_cs` out of
/// its datum, so this shape would have aborted. It is present in BOTH tests so
/// the only delta between them is the mint policy.
fn alt_address_spend_tx() -> Transaction {
  let decoy_cs: PolicyId = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  let decoy_ref_input = Input {
    output_reference: OutputReference {
      transaction_id: #"2222222222222222222222222222222222222222222222222222222222222222",
      output_index: 0,
    },
    output: Output {
      address: test_input_address,
      value: min_ada |> assets.add(decoy_cs, "Unrelated", 1),
      datum: NoDatum,
      reference_script: None,
    },
  }
  Transaction {
    ..transaction.placeholder,
    inputs: [alt_node_input()],
    reference_inputs: [decoy_ref_input],
    mint: from_asset(alt_registry_script_hash, "OriginNode", 1),
  }
}

// Positive: the node sits at `alt_registry_script_hash` and its NFT is minted
// under that same hash. The handler recognises the mint, so it must have taken
// the policy from the spent UTxO's payment credential — no other fixture value
// in this transaction equals it.
test registry_spend_derives_node_policy_from_its_own_address() {
  call_spend(Some(origin_node), spend_own_ref(), alt_address_spend_tx())
}

// Negative, single delta: the mint moves to `registry_script_hash`, which is
// every OTHER node's policy in this module but is NOT this node's address
// credential. The handler does not recognise it as a node mint, falls to the
// update branch, and with no continuing output the spend is rejected. A
// hardcoded policy would accept this transaction.
test registry_spend_fails_node_mint_under_a_policy_that_is_not_its_address() fail {
  let tx = Transaction {
    ..alt_address_spend_tx(),
    mint: from_asset(registry_script_hash, "OriginNode", 1),
  }
  call_spend(Some(origin_node), spend_own_ref(), tx)
}

// Companion negative to the derivation test above: the minted token is under
// SOME OTHER policy, not the script's own hash. The handler does not recognise
// it as a node mint, so the spend is judged as an in-place update — and with no
// continuing node output there is nothing to update, so it is rejected. A node
// can never be spent into a transaction that neither extends the list nor
// preserves the node.
test fails_no_registry_node_minted() fail {
  let other_cs: PolicyId = #"99999999999999999999999999999999999999999999999999999999"
  let tx = Transaction {
    ..spend_transaction(),
    mint: from_asset(other_cs, "SomethingElse", 1),
  }
  call_spend(Some(origin_node), spend_own_ref(), tx)
}

// Registry nodes are permanent: the Some branch requires amount > 0, so a burn
// of the node NFT is rejected.
test fails_registry_node_burned() fail {
  let tx = Transaction {
    ..spend_transaction(),
    mint: from_asset(registry_script_hash, "OriginNode", -1),
  }
  call_spend(Some(origin_node), spend_own_ref(), tx)
}

// One registry operation per transaction: `expect [Pair(_, amount)]` rejects
// two asset names minted under the node policy.
test fails_multiple_token_names_under_registry_cs() fail {
  let tx = Transaction {
    ..spend_transaction(),
    mint: from_asset(registry_script_hash, "NodeA", 1)
      |> assets.add(registry_script_hash, "NodeB", 1),
  }
  call_spend(Some(origin_node), spend_own_ref(), tx)
}

// Nothing minted at all → the update (None) branch, which needs a continuing
// node output. There is none, so the spend is rejected.
test fails_empty_mint() fail {
  let tx = Transaction { ..spend_transaction(), mint: assets.zero }
  call_spend(Some(origin_node), spend_own_ref(), tx)
}

// ===========================================================================
// Spend: in-place node update (None branch — no node NFT minted)
//
// The creator updates the 3 mutable fields (transfer_logic_script,
// third_party_transfer_logic_script, global_state_cs) of an existing node,
// keeping key / next / minting_logic_script frozen. Authorisation is the
// node's own minting_logic_script invoked via withdraw-0.
// ===========================================================================

// Happy path: creator updates the 3 mutable fields with proper authorisation.
test registry_spend_update_node() {
  call_spend(Some(old_registry_node()), spend_own_ref(), update_transaction())
}

// Reject: minting_logic_script is NOT invoked (no withdrawal) → unauthorised.
// pairs.has_key returns False → validator returns False.
test fails_update_without_minting_logic_withdrawal() fail {
  let tx = Transaction { ..update_transaction(), withdrawals: [] }
  call_spend(Some(old_registry_node()), spend_own_ref(), tx)
}

// Reject: a different credential is invoked, not the node's minting_logic_script.
test fails_update_wrong_withdrawal_credential() fail {
  let tx = Transaction {
    ..update_transaction(),
    withdrawals: [Pair(Script(test_other_minting_hash), 0)],
  }
  call_spend(Some(old_registry_node()), spend_own_ref(), tx)
}

// Reject: tampering with an immutable field (minting_logic_script). key/next are
// untouched so validate_directory_node_output passes, but the record-equality in
// is_field_updated_registry_node fails.
test fails_update_changes_minting_logic() fail {
  let tampered = RegistryNode {
    ..new_registry_node(),
    minting_logic_script: Script(test_other_minting_hash),
  }
  let tx = Transaction {
    ..update_transaction(),
    outputs: [registry_node_output(tampered)],
  }
  call_spend(Some(old_registry_node()), spend_own_ref(), tx)
}

// Reject: relocating the node NFT to a different address (theft). The continuing
// output's address must equal the spent input's address.
test fails_update_relocates_nft() fail {
  let relocated = Output {
    ..registry_node_output(new_registry_node()),
    address: Address {
      payment_credential: VerificationKey(test_attacker_addr_hash),
      stake_credential: None,
    },
  }
  let tx = Transaction { ..update_transaction(), outputs: [relocated] }
  call_spend(Some(old_registry_node()), spend_own_ref(), tx)
}

// Reject: two continuing node outputs (batching / double-satisfaction). The
// single-output filter `expect [cont]` rejects more than one.
test fails_update_two_node_outputs() fail {
  let tx = Transaction {
    ..update_transaction(),
    outputs: [
      registry_node_output(new_registry_node()),
      registry_node_output(new_registry_node()),
    ],
  }
  call_spend(Some(old_registry_node()), spend_own_ref(), tx)
}

// The origin node is PERMANENTLY IMMUTABLE, and this test is the only thing
// that says so.
//
// `origin_node.minting_logic_script` is `empty_vkey` — a VerificationKey. The
// update branch's authorisation is `when spent_node.minting_logic_script is {
// Script(_) -> pairs.has_key(withdrawals, ..); VerificationKey(_) -> False }`,
// so that `VerificationKey(_) -> False` arm is the ORIGIN NODE'S ONLY LOCK:
// there is no credential any transaction could invoke to authorise an origin
// update, because a vkey credential can never appear in `tx.withdrawals` as
// the node's minting logic. Flip that arm to `True` and a transaction that
// spends the origin node, rewrites `transfer_logic_script`,
// `third_party_transfer_logic_script` and `global_state_cs` to attacker values
// and carries NO withdrawals at all is accepted — the origin node becomes
// freely rewritable by anyone who can build the transaction.
//
// Before this test that mutation changed no test's state. Not an audit finding
// and not introduced by the registry merge — a pre-existing coverage hole, so
// no `Finding NN:` prefix.
//
// The fixture is a legitimate update in every other respect (key, next and
// minting_logic_script frozen; address, NFT and value preserved), so
// `is_field_updated_registry_node` passes and the ONLY thing left to reject it
// is the vkey arm. Positive companion: `registry_spend_update_node`, which
// shows a Script-credentialed node updating normally.
test registry_spend_fails_origin_node_update() fail {
  let attacker_rewrite = RegistryNode {
    ..origin_node,
    transfer_logic_script: Script(test_transfer_new),
    third_party_transfer_logic_script: Script(test_third_party_new),
    global_state_cs: test_global_new,
  }
  let origin_input = registry_node_input(origin_node)
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [origin_input],
    outputs: [
      Output {
        ..origin_input.output,
        datum: InlineDatum(as_data(attacker_rewrite)),
      },
    ],
    withdrawals: [],
  }
  call_spend(Some(origin_node), spend_own_ref(), tx)
}

// Reject: malformed mutable value — a non-28-byte transfer_logic_script.
test fails_update_malformed_transfer_logic() fail {
  let bad = RegistryNode {
    ..new_registry_node(),
    transfer_logic_script: Script(#"1234"),
  }
  let tx = Transaction {
    ..update_transaction(),
    outputs: [registry_node_output(bad)],
  }
  call_spend(Some(old_registry_node()), spend_own_ref(), tx)
}

// ========================================================================
// R-01: a registry-node spend must not double as an issuance of that node's
// own programmable token (`key`). This closes the OutputIndex custody escape:
// a node spent + re-emitted (update, or insert-covering) is an OUTPUT that
// `issuance_mint`'s OutputIndex path accepts as proof-of-node; minting `key`
// in that same tx would let fresh supply escape PLB custody. The spend
// handler is the sole spender of every node, so this one guard — hoisted
// above the `when` — covers BOTH paths: the UPDATE (None) branch and the
// covering-node spend of an INSERT (Some).
// ========================================================================

// UPDATE path (None branch): update the node AND mint its own key → rejected.
// Single delta from the happy-path `update_transaction()`: a mint under
// `test_node_key`.
test fails_update_mints_own_programmable_token() fail {
  let tx = Transaction {
    ..update_transaction(),
    mint: from_asset(test_node_key, #"746f6b656e", 100),
  }
  call_spend(Some(old_registry_node()), spend_own_ref(), tx)
}

// UPDATE positive companion: the guard is scoped to the node's OWN `key`, not
// a blanket no-mint rule. An update MAY coexist with minting an UNRELATED
// policy (e.g. batching), so this must still pass.
test update_node_with_unrelated_mint_ok() {
  let unrelated_policy = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let tx = Transaction {
    ..update_transaction(),
    mint: from_asset(unrelated_policy, #"746f6b656e", 100),
  }
  call_spend(Some(old_registry_node()), spend_own_ref(), tx)
}

// INSERT path (Some branch): the covering node is spent while its own key is
// minted → rejected by the SAME guard, with no change to the mint handler.
// Single delta from `insert_covering_spend_tx()`: a mint under the covering key.
test fails_insert_covering_node_token_minted() fail {
  let tx = Transaction {
    ..insert_covering_spend_tx(),
    mint: from_asset(registry_script_hash, "InsertedNode", 1)
      |> assets.add(test_covering_key, #"746f6b656e", 100),
  }
  call_spend(Some(covering_node()), spend_own_ref(), tx)
}

// INSERT positive companion: a covering-node spend during an insert with NO
// mint of the covering's own key passes (guard scoped to `key`; the new node's
// key is legitimately minted elsewhere in a real insert).
test insert_covering_spend_valid() {
  call_spend(Some(covering_node()), spend_own_ref(), insert_covering_spend_tx())
}

// =========================================================================
// CIP-68 subsequent mint (RefInput registry proof) in issuance_mint
//
// Exercises issuance_mint with CIP-68 dual-token mint + RefInput proof,
// covering the path where the registry already exists from a prior insert.
// Not a registry test — it lives here because it always has; moved across
// unchanged from registry_mint.test.ak.
// =========================================================================

// issuance_mint validator params
const ism_plb_cred: Credential =
  Script(#"aa11111111111111111111111111111111111111111111111111111111")

const ism_registry_cs: PolicyId =
  #"aa22222222222222222222222222222222222222222222222222222222"

const ism_ml_cred: Credential =
  Script(#"aa33333333333333333333333333333333333333333333333333333333")

const ism_params_policy: PolicyId =
  #"aa5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e"

const ism_own_policy: PolicyId =
  #"aa44444444444444444444444444444444444444444444444444444444"

fn ism_registry_node_output() -> Output {
  Output {
    address: Address {
      payment_credential: Script(
        #"aa88888888888888888888888888888888888888888888888888888888",
      ),
      stake_credential: None,
    },
    value: min_ada
      |> assets.add(ism_registry_cs, ism_own_policy, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: ism_own_policy,
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: Script(
            #"aa66666666666666666666666666666666666666666666666666666666",
          ),
          third_party_transfer_logic_script: Script(
            #"aa77777777777777777777777777777777777777777777777777777777",
          ),
          // Must match the `ism_ml_cred` parameter passed to call_issuance_validator
          // (defense-in-depth #3: issuance_mint asserts this equals its
          // `minting_logic_cred` parameter).
          minting_logic_script: ism_ml_cred,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

fn ism_ref_input() -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
      output_index: 0,
    },
    output: ism_registry_node_output(),
  }
}

fn ism_plb_output(value: assets.Value) -> Output {
  Output {
    address: Address {
      payment_credential: ism_plb_cred,
      stake_credential: Some(
        Inline(
          Script(#"aa99999999999999999999999999999999999999999999999999999999"),
        ),
      ),
    },
    value,
    datum: InlineDatum(Void),
    reference_script: None,
  }
}

fn call_issuance_validator(rdmr: MintingRegistryProof, tx: Transaction) -> Bool {
  issuance_mint.issuance_mint.mint(
    ism_plb_cred,
    ism_registry_cs,
    ism_ml_cred,
    ism_params_policy,
    rdmr,
    ism_own_policy,
    tx,
  )
}

// CIP-68 subsequent mint with RefInput: FT + ref token, registry already exists
test cip68_subsequent_mint_ref_input() {
  let rdmr = RefInput(0)
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [ism_ref_input()],
    outputs: [
      ism_plb_output(min_ada |> assets.add(ism_own_policy, cip68_ft_name, 500)),
      ism_plb_output(min_ada |> assets.add(ism_own_policy, cip68_ref_name, 1)),
    ],
    mint: from_asset(ism_own_policy, cip68_ft_name, 500)
      |> assets.add(ism_own_policy, cip68_ref_name, 1),
    withdrawals: [Pair(ism_ml_cred, 0)],
    redeemers: [Pair(Mint(ism_own_policy), as_data(rdmr))],
  }
  call_issuance_validator(rdmr, tx)
}
