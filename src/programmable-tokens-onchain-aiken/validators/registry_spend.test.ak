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
  let other_cs: PolicyId =
    #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
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
    as_data(Void),
    tx,
  )
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
  let tx =
    Transaction {
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
  let tx =
    Transaction {
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
  let tx =
    Transaction {
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
  let tx =
    Transaction {
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
  let bad_ref_input =
    Input {
      ..protocol_params_ref_input(),
      output: Output {
        ..protocol_params_ref_input().output,
        datum: NoDatum,
      },
    }
  let tx =
    Transaction {
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
  let bad_ref_input =
    Input {
      ..protocol_params_ref_input(),
      output: Output {
        ..protocol_params_ref_input().output,
        datum: InlineDatum(as_data(42)),
      },
    }
  let tx =
    Transaction {
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
  let other_cs: PolicyId =
    #"9999999999999999999999999999999999999999999999999999999999"
  let tx =
    Transaction {
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
  let tx =
    Transaction {
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
  let tx =
    Transaction {
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
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [protocol_params_ref_input()],
      mint: assets.zero,
    }
  call_validator(tx)
}
