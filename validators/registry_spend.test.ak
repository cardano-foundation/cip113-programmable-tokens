//// Comprehensive tests for the registry_spend validator.
////
//// Tests invoke the validator's spend handler directly, covering:
//// - Happy path with valid protocol params ref input and registry node minting
//// - Missing or invalid protocol params reference input
//// - Datum validation (missing, wrong type)
//// - Registry node minting checks (none, burning, multiple token names)

use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use registry_node.{RegistryNode}
use registry_spend

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_protocol_params_cs: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const test_registry_node_cs: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const test_prog_logic_hash: ByteArray =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn valid_params_datum() -> Data {
  as_data(
    ProgrammableLogicGlobalParams {
      registry_node_cs: test_registry_node_cs,
      prog_logic_cred: Script(test_prog_logic_hash),
      unfracking_cred: Script(
        #"00000000000000000000000000000000000000000000000000def17a",
      ),
    },
  )
}

/// Build a reference input that carries the protocol params NFT + inline datum
fn protocol_params_ref_input() -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
      output_index: 0,
    },
    output: Output {
      address: Address {
        payment_credential: Script(
          #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        ),
        stake_credential: None,
      },
      value: min_ada
        |> assets.add(test_protocol_params_cs, "ProtocolParams", 1),
      datum: InlineDatum(valid_params_datum()),
      reference_script: None,
    },
  }
}

/// A reference input that does NOT carry the protocol params token
fn unrelated_ref_input() -> Input {
  let other_cs: PolicyId = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  Input {
    output_reference: OutputReference {
      transaction_id: #"2222222222222222222222222222222222222222222222222222222222222222",
      output_index: 0,
    },
    output: Output {
      address: Address {
        payment_credential: VerificationKey(
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ),
        stake_credential: None,
      },
      value: min_ada
        |> assets.add(other_cs, "Unrelated", 1),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn valid_transaction() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [protocol_params_ref_input()],
    mint: from_asset(test_registry_node_cs, "OriginNode", 1),
  }
}

fn call_validator(tx: Transaction) -> Bool {
  registry_spend.registry_spend.spend(
    test_protocol_params_cs,
    None,
    as_data(Void),
    placeholder_own_ref(),
    tx,
  )
}

/// A throwaway OutputReference for tests that hit the minting (Some) branch,
/// which never resolves own_ref. Update-path tests should pass an own_ref that
/// matches the spent node input instead.
fn placeholder_own_ref() -> OutputReference {
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
    output_index: 0,
  }
}

// ========================================================================
// Happy path — protocol params ref input present, registry node minted
// ========================================================================

test registry_spend_valid() {
  call_validator(valid_transaction())
}

// ========================================================================
// Happy path — passes with a different registry node token name
//
// The validator only checks that *some* token is minted under
// registry_node_cs with amount > 0; it does not prescribe the token name.
// ========================================================================

test registry_spend_valid_any_token_name() {
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [protocol_params_ref_input()],
    mint: from_asset(test_registry_node_cs, "AnyNodeName", 1),
  }
  call_validator(tx)
}

// ========================================================================
// Happy path — protocol params ref input among multiple ref inputs
//
// Ensures list.find correctly locates the protocol params even when
// other unrelated reference inputs are present.
// ========================================================================

test registry_spend_valid_multiple_ref_inputs() {
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [unrelated_ref_input(), protocol_params_ref_input()],
    mint: from_asset(test_registry_node_cs, "OriginNode", 1),
  }
  call_validator(tx)
}

// ========================================================================
// No protocol params reference input at all
//
// list.find returns None → expect Some crashes.
// ========================================================================

test fails_no_protocol_params_ref_input() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [],
    mint: from_asset(test_registry_node_cs, "OriginNode", 1),
  }
  call_validator(tx)
}

// ========================================================================
// Protocol params ref input present but has wrong currency symbol
//
// The ref input carries a different policy ID, so has_currency_symbol
// returns False for protocol_params_cs and list.find returns None.
// ========================================================================

test fails_wrong_protocol_params_cs_in_ref_input() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [unrelated_ref_input()],
    mint: from_asset(test_registry_node_cs, "OriginNode", 1),
  }
  call_validator(tx)
}

// ========================================================================
// Protocol params ref input has NoDatum
//
// expect_inline_datum crashes when datum is NoDatum.
// ========================================================================

test fails_no_inline_datum_on_params() fail {
  let bad_ref_input = Input {
    ..protocol_params_ref_input(),
    output: Output { ..protocol_params_ref_input().output, datum: NoDatum },
  }
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [bad_ref_input],
    mint: from_asset(test_registry_node_cs, "OriginNode", 1),
  }
  call_validator(tx)
}

// ========================================================================
// Protocol params datum is wrong type
//
// expect params: ProgrammableLogicGlobalParams crashes when the datum
// is an integer instead of the expected constructor.
// ========================================================================

test fails_invalid_datum_type() fail {
  let bad_ref_input = Input {
    ..protocol_params_ref_input(),
    output: Output {
      ..protocol_params_ref_input().output,
      datum: InlineDatum(as_data(42)),
    },
  }
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [bad_ref_input],
    mint: from_asset(test_registry_node_cs, "OriginNode", 1),
  }
  call_validator(tx)
}

// ========================================================================
// No tokens minted under registry_node_cs
//
// dict.get(registry_node_cs) returns None → expect Some crashes.
// This tests the core check: spending registry nodes is only allowed
// when the registry structure is being modified (minting nodes).
// ========================================================================

