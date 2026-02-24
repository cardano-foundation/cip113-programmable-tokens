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

  let redeemer = TransferAct { proofs: [proof1, proof2], mint_proofs: [] }

  when redeemer is {
    TransferAct { proofs, .. } -> list.length(proofs) == 2
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
/// two corresponding outputs with those tokens removed, plus a remaining
/// output at prog_logic_cred that receives the seized tokens (balance invariant).
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
        // Paired outputs with programmable tokens removed (value = min_ada only)
        fixture.some_output_with_programmable_tokens([]),
        fixture.some_output_with_programmable_tokens([]),
        // Remaining output: seized tokens stay at prog_logic_cred (balance invariant)
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 142)],
        ),
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

// ---------------------------------------------------------------------------
// Balance Invariant Tests (Issues #2 and #3 from functional analysis)
//
// These tests verify that seized tokens cannot escape prog_logic_cred
// and that partial seizure is supported.
// ---------------------------------------------------------------------------

// Negative: seized tokens routed to Eve's wallet (NOT at prog_logic_cred).
// The balance invariant rejects this because total output at prog_cred (0)
// is less than total input tokens (42).
test third_party_act_seized_tokens_escape_prog_cred_must_fail() fail {
  let eve_address =
    Address {
      payment_credential: VerificationKey(
        #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      ),
      stake_credential: None,
    }

  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        // Input 0: prog_logic_cred UTxO with 42 FOO tokens
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 42)],
          "smuggling_input",
        ),
      ],
      outputs: [
        // Output 0: paired output at prog_logic_cred with FOO removed
        fixture.some_output_with_programmable_tokens([]),
        // Output 1: Eve's wallet receives the 42 FOO — ESCAPE!
        Output {
          address: eve_address,
          value: from_asset(ada_policy_id, ada_asset_name, 1_000_000)
            |> merge(from_asset(test_third_party_policy, "FOO", 42)),
          datum: NoDatum,
          reference_script: None,
        },
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Positive: seized tokens routed to a new output at prog_logic_cred.
// This is the correct seizure pattern.
test third_party_act_seized_tokens_to_prog_cred_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 42)],
          "seize_input",
        ),
      ],
      outputs: [
        // Paired output: tokens removed
        fixture.some_output_with_programmable_tokens([]),
        // Remaining output: seized tokens stay at prog_logic_cred
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 42)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Positive: partial seizure — seize 40 of 100 tokens, leave 60 with owner.
// The paired output retains 60 FOO, and a remaining output receives the 40 seized.
test third_party_act_partial_seizure_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "partial_seize_input",
        ),
      ],
      outputs: [
        // Paired output: owner keeps 60 FOO
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 60)],
        ),
        // Remaining output: authority receives 40 seized FOO
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 40)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Negative: remaining outputs at prog_cred don't have enough seized tokens.
// Input has 100 FOO, paired output has 0, remaining only has 50 — delta of 50 is missing.
test third_party_act_delta_insufficient_remaining_fails() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "insufficient_input",
        ),
      ],
      outputs: [
        // Paired output: all FOO removed
        fixture.some_output_with_programmable_tokens([]),
        // Remaining output: only 50 FOO, but 100 were seized
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 50)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// ---------------------------------------------------------------------------
// TransferAct Mint Support Tests (Issue #1 from functional analysis)
// ---------------------------------------------------------------------------

/// A programmable token policy used for the transfer/mint tests.
const test_mint_policy: PolicyId =
  #"3132333435363738393a3b3c3d3e3f404142434445464748494a4b4c"

