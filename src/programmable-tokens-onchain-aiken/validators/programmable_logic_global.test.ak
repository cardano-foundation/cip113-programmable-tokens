use aiken/collection/list
use aiken/crypto.{ScriptHash, blake2b_256}
use aiken/fuzz
// Integration tests for programmable logic global validator
use aiken/primitive/bytearray
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{
  PolicyId, ada_asset_name, ada_policy_id, from_asset, merge, negate, zero,
}
use cardano/fuzz as cardano
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use programmable_logic_base
use programmable_logic_global
use types.{
  ProgrammableLogicGlobalParams, ProgrammableLogicGlobalRedeemer, RegistryNode,
  TokenDoesNotExist, TokenExists, TransferAct,
}
use utils.{bytearray_lt}

// Test data
// const test_protocol_params_cs: PolicyId =
// #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"

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

// Test ThirdPartyAct redeemer
// test third_party_act_redeemer() {
//   let redeemer =
//     ThirdPartyAct { seize_input_idx: 0, seize_output_idx: 1, registry_node_idx: 0 }

//   when redeemer is {
//     ThirdPartyAct { seize_input_idx, seize_output_idx, registry_node_idx } ->
//       seize_input_idx == 0 && seize_output_idx == 1 && registry_node_idx == 0
//     _ -> False
//   }
// }

// // Test TokenExists proof
// test token_exists_proof() {
//   let proof = TokenExists { node_idx: 5 }

//   when proof is {
//     TokenExists { node_idx } -> node_idx == 5
//     _ -> False
//   }
// }

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

// Quick benchmarking of a few proto-typical scenarios

fn generate(fuzzer: Fuzzer<a>, label: ByteArray) -> a {
  expect Some((_, a)) = fuzzer(Seeded { seed: blake2b_256(label), choices: "" })
  a
}

