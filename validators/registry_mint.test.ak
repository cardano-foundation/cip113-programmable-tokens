//// Tests for the registry_mint validator.
//// Invokes the validator's mint handler directly, covering both
//// RegistryInit and RegistryInsert redeemer paths.

use cardano/address.{Address, Credential, Inline, Script}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, Transaction,
}
use issuance_mint
use registry_mint
use registry_node.{RegistryNode, empty_vkey, origin_node_tn}
use types.{
  IssuanceCborHex, RefInput, RegistryInit, RegistryInsert, RegistryRedeemer,
  SmartTokenMintingAction,
}
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
    Script(#"cccccccc"),
    RegistryInit,
    test_policy_id,
    tx,
  )
}

fn call_insert_validator(redeemer: RegistryRedeemer, tx: Transaction) -> Bool {
  registry_mint.registry_mint.mint(
    test_utxo_ref,
    test_issuance_cbor_hex_cs,
    Script(#"cccccccc"),
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

// =========================================================================
// CIP-68 multi-asset registration
//
// is_programmable_token_registration now allows multiple asset names under
// the same policy to support CIP-68 (FT label 333 + ref token label 100).
// =========================================================================

// CIP-67 label 333 (FT) prefix + "MyToken" hex
const cip68_ft_name = #"000f41414d79546f6b656e"

// CIP-67 label 100 (reference) prefix + "MyToken" hex
const cip68_ref_name = #"000643b04d79546f6b656e"

// Happy path: register with CIP-68 dual-token mint (FT + ref token)
test registry_insert_cip68_dual_token_mint() {
  let key = computed_key()
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [covering_node_input()],
      outputs: [updated_covering_node_output(), inserted_node_output()],
      reference_inputs: [issuance_ref_input()],
      mint: from_asset(test_policy_id, key, 1)
        |> assets.add(key, cip68_ft_name, 1_000_000)
        |> assets.add(key, cip68_ref_name, 1),
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// Burn-during-registration (defense-in-depth)
//
// Burning tokens requires prior minting, which requires prior registration,
// and the linked list prevents duplicate inserts — so this scenario is
// logically impossible in practice. The amount > 0 check makes the
// invariant explicit locally.
// =========================================================================

// Burn-only: no positive mint amount for the programmable token policy — must fail
test registry_insert_fails_burn_only() fail {
  let key = computed_key()
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [covering_node_input()],
      outputs: [updated_covering_node_output(), inserted_node_output()],
      reference_inputs: [issuance_ref_input()],
      // Registry node NFT is minted, but programmable token policy only burns
      mint: from_asset(test_policy_id, key, 1)
        |> assets.add(key, #"746f6b656e", -100),
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Mixed mint+burn: one asset name positive, another negative — should pass
// (at least one asset name has amount > 0)
test registry_insert_mixed_mint_and_burn() {
  let key = computed_key()
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [covering_node_input()],
      outputs: [updated_covering_node_output(), inserted_node_output()],
      reference_inputs: [issuance_ref_input()],
      mint: from_asset(test_policy_id, key, 1)
        |> assets.add(key, cip68_ft_name, 1_000_000)
        |> assets.add(key, #"6f6c64746f6b656e", -50),
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// CIP-68 subsequent mint (RefInput registry proof) in issuance_mint
//
// Exercises issuance_mint with CIP-68 dual-token mint + RefInput proof,
// covering the path where the registry already exists from a prior insert.
// =========================================================================

// issuance_mint validator params
const ism_plb_cred: Credential =
  Script(#"aa11111111111111111111111111111111111111111111111111111111")

const ism_registry_cs: PolicyId =
  #"aa22222222222222222222222222222222222222222222222222222222"

const ism_ml_cred: Credential =
  Script(#"aa33333333333333333333333333333333333333333333333333333333")

const ism_plg_cred: Credential =
  Script(#"aa55555555555555555555555555555555555555555555555555555555")

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

fn call_issuance_validator(
  rdmr: SmartTokenMintingAction,
  tx: Transaction,
) -> Bool {
  issuance_mint.issuance_mint.mint(
    ism_plb_cred,
    ism_registry_cs,
    ism_ml_cred,
    ism_plg_cred,
    rdmr,
    ism_own_policy,
    tx,
  )
}

// CIP-68 subsequent mint with RefInput: FT + ref token, registry already exists
test cip68_subsequent_mint_ref_input() {
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: ism_ml_cred,
      minting_registry_proof: RefInput(0),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [ism_ref_input()],
      outputs: [
        ism_plb_output(
          min_ada
            |> assets.add(ism_own_policy, cip68_ft_name, 500),
        ),
        ism_plb_output(
          min_ada
            |> assets.add(ism_own_policy, cip68_ref_name, 1),
        ),
      ],
      mint: from_asset(ism_own_policy, cip68_ft_name, 500)
        |> assets.add(ism_own_policy, cip68_ref_name, 1),
      withdrawals: [Pair(ism_ml_cred, 0)],
      redeemers: [Pair(Mint(ism_own_policy), as_data(rdmr))],
    }
  call_issuance_validator(rdmr, tx)
}