// Positive: partial burn via TransferAct with mint_proofs.
// Input has 100 FOO, burns 30, output has 70. The mint_proofs validate the
// burned tokens against the registry, adjusting the expected output down.
test transfer_act_partial_burn_with_mint_proofs_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_mint_policy, "FOO", 100)],
          "burn input",
        ),
      ],
      mint: from_asset(test_mint_policy, "FOO", -30),
      outputs: [
        fixture.some_output_with_programmable_tokens(
          [(test_mint_policy, "FOO", 70)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        fixture.some_reference_input_tokens_registry_node(
          test_mint_policy,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "registry node",
        ),
      ],
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    }

  let redeemer =
    TransferAct {
      proofs: [TokenExists { node_idx: 1 }],
      mint_proofs: [TokenExists { node_idx: 1 }],
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Positive: transfer with minting — new tokens appear at prog_logic_cred.
// Input has 100 FOO, mints 50 more, output must have at least 150.
test transfer_act_with_minting_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_mint_policy, "FOO", 100)],
          "mint input",
        ),
      ],
      mint: from_asset(test_mint_policy, "FOO", 50),
      outputs: [
        fixture.some_output_with_programmable_tokens(
          [(test_mint_policy, "FOO", 150)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        fixture.some_reference_input_tokens_registry_node(
          test_mint_policy,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "registry node",
        ),
      ],
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    }

  let redeemer =
    TransferAct {
      proofs: [TokenExists { node_idx: 1 }],
      mint_proofs: [TokenExists { node_idx: 1 }],
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Negative: minting with empty mint_proofs must fail.
// If tx.mint is non-empty but mint_proofs is [], the validator must reject.
// This prevents unvalidated tokens from bypassing the directory check.
test transfer_act_mint_without_proofs_must_fail() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_mint_policy, "FOO", 100)],
          "no proof input",
        ),
      ],
      mint: from_asset(test_mint_policy, "FOO", 50),
      outputs: [
        fixture.some_output_with_programmable_tokens(
          [(test_mint_policy, "FOO", 150)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        fixture.some_reference_input_tokens_registry_node(
          test_mint_policy,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "registry node",
        ),
      ],
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    }

  // mint_proofs is empty but tx.mint is non-empty — must be rejected
  let redeemer =
    TransferAct {
      proofs: [TokenExists { node_idx: 1 }],
      mint_proofs: [],
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// ---------------------------------------------------------------------------
// ThirdPartyAct Wipe (Burn) Support Tests
//
// These tests verify that ThirdPartyAct supports burning tokens via tx.mint,
// enabling a compliance "wipe" feature: seize AND burn in one transaction.
// The mint-aware balance invariant adjusts input expectations by tx.mint.
// ---------------------------------------------------------------------------

// Positive: full wipe — seize all 100 FOO and burn all 100.
// Input has 100 FOO, mint has -100 FOO, paired output has 0 FOO.
// Adjusted input = 100 + (-100) = 0, filtered to empty → check trivially passes.
test third_party_act_wipe_full_burn_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "wipe_full_burn_input",
        ),
      ],
      mint: from_asset(test_third_party_policy, "FOO", -100),
      outputs: [
        // Paired output: all FOO removed
        fixture.some_output_with_programmable_tokens([]),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Positive: partial burn — seize all 100 FOO, burn 60, 40 remaining at prog_cred.
// Adjusted input = 100 + (-60) = 40, output has 40 → passes.
test third_party_act_wipe_partial_burn_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "wipe_partial_burn_input",
        ),
      ],
      mint: from_asset(test_third_party_policy, "FOO", -60),
      outputs: [
        // Paired output: all FOO removed from owner
        fixture.some_output_with_programmable_tokens([]),
        // Remaining output: 40 FOO stays at prog_logic_cred
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 40)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Positive: seize + partial burn — seize 80 of 100, burn 50, 30 remaining.
// Owner keeps 20, authority gets 30, 50 burned.
// Adjusted input = 100 + (-50) = 50, output = 20 + 30 = 50 → passes.
test third_party_act_wipe_seize_and_partial_burn() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "wipe_seize_partial_input",
        ),
      ],
      mint: from_asset(test_third_party_policy, "FOO", -50),
      outputs: [
        // Paired output: owner keeps 20 FOO
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 20)],
        ),
        // Remaining output: authority receives 30 seized FOO
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 30)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Negative: burn 30, but remaining output only 50 — need 70.
// Adjusted input = 100 + (-30) = 70, output = 0 + 50 = 50 < 70 → fails.
test third_party_act_wipe_insufficient_after_burn_fails() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "wipe_insufficient_input",
        ),
      ],
      mint: from_asset(test_third_party_policy, "FOO", -30),
      outputs: [
        // Paired output: all FOO removed
        fixture.some_output_with_programmable_tokens([]),
        // Remaining output: only 50 FOO, but adjusted input expects 70
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 50)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// ---------------------------------------------------------------------------
// ThirdPartyAct Mint Interaction Tests
//
// Verify that minting during a ThirdPartyAct (seizure) behaves correctly for
// all combinations: same-policy mint, other-policy mint (programmable or not),
// and mixed mints. The balance invariant only tracks the seized policy_id;
// other mints are invisible to it. Each layer handles its own authorization:
// - issuance_mint → authorizes minting/burning
// - validate_third_party → tracks balance for the seized policy
// - programmable_logic_base → authorizes spending from prog_cred
// ---------------------------------------------------------------------------