test fails_no_registry_node_minted() fail {
  let other_cs: PolicyId = #"9999999999999999999999999999999999999999999999999999999999"
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [protocol_params_ref_input()],
    mint: from_asset(other_cs, "SomethingElse", 1),
  }
  call_validator(tx)
}

// ========================================================================
// Registry node burned (negative amount)
//
// The validator requires amount > 0, which blocks burning.
// This is an intentional design choice: registry nodes are permanent.
// With the old `!= 0` check, burning would have been allowed.
// ========================================================================

test fails_registry_node_burned() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [protocol_params_ref_input()],
    mint: from_asset(test_registry_node_cs, "OriginNode", -1),
  }
  call_validator(tx)
}

// ========================================================================
// Multiple token names minted under registry_node_cs
//
// expect [Pair(_, amount)] = dict.to_pairs(minted_assets) crashes
// because the list has 2 elements instead of 1.
// This enforces one registry operation per transaction per the
// spending validator's perspective.
// ========================================================================

test fails_multiple_token_names_under_registry_cs() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [protocol_params_ref_input()],
    mint: from_asset(test_registry_node_cs, "NodeA", 1)
      |> assets.add(test_registry_node_cs, "NodeB", 1),
  }
  call_validator(tx)
}

// ========================================================================
// Empty mint field — no minting at all
//
// dict.get(registry_node_cs) on empty mint returns None → crashes.
// ========================================================================

test fails_empty_mint() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [protocol_params_ref_input()],
    mint: assets.zero,
  }
  call_validator(tx)
}

// ===========================================================================
// In-place node update path (None branch: no registry_node_cs minted)
//
// The creator updates the 3 mutable fields (transfer_logic_script,
// third_party_transfer_logic_script, global_state_cs) of an existing node,
// keeping key / next / minting_logic_script frozen. Authorisation is the
// node's own minting_logic_script invoked via withdraw-0.
// ===========================================================================

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

const test_node_addr_hash: ByteArray =
  #"88888888888888888888888888888888888888888888888888888888"

const test_attacker_addr_hash: ByteArray =
  #"99999999999999999999999999999999999999999999999999999999"

const test_other_minting_hash: ByteArray =
  #"abababababababababababababababababababababababababababab"

/// The registry-node address (payment = registry_spend script, stake = None).
fn test_node_address() -> Address {
  Address {
    payment_credential: Script(test_node_addr_hash),
    stake_credential: None,
  }
}

/// The node before the update.
fn old_registry_node() -> RegistryNode {
  RegistryNode {
    key: test_node_key,
    next: test_node_next,
    minting_logic_script: Script(test_minting_logic_hash),
    transfer_logic_script: Script(test_transfer_old),
    third_party_transfer_logic_script: Script(test_third_party_old),
    global_state_cs: #"",
  }
}

/// The node after the update — only the 3 mutable fields change.
fn new_registry_node() -> RegistryNode {
  RegistryNode {
    ..old_registry_node(),
    transfer_logic_script: Script(test_transfer_new),
    third_party_transfer_logic_script: Script(test_third_party_new),
    global_state_cs: test_global_new,
  }
}

/// OutputReference of the registry node being spent. Shared so the value the
/// validator receives as `own_ref` matches the input `find_input` must locate.
fn test_node_own_ref() -> OutputReference {
  OutputReference {
    transaction_id: #"3333333333333333333333333333333333333333333333333333333333333333",
    output_index: 0,
  }
}

/// A registry-node UTxO carrying the node NFT (token name == key) + inline datum.
fn registry_node_input(node: RegistryNode) -> Input {
  Input {
    output_reference: test_node_own_ref(),
    output: Output {
      address: test_node_address(),
      value: min_ada |> assets.add(test_registry_node_cs, test_node_key, 1),
      datum: InlineDatum(as_data(node)),
      reference_script: None,
    },
  }
}

fn registry_node_output(node: RegistryNode) -> Output {
  Output {
    address: test_node_address(),
    value: min_ada |> assets.add(test_registry_node_cs, test_node_key, 1),
    datum: InlineDatum(as_data(node)),
    reference_script: None,
  }
}

/// A valid in-place update tx: no registry mint, single node in/out, mutable
/// fields changed, minting_logic_script invoked via withdraw-0.
fn update_transaction() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [protocol_params_ref_input()],
    inputs: [registry_node_input(old_registry_node())],
    outputs: [registry_node_output(new_registry_node())],
    withdrawals: [Pair(Script(test_minting_logic_hash), 0)],
  }
}

// Happy path: creator updates the 3 mutable fields with proper authorisation.
test registry_spend_update_node() {
  registry_spend.registry_spend.spend(
    test_protocol_params_cs,
    Some(old_registry_node()),
    as_data(Void),
    test_node_own_ref(),
    update_transaction(),
  )
}

// Reject: minting_logic_script is NOT invoked (no withdrawal) → unauthorised.
// pairs.has_key returns False → validator returns False.
test fails_update_without_minting_logic_withdrawal() fail {
  let tx = Transaction { ..update_transaction(), withdrawals: [] }
  call_validator(tx)
}

// Reject: a different credential is invoked, not the node's minting_logic_script.
test fails_update_wrong_withdrawal_credential() fail {
  let tx = Transaction {
    ..update_transaction(),
    withdrawals: [Pair(Script(test_other_minting_hash), 0)],
  }
  call_validator(tx)
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
  call_validator(tx)
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
  call_validator(tx)
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
  call_validator(tx)
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
  call_validator(tx)
}
