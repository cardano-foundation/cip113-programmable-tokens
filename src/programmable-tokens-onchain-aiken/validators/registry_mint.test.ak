//// Tests for the registry_mint validator.
//// Invokes the validator's mint handler directly, covering both
//// RegistryInit and RegistryInsert redeemer paths.

use cardano/address.{Address, Script}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use registry_mint
use registry_node.{RegistryNode, empty_vkey, origin_node_tn}
use types.{IssuanceCborHex, RegistryInit, RegistryInsert, RegistryRedeemer}
use utils.{apply_hashed_parameter}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_utxo_ref = OutputReference { transaction_id: #"00", output_index: 0 }

/// A fake issuance_cbor_hex currency symbol (28 bytes)
const test_issuance_cbor_hex_cs: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

/// The registry policy id (what registry_mint mints under)
const test_policy_id: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

/// Address for node outputs (simulates the registry script address)
const test_node_address =
  Address { payment_credential: Script(#"cccccccc"), stake_credential: None }

/// Address for a generic input
const test_input_address =
  Address { payment_credential: Script(#"dddddddd"), stake_credential: None }

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

/// Prefix / postfix for issuance script reconstruction
const test_prefix = #"0102"

const test_postfix = #"0304"

/// A valid hashed_param (arbitrary 28 bytes)
const test_hashed_param =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build the 28-byte key that `is_programmable_token_registration` expects.
fn computed_key() -> ByteArray {
  apply_hashed_parameter(test_prefix, test_postfix, test_hashed_param)
}

/// Origin node output: key=#"", next=0xff…ff, empty credentials
fn origin_node_output() -> Output {
  Output {
    address: test_node_address,
    value: min_ada
      |> assets.add(test_policy_id, origin_node_tn, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: #"",
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
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
        |> assets.add(test_policy_id, origin_node_tn, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: #"",
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: empty_vkey,
            third_party_transfer_logic_script: empty_vkey,
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
      |> assets.add(test_policy_id, origin_node_tn, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: #"",
          next: key,
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
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
      |> assets.add(test_policy_id, key, 1),
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
  registry_mint.registry_mint.mint(
    test_utxo_ref,
    test_issuance_cbor_hex_cs,
    RegistryInit,
    test_policy_id,
    tx,
  )
}

fn call_insert_validator(redeemer: RegistryRedeemer, tx: Transaction) -> Bool {
  registry_mint.registry_mint.mint(
    test_utxo_ref,
    test_issuance_cbor_hex_cs,
    redeemer,
    test_policy_id,
    tx,
  )
}

// =========================================================================
// RegistryInit tests
// =========================================================================

// Happy path: consume utxo_ref, one origin node output, mint origin token
test registry_init_valid() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [utxo_ref_input()],
      outputs: [origin_node_output()],
      mint: from_asset(test_policy_id, origin_node_tn, 1),
    }
  call_init_validator(tx)
}

// utxo_ref not consumed in inputs
test registry_init_fails_utxo_not_consumed() fail {
  let other_input =
    Input {
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
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [other_input],
      outputs: [origin_node_output()],
      mint: from_asset(test_policy_id, origin_node_tn, 1),
    }
  call_init_validator(tx)
}

// Origin node has non-empty key
test registry_init_fails_wrong_origin_key() fail {
  let bad_origin =
    Output {
      address: test_node_address,
      value: min_ada
        |> assets.add(test_policy_id, origin_node_tn, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: #"aa",
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: empty_vkey,
            third_party_transfer_logic_script: empty_vkey,
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [utxo_ref_input()],
      outputs: [bad_origin],
      mint: from_asset(test_policy_id, origin_node_tn, 1),
    }
  call_init_validator(tx)
}

// No origin token minted
test registry_init_fails_no_mint() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [utxo_ref_input()],
      outputs: [origin_node_output()],
      mint: assets.zero,
    }
  call_init_validator(tx)
}

// =========================================================================
// RegistryInsert tests
// =========================================================================

fn valid_insert_redeemer() -> RegistryRedeemer {
  RegistryInsert { key: computed_key(), hashed_param: test_hashed_param }
}

fn valid_insert_tx() -> Transaction {
  let key = computed_key()
  Transaction {
    ..transaction.placeholder,
    inputs: [covering_node_input()],
    outputs: [updated_covering_node_output(), inserted_node_output()],
    reference_inputs: [issuance_ref_input()],
    // Must mint both the registry node token AND a programmable token under `key` as policy
    mint: from_asset(test_policy_id, key, 1)
      |> assets.add(key, #"746f6b656e", 100),
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
  let bad_covering =
    Input {
      output_reference: OutputReference {
        transaction_id: #"01",
        output_index: 0,
      },
      output: Output {
        address: test_node_address,
        value: min_ada
          |> assets.add(test_policy_id, key, 1),
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
  let rdmr = RegistryInsert { key: short_key, hashed_param: test_hashed_param }
  call_insert_validator(rdmr, valid_insert_tx())
}

// Covering node's transfer_logic_script changed in output (NEW-1 fix)
test registry_insert_fails_updated_node_modified() fail {
  let key = computed_key()
  // Updated covering output with modified transfer_logic_script
  let tampered_output =
    Output {
      address: test_node_address,
      value: min_ada
        |> assets.add(test_policy_id, origin_node_tn, 1),
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
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    }
  let tx =
    Transaction {
      ..valid_insert_tx(),
      outputs: [tampered_output, inserted_node_output()],
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Programmable token not being minted (fails is_programmable_token_registration)
test registry_insert_fails_no_token_minted() fail {
  let tx = Transaction { ..valid_insert_tx(), mint: assets.zero }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Only one node output instead of two
test registry_insert_fails_single_output() fail {
  let tx =
    Transaction {
      ..valid_insert_tx(),
      outputs: [updated_covering_node_output()],
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}