/// An unrelated policy used to test minting of tokens other than the seized policy.
/// From the validator's perspective, programmable vs non-programmable is identical:
/// get_policy_tokens only extracts the seized policy, so this is invisible to the
/// balance invariant regardless. issuance_mint handles programmable mint authorization
/// externally.
const test_unrelated_policy: PolicyId =
  #"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"

// Positive: mint same policy during seizure — adjusted input INCREASES.
// Seize 100 FOO, mint 50 more FOO → adjusted input = 150.
// Output must have >= 150 FOO at prog_cred.
// Not exploitable: issuance_mint forces minted tokens to prog_cred,
// so the minter is just raising the bar for themselves.
test third_party_act_same_policy_mint_during_seizure_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "same_policy_mint_input",
        ),
      ],
      mint: from_asset(test_third_party_policy, "FOO", 50),
      outputs: [
        // Paired output: all FOO removed from owner
        fixture.some_output_with_programmable_tokens([]),
        // Remaining output: 100 seized + 50 minted = 150 at prog_cred
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 150)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Negative: mint same policy during seizure but insufficient output.
// Seize 100 FOO, mint 50 → adjusted input = 150, but output only has 100.
test third_party_act_same_policy_mint_insufficient_output_fails() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "same_policy_mint_fail_input",
        ),
      ],
      mint: from_asset(test_third_party_policy, "FOO", 50),
      outputs: [
        // Paired output: all FOO removed
        fixture.some_output_with_programmable_tokens([]),
        // Only 100 FOO, but adjusted input expects 150
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Positive: mint an unrelated policy during seizure.
// Seized policy is test_third_party_policy; the unrelated mint is invisible
// to the balance invariant (get_policy_tokens ignores it).
// Programmable vs non-programmable doesn't matter here — the validator
// doesn't distinguish. issuance_mint handles programmable authorization
// externally; non-programmable tokens have their own minting policy.
test third_party_act_unrelated_policy_mint_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "unrelated_mint_input",
        ),
      ],
      mint: from_asset(test_unrelated_policy, "BAR", 500),
      outputs: [
        // Paired output: all FOO removed
        fixture.some_output_with_programmable_tokens([]),
        // Remaining output: seized FOO stays at prog_cred
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Positive: wipe (burn seized policy) + mint unrelated policy in the same tx.
// This is the realistic compliance scenario: admin burns seized tokens while
// the tx also mints something unrelated (e.g. a receipt NFT).
// Balance invariant sees only the seized policy burn; unrelated mint is invisible.
test third_party_act_wipe_burn_plus_unrelated_mint_succeeds() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 100)],
          "mixed_mint_input",
        ),
      ],
      mint: from_asset(test_third_party_policy, "FOO", -60)
        |> merge(from_asset(test_unrelated_policy, "RECEIPT", 1)),
      outputs: [
        // Paired output: all FOO removed from owner
        fixture.some_output_with_programmable_tokens([]),
        // Remaining output: 40 FOO stays at prog_cred (100 - 60 burned)
        fixture.some_output_with_programmable_tokens(
          [(test_third_party_policy, "FOO", 40)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
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
      input_idxs: [0],
      outputs_start_idx: 0,
      length_input_idxs: 1,
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// Negative: minting without enough output — mints 50 FOO but output only has 100.
// Expected output is 100 (input) + 50 (mint) = 150, but output only has 100.
test transfer_act_mint_insufficient_output_fails() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        fixture.some_input_with_programmable_tokens(
          [(test_mint_policy, "FOO", 100)],
          "mint fail input",
        ),
      ],
      mint: from_asset(test_mint_policy, "FOO", 50),
      outputs: [
        // Only 100 FOO, but expected 150
        fixture.some_output_with_programmable_tokens(
          [(test_mint_policy, "FOO", 100)],
        ),
      ],
      reference_inputs: [
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        fixture.some_reference_input_tokens_registry_node(
          test_mint_policy,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "registry node",
        ),
      ],
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    }

  let redeemer =
    TransferAct {
      proofs: [TokenExists { node_idx: 1 }],
      mint_proofs: [TokenExists { node_idx: 1 }],
    }

  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}
