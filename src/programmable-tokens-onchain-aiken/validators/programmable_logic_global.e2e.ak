//// End-to-end tests / benchmarks for programmable logic base+global validators

use aiken/crypto.{blake2b_256}
use cardano/address.{Address, Credential, Inline}
use cardano/assets.{AssetName, PolicyId, ada_asset_name, ada_policy_id}
use cardano/fuzz as cardano
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, Transaction}
use programmable_logic_base
use programmable_logic_global
use types.{
  ProgrammableLogicGlobalParams, ProgrammableLogicGlobalRedeemer, RegistryNode,
  TokenExists, TransferAct,
}

/// Run a 'Fuzzer' in-place, using a label as a seed. This can be used to
/// deterministically produce a single arbitrary value from a known fuzzer.
///
/// Different seeds give different values.
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

const fixture_programmable_token_name: AssetName = "FOO"

const fixture_registry_node_cs: PolicyId =
  #"000000000000000000000000000000000000000000000000000040de"

const fixture_protocol_params: ProgrammableLogicGlobalParams =
  ProgrammableLogicGlobalParams {
    registry_node_cs: fixture_registry_node_cs,
    prog_logic_cred: fixture_validator_logic_base,
  }

// Some redeemer with a single proof of a token in the registry, located at position #2 in reference inputs
const fixture_logic_global_redeemer: ProgrammableLogicGlobalRedeemer =
  TransferAct { proofs: [TokenExists { node_idx: 2 }] }

// A transaction doing a simple transfer from script-locked programmable tokens
const fixture_transaction_simple_transfer: Transaction = {
    let input_with_programmable_tokens =
      // An input holding programmable tokens being spent.
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
            |> assets.add(
                fixture_programmable_token_cs,
                fixture_programmable_token_name,
                42,
              ),
          datum: NoDatum,
          reference_script: None,
        },
      }

    let input_fuel =
      // Some input to pay for fuel
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

    let output_first_prog_value =
      // A first output with (still trapped) programmable tokens to some recipient
      Output {
        address: Address {
          payment_credential: fixture_validator_logic_base,
          stake_credential: Some(Inline(fixture_transfer_logic)),
        },
        value: assets.zero
          |> assets.add(ada_policy_id, ada_asset_name, 1140000)
          |> assets.add(
              fixture_programmable_token_cs,
              fixture_programmable_token_name,
              28,
            ),
        datum: NoDatum,
        reference_script: None,
      }

    let output_second_prog_value =
      // A second output with (still trapped) programmable tokens to some recipient
      Output {
        address: Address {
          payment_credential: fixture_validator_logic_base,
          stake_credential: Some(Inline(fixture_transfer_logic)),
        },
        value: assets.zero
          |> assets.add(ada_policy_id, ada_asset_name, 1130000)
          |> assets.add(
              fixture_programmable_token_cs,
              fixture_programmable_token_name,
              14,
            ),
        datum: NoDatum,
        reference_script: None,
      }

    let output_change =
      // Some change output
      Output {
        address: generate(cardano.address(), "change address"),
        value: assets.zero
          |> assets.add(ada_policy_id, ada_asset_name, 10000000000),
        datum: NoDatum,
        reference_script: None,
      }

    let reference_input_protocol_params =
      // Reference inputs with the protocol params. Identified by a specific NFT.
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
      // Token registry node ancestor, for inclusion validation
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
      // Token registry node holding the programmable policy being spent.
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
        // Reference inputs with the protocol params. Identified by a specific NFT.
        // Holds a ProtocolParams inline datum with configuration.
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
test bench_simple_transfer() {
  // Include both the base and global in the benchmark
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
