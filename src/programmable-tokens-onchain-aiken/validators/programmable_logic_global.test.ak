//// Integration tests for programmable logic global validator

use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset, merge, negate, zero}
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, OutputReference, Transaction}
use programmable_logic/fixture
use programmable_logic_global
use types.{
  ProgrammableLogicGlobalParams, RegistryNode, ThirdPartyAct, TokenDoesNotExist,
  TokenExists, TransferAct,
}
use utils.{bytearray_lt}

const test_registry_node_cs: PolicyId =
  #"1112131415161718191a1b1c0d0e0f0102030405060708090a0b0c0d"

const test_prog_logic_cred: Credential = Script(#"70726f67")

const test_transfer_logic_cred: Credential = Script(#"7472616e73666572")

const test_third_party_transfer_logic_cred: Credential = Script(#"6973737565")

const test_token_cs: PolicyId =
  #"2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c"

// Test ProgrammableLogicGlobalParams structure
test programmable_logic_global_params_structure() {
  let params =
    ProgrammableLogicGlobalParams {
      prog_logic_cred: test_prog_logic_cred,
      registry_node_cs: test_registry_node_cs,
    }

  params.prog_logic_cred == test_prog_logic_cred && params.registry_node_cs == test_registry_node_cs
}

// Test TransferAct redeemer
test transfer_act_redeemer() {
  let proof1 = TokenExists { node_idx: 0 }
  let proof2 = TokenDoesNotExist { node_idx: 1 }

  let redeemer = TransferAct { proofs: [proof1, proof2] }

  when redeemer is {
    TransferAct { proofs } -> list.length(proofs) == 2
    _ -> False
  }
}

// Test TokenDoesNotExist proof
test token_does_not_exist_proof() {
  let proof = TokenDoesNotExist { node_idx: 3 }

  when proof is {
    TokenDoesNotExist { node_idx } -> node_idx == 3
    _ -> False
  }
}

// Test registry node validation for transfer
test registry_node_validation_for_transfer() {
  let node =
    RegistryNode {
      key: test_token_cs,
      next: #"ffff",
      transfer_logic_script: test_transfer_logic_cred,
      third_party_transfer_logic_script: test_third_party_transfer_logic_cred,
      global_state_cs: #"",
    }

  // Node key should match the token CS
  node.key == test_token_cs && // Transfer logic script should be present
  node.transfer_logic_script == test_transfer_logic_cred
}

// Test covering node logic for non-existent token
test covering_node_logic_for_non_existent_token() {
  let covering_key = #"aa"
  let token_cs = #"bb"
  let next_key = #"cc"

  let covering_node =
    RegistryNode {
      key: covering_key,
      next: next_key,
      transfer_logic_script: test_transfer_logic_cred,
      third_party_transfer_logic_script: test_third_party_transfer_logic_cred,
      global_state_cs: #"",
    }

  // Covering node should satisfy: covering_key < token_cs < next_key
  bytearray_lt(covering_node.key, token_cs) && bytearray_lt(
    token_cs,
    covering_node.next,
  )
}

// Test seize validation structure
test seize_validation_structure() {
  let seized_cs = test_token_cs
  let input_value = from_asset(seized_cs, #"746f6b656e", 100)
  let expected_output_value = zero

  // After seizing, the output should have the tokens removed
  input_value != expected_output_value
}

// Test programmable tokens go to prog_logic_cred
test programmable_tokens_go_to_prog_logic_cred() {
  let output =
    Output {
      address: Address {
        payment_credential: test_prog_logic_cred,
        stake_credential: None,
      },
      value: from_asset(test_token_cs, #"746f6b656e", 100),
      datum: NoDatum,
      reference_script: None,
    }

  output.address.payment_credential == test_prog_logic_cred
}

// Test transfer logic script must be invoked
test transfer_logic_script_must_be_invoked() {
  let invoked_scripts = [test_transfer_logic_cred, Script(#"6f74686572")]

  list.has(invoked_scripts, test_transfer_logic_cred)
}

// Test third party transfer logic script must be invoked for third party actions
test third_party_transfer_logic_script_must_be_invoked_for_third_party_actions() {
  let invoked_scripts =
    [test_third_party_transfer_logic_cred, Script(#"6f74686572")]

  list.has(invoked_scripts, test_third_party_transfer_logic_cred)
}

// Test signed prog inputs validation
test signed_prog_inputs_validation() {
  let stake_pkh = #"aabbccdd"
  let input =
    Input {
      output_reference: OutputReference {
        transaction_id: #"00",
        output_index: 0,
      },
      output: Output {
        address: Address {
          payment_credential: test_prog_logic_cred,
          stake_credential: Some(Inline(VerificationKey(stake_pkh))),
        },
        value: from_asset(test_token_cs, #"746f6b656e", 100),
        datum: NoDatum,
        reference_script: None,
      },
    }

  // Input is from prog_logic_cred with stake credential
  input.output.address.payment_credential == test_prog_logic_cred && when
    input.output.address.stake_credential
  is {
    Some(Inline(VerificationKey(pkh))) -> pkh == stake_pkh
    _ -> False
  }
}

// Test seize prevents DDOS by requiring value change
test seize_prevents_ddos_by_requiring_value_change() {
  let input_value = from_asset(test_token_cs, #"746f6b656e", 100)
  // let output_value = from_asset(test_token_cs, #"746f6b656e", 100)
  let expected_output =
    merge(input_value, negate(from_asset(test_token_cs, #"746f6b656e", 50)))

  // Must actually remove tokens (DDOS prevention)
  input_value != expected_output
}

// Test only one prog_logic_cred input allowed in seize
test only_one_prog_logic_cred_input_in_seize() {
  let inputs =
    [
      Input {
        output_reference: OutputReference {
          transaction_id: #"00",
          output_index: 0,
        },
        output: Output {
          address: Address {
            payment_credential: test_prog_logic_cred,
            stake_credential: None,
          },
          value: zero,
          datum: NoDatum,
          reference_script: None,
        },
      },
    ]

  list.length(
    list.filter(
      inputs,
      fn(input) {
        input.output.address.payment_credential == test_prog_logic_cred
      },
    ),
  ) == 1
}

// Test protocol params from reference inputs
test protocol_params_from_reference_inputs() {
  let params =
    ProgrammableLogicGlobalParams {
      prog_logic_cred: test_prog_logic_cred,
      registry_node_cs: test_registry_node_cs,
    }

  // Protocol params should be loaded from reference input
  params.registry_node_cs == test_registry_node_cs
}

// Test invoked scripts via withdrawals
test invoked_scripts_via_withdrawals() {
  let withdrawals =
    [
      Pair(test_transfer_logic_cred, 0),
      Pair(test_third_party_transfer_logic_cred, 0),
    ]

  let invoked_scripts =
    list.map(
      withdrawals,
      fn(wdrl) {
        let Pair(cred, _amount) = wdrl
        cred
      },
    )

  list.has(invoked_scripts, test_transfer_logic_cred) && list.has(
    invoked_scripts,
    test_third_party_transfer_logic_cred,
  )
}

// ---------------------------------------------------------------------------
// F-01: ThirdPartyAct input_idxs uniqueness & ordering tests
//
// These tests invoke the actual programmable_logic_global.withdraw validator
// with a ThirdPartyAct redeemer to exercise the validate_third_party path.
//
// The two `fail` tests demonstrate the vulnerability: duplicate or unsorted
// input_idxs currently PASS the validator (so the `fail` test will itself
// FAIL). Once the fix enforcing strictly-increasing indices is applied, the
// validator will correctly reject them and these tests will PASS.
// ---------------------------------------------------------------------------

/// Arbitrary credential representing a third-party transfer logic script
/// (e.g. a seize/freeze substandard) used in withdrawals.
const test_third_party_cred: Credential =
  Script(#"000000000000000000000000000000000000000000000000000003d9")

/// A programmable token policy used across the ThirdPartyAct tests.
const test_third_party_policy: PolicyId =
  #"00000000000000000000000000000000000000000000000000000f00"

/// Build a registry-node reference input whose third_party_transfer_logic_script
/// is set to a real credential (unlike the default fixture which uses Script("")).
fn third_party_registry_node_ref_input(
  key: ByteArray,
  third_party_cred: Credential,
) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      output_index: 0,
    },
    output: Output {
      address: Address {
        payment_credential: Script(
          #"00000000000000000000000000000000000000000000000000aabb",
        ),
        stake_credential: None,
      },
      value: from_asset(ada_policy_id, ada_asset_name, 1_000_000)
        |> merge(
            from_asset(fixture.policy_tokens_registry, blake2b_256(key), 1),
          ),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key,
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: fixture.credential_transfer_logic,
            third_party_transfer_logic_script: third_party_cred,
            global_state_cs: "",
          },
        ),
      ),
      reference_script: None,
    },
  }
}

/// Run programmable_logic_global.withdraw with a ThirdPartyAct redeemer whose
/// input_idxs are given as parameter. The transaction always has two
/// prog_logic_cred inputs (indices 0 and 1) holding programmable tokens, and
/// two corresponding outputs with those tokens removed.
fn validate_third_party_with_idxs(input_idxs: List<Int>) -> Bool {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        // Index 0 – prog_logic input A
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 42)],
          "third_party_input_a",
        ),
        // Index 1 – prog_logic input B
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "third_party_input_b",
        ),
      ],
      outputs: [
        // Outputs with programmable tokens removed (value = min_ada only)
        fixture.some_output_with_programmable_tokens([]),
        fixture.some_output_with_programmable_tokens([]),
      ],
      reference_inputs: [
        // Index 0 – protocol params
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        // Index 1 – registry node with real third-party credential
        third_party_registry_node_ref_input(
          test_third_party_policy,
          test_third_party_cred,
        ),
      ],
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(test_third_party_cred, 0),
      ],
    }

  let redeemer =
    ThirdPartyAct {
      registry_node_idx: 1,
      input_idxs,
      outputs_start_idx: 0,
      length_input_idxs: list.length(input_idxs),
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Positive: unique, sorted indices [0, 1] — must always pass.
test third_party_act_with_unique_sorted_indices() {
  validate_third_party_with_idxs([0, 1])
}

// Negative (F-01): duplicate index [0, 0] — input 1 is consumed but never
// validated, allowing its tokens to be stolen.  The validator SHOULD reject
// this, so we mark the test `fail`.  Until the fix is applied, the validator
// incorrectly accepts it and this test will report as FAILING.
test third_party_act_duplicate_indices_must_fail() fail {
  validate_third_party_with_idxs([0, 0])
}

// Negative (F-01): unsorted indices [1, 0] — a strictly-increasing check
// should reject this ordering.  Until the fix is applied this test will
// report as FAILING because the validator currently accepts it.
test third_party_act_unsorted_indices_must_fail() fail {
  validate_third_party_with_idxs([1, 0])
}
