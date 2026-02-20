//// Comprehensive tests for the protocol_params_mint validator.
////
//// Tests invoke the validator's mint handler directly, covering:
//// - Happy path (all conditions met)
//// - One-shot UTxO consumption
//// - Token name and quantity checks
//// - Always-fail address enforcement
//// - InlineDatum and ProgrammableLogicGlobalParams datum validation

use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use protocol_params_mint
use types.{ProgrammableLogicGlobalParams, protocol_params_token}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_utxo_ref =
  OutputReference {
    transaction_id: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    output_index: 0,
  }

const test_always_fail_hash: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const test_policy_id: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const test_registry_node_cs: PolicyId =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const test_prog_logic_hash: ByteArray =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn always_fail_address() -> Address {
  Address {
    payment_credential: Script(test_always_fail_hash),
    stake_credential: None,
  }
}

fn valid_params_datum() -> Data {
  as_data(
    ProgrammableLogicGlobalParams {
      registry_node_cs: test_registry_node_cs,
      prog_logic_cred: Script(test_prog_logic_hash),
    },
  )
}

fn valid_nft_output() -> Output {
  Output {
    address: always_fail_address(),
    value: min_ada
      |> assets.add(test_policy_id, protocol_params_token, 1),
    datum: InlineDatum(valid_params_datum()),
    reference_script: None,
  }
}

fn valid_input() -> Input {
  Input {
    output_reference: test_utxo_ref,
    output: Output {
      address: Address {
        payment_credential: VerificationKey(
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ),
        stake_credential: None,
      },
      value: min_ada,
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn valid_transaction() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, protocol_params_token, 1),
    outputs: [valid_nft_output()],
  }
}

fn call_validator(
  utxo_ref: OutputReference,
  af_hash: ByteArray,
  tx: Transaction,
) -> Bool {
  protocol_params_mint.protocol_params_mint.mint(
    utxo_ref,
    af_hash,
    as_data(Void),
    test_policy_id,
    tx,
  )
}

// ========================================================================
// Happy path — all conditions met
// ========================================================================

test protocol_params_mint_valid() {
  call_validator(test_utxo_ref, test_always_fail_hash, valid_transaction())
}

// ========================================================================
// One-shot UTxO not consumed
// ========================================================================

test fails_when_utxo_not_consumed() fail {
  let wrong_utxo_ref =
    OutputReference {
      transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
      output_index: 99,
    }
  call_validator(wrong_utxo_ref, test_always_fail_hash, valid_transaction())
}

// ========================================================================
// Wrong token name — the `tn == protocol_params_token` check
//
// We mint "WrongName" but keep the output NFT as "ProtocolParams" so
// has_nft_strict and datum checks pass; only the token-name check fails.
// ========================================================================

test fails_with_wrong_token_name() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [valid_input()],
      mint: from_asset(test_policy_id, "WrongName", 1),
      outputs: [valid_nft_output()],
    }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// Quantity != 1 — the `qty == 1` check
//
// We mint qty=2 but keep the output with qty=1 so has_nft_strict passes;
// only the quantity check in the and-block fails.
// ========================================================================

test fails_when_quantity_is_not_one() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [valid_input()],
      mint: from_asset(test_policy_id, protocol_params_token, 2),
      outputs: [valid_nft_output()],
    }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// Multiple token names minted under the same policy
//
// The `expect [(_, tn, qty)] = own_minted` pattern crashes because
// the list has 2 elements instead of 1.
// ========================================================================

test fails_with_multiple_token_names_minted() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [valid_input()],
      mint: from_asset(test_policy_id, protocol_params_token, 1)
        |> assets.add(test_policy_id, "ExtraToken", 1),
      outputs: [valid_nft_output()],
    }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// No tokens minted from own policy
//
// The mint contains a different policy entirely, so `own_minted` is empty
// and `expect [(_, tn, qty)]` crashes.
// ========================================================================

test fails_when_no_tokens_minted_from_own_policy() fail {
  let other_policy: PolicyId =
    #"1111111111111111111111111111111111111111111111111111111111"
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [valid_input()],
      mint: from_asset(other_policy, "SomeToken", 1),
      outputs: [valid_nft_output()],
    }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// No output at the always-fail address
//
// The NFT goes to a completely different address.
// `expect Some(nft_output) = list.find(...)` crashes because no output
// matches the expected always-fail address.
// ========================================================================

test fails_when_no_output_at_always_fail_address() fail {
  let wrong_address =
    Address {
      payment_credential: Script(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      ),
      stake_credential: None,
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [valid_input()],
      mint: from_asset(test_policy_id, protocol_params_token, 1),
      outputs: [
        Output {
          address: wrong_address,
          value: min_ada
            |> assets.add(test_policy_id, protocol_params_token, 1),
          datum: InlineDatum(valid_params_datum()),
          reference_script: None,
        },
      ],
    }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// Output at always-fail address exists but does NOT contain the NFT
//
// `has_nft_strict(nft_output.value, own_policy, ...)` fails because
// the output at the always-fail address has only ADA.
// ========================================================================

test fails_when_nft_missing_from_always_fail_output() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [valid_input()],
      mint: from_asset(test_policy_id, protocol_params_token, 1),
      outputs: [
        // Output at always-fail address but WITHOUT the NFT
        Output {
          address: always_fail_address(),
          value: min_ada,
          datum: InlineDatum(valid_params_datum()),
          reference_script: None,
        },
      ],
    }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// No inline datum on the always-fail output
//
// `expect InlineDatum(datum) = nft_output.datum` crashes because the
// output uses NoDatum.
// ========================================================================

test fails_when_no_inline_datum() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [valid_input()],
      mint: from_asset(test_policy_id, protocol_params_token, 1),
      outputs: [Output { ..valid_nft_output(), datum: NoDatum }],
    }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// Invalid datum type — datum is not ProgrammableLogicGlobalParams
//
// `expect _params: ProgrammableLogicGlobalParams = datum` crashes because
// an Int doesn't match the ProgrammableLogicGlobalParams constructor.
// ========================================================================

test fails_with_invalid_datum_type() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [valid_input()],
      mint: from_asset(test_policy_id, protocol_params_token, 1),
      outputs: [
        Output { ..valid_nft_output(), datum: InlineDatum(as_data(42)) },
      ],
    }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}