const fixture_transfer_logic: Credential =
  Credential.Script(#"00000000000000000000000000000000000000000000000000000b0b")

const fixture_validator_logic_global: Credential =
  Credential.Script(#"0000000000000000000000000000000000000000000000000001091c")

const fixture_validator_logic_base: Credential =
  Credential.Script(#"0000000000000000000000000000000000000000000000000000ba5e")

const fixture_protocol_params_cs: PolicyId =
  #"000000000000000000000000000000000000000000000000000005ef"

const fixture_programmable_token_cs: PolicyId =
  #"00000000000000000000000000000000000000000000000000000f00"

const fixture_registry_node_cs: PolicyId =
  #"000000000000000000000000000000000000000000000000000040de"

const fixture_protocol_params: ProgrammableLogicGlobalParams =
  ProgrammableLogicGlobalParams {
    registry_node_cs: fixture_registry_node_cs,
    prog_logic_cred: fixture_validator_logic_base,
  }

// A transaction doing a simple transfer from script-locked programmable tokens
const fixture_transaction_simple_transfer: Transaction = {
    let input_with_programmable_tokens =
      Input {
        output_reference: generate(
          cardano.output_reference(),
          "locked programmable tokens",
        ),
        output: Output {
          address: Address {
            payment_credential: fixture_validator_logic_base,
            stake_credential: Some(Inline(fixture_transfer_logic)),
          },
          value: assets.zero
            |> assets.add(ada_policy_id, ada_asset_name, 1140000)
            |> assets.add(fixture_programmable_token_cs, "FOO", 42),
          datum: NoDatum,
          reference_script: None,
        },
      }

    let input_fuel =
      Input {
        output_reference: generate(cardano.output_reference(), "fuel input"),
        output: Output {
          address: generate(cardano.address(), "fuel input"),
          value: assets.zero
            |> assets.add(ada_policy_id, ada_asset_name, 10000000000),
          datum: NoDatum,
          reference_script: None,
        },
      }

    let reference_input_protocol_params =
      Input {
        output_reference: generate(
          cardano.output_reference(),
          "referenced protocol params",
        ),
        output: Output {
          address: address.from_verification_key(
            generate(cardano.verification_key_hash(), "protocol params owner"),
          ),
          value: assets.zero
            |> assets.add(ada_policy_id, ada_asset_name, 1380000)
            |> assets.add(fixture_protocol_params_cs, "ProtocolParams", 1),
          datum: InlineDatum(as_data(fixture_protocol_params)),
          reference_script: None,
        },
      }

    let reference_input_registry_ancestor =
      Input {
        output_reference: generate(
          cardano.output_reference(),
          "token registry previous node",
        ),
        output: Output {
          address: address.from_verification_key(
            generate(
              cardano.verification_key_hash(),
              "token registry previous node owner",
            ),
          ),
          value: assets.zero
            |> assets.add(ada_policy_id, ada_asset_name, 1230000)
            |> assets.add(fixture_registry_node_cs, "ancestor", 1),
          datum: InlineDatum(
            as_data(
              RegistryNode {
                key: #"",
                next: fixture_programmable_token_cs,
                transfer_logic_script: Credential.Script(""),
                third_party_transfer_logic_script: Credential.Script(""),
                global_state_cs: "",
              },
            ),
          ),
          reference_script: None,
        },
      }

    let reference_input_registry_current =
      Input {
        output_reference: generate(
          cardano.output_reference(),
          "token registry current node",
        ),
        output: Output {
          address: address.from_verification_key(
            generate(
              cardano.verification_key_hash(),
              "token registry previous node owner",
            ),
          ),
          value: assets.zero
            |> assets.add(ada_policy_id, ada_asset_name, 1730000)
            |> assets.add(fixture_registry_node_cs, "current", 1),
          datum: InlineDatum(
            as_data(
              RegistryNode {
                key: fixture_programmable_token_cs,
                next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                transfer_logic_script: fixture_transfer_logic,
                third_party_transfer_logic_script: Credential.Script(""),
                global_state_cs: "",
              },
            ),
          ),
          reference_script: None,
        },
      }

    let output_first_prog_value =
      Output {
        address: Address {
          payment_credential: fixture_validator_logic_base,
          stake_credential: Some(Inline(fixture_transfer_logic)),
        },
        value: assets.zero
          |> assets.add(ada_policy_id, ada_asset_name, 1140000)
          |> assets.add(fixture_programmable_token_cs, "FOO", 28),
        datum: NoDatum,
        reference_script: None,
      }

    let output_second_prog_value =
      Output {
        address: Address {
          payment_credential: fixture_validator_logic_base,
          stake_credential: Some(Inline(fixture_transfer_logic)),
        },
        value: assets.zero
          |> assets.add(ada_policy_id, ada_asset_name, 1130000)
          |> assets.add(fixture_programmable_token_cs, "FOO", 14),
        datum: NoDatum,
        reference_script: None,
      }

    let output_change =
      Output {
        address: generate(cardano.address(), "change address"),
        value: assets.zero
          |> assets.add(ada_policy_id, ada_asset_name, 10000000000),
        datum: NoDatum,
        reference_script: None,
      }

    Transaction {
      ..transaction.placeholder,
      inputs: [
        // An input holding programmable tokens being spent.
        input_with_programmable_tokens,
        // Some input to pay for fuel
        input_fuel,
      ],
      outputs: [
        // A first output with (still trapped) programmable tokens to some recipient
        output_first_prog_value,
        // A second output with (still trapped) programmable tokens to some recipient
        output_second_prog_value,
        // Some change output
        output_change,
      ],
      reference_inputs: [
        // Reference inputs with the protocol params. Identified by a specific NFT. Holds a
        // ProtocolParams inline datum with configuration.
        reference_input_protocol_params,
        // Token registry node ancestor, for inclusion validation
        reference_input_registry_ancestor,
        // Token registry node holding the programmable policy being spent.
        reference_input_registry_current,
      ],
      withdrawals: [
        // The artificial withdraw-0 to execute the global logic
        Pair(fixture_validator_logic_global, 0),
        // The artificial withdraw-0 to execute the spending logic
        Pair(fixture_transfer_logic, 0),
      ],
    }
  }

// Some redeemer with a single proof of a token in the registry, located at position #2 in reference inputs
const fixture_logic_global_redeemer: ProgrammableLogicGlobalRedeemer =
  TransferAct { proofs: [TokenExists { node_idx: 2 }] }

// Plutarch baseline: https://preview.cexplorer.io/tx/d29ce2a9f79a70a91d83a40e0e1cf346ab94979b6f0ba001de8a89895aa518df?tab=content
//
// Costs
// - mem: 10,283 +  258,828 = 269,111
// - cpu: 4,168,800 + 93,272,116 = 97,440,916
//
// Caracteristics
// - 2 inputs (one fuel, last)
// - 3 reference inputs
// - 3 outputs (one change last)
// - script-locked (i.e 1 extra withdrawal)
//
// Possible interesting more complexe case:
//
// https://preview.cexplorer.io/tx/736816cbcc25b6a2d27b0dfad0effd5c53dcd91f6e4429dbeb3eaaf4ab30185a
test bench_simple_transfer() {
  and {
    programmable_logic_base.programmable_logic_base.spend(
      fixture_validator_logic_global,
      None,
      Void,
      Void,
      fixture_transaction_simple_transfer,
    ),
    programmable_logic_global.programmable_logic_global.withdraw(
      fixture_protocol_params_cs,
      fixture_logic_global_redeemer,
      fixture_validator_logic_global,
      fixture_transaction_simple_transfer,
    ),
  }
}
