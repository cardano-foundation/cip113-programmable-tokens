//// End-to-end tests / benchmarks for programmable logic base+global validators

use aiken/collection/list
use aiken/fuzz
use cardano/assets.{AssetName, PolicyId}
use cardano/fuzz as cardano
use cardano/transaction.{Input, Output, OutputReference, Transaction}
use programmable_logic/fixture
use programmable_logic_base
use programmable_logic_global
use types.{
  ProgrammableLogicGlobalRedeemer, ThirdPartyAct, TokenDoesNotExist, TokenExists,
  TransferAct,
}

fn programmable_logic(
  self: Transaction,
  redeemer: ProgrammableLogicGlobalRedeemer,
) -> Bool {
  // Include both the base and global in the benchmark
  and {
    programmable_logic_base.programmable_logic_base.spend(
      fixture.credential_validator_logic_global,
      None,
      Void,
      Void,
      self,
    ),
    programmable_logic_global.programmable_logic_global.withdraw(
      fixture.policy_protocol_params,
      redeemer,
      fixture.credential_validator_logic_global,
      self,
    ),
  }
}

/// --- Plutarch baseline (3rd party) ---------------------------------------------------------------
///
/// Replicate a Preview 3rd-party transaction based on the Plutarch version of the
/// programmable logic validators. This transaction has been used as a benchmark
/// for optimisation and improvements over the Aiken version.
///
/// Characteristics:
/// - seize all tokens from 1 UTxO
/// - sends them to a single output
/// - no minting and burning
/// - no other tokens
///
/// Source: https://preview.cexplorer.io/tx/d29a977a55ed54ef0f5c9d5c15f85a63e915349890f1952934809070430ef33a
const fixture_plutarch_baseline_3rd_party: Transaction = {
    let policy_programmable_token: PolicyId =
      #"76658c4afd597ba7524f85bf32ac59d9e58856593a2e8399326f853a"

    let asset_name_programmable_token: AssetName = "tUSDT"

    Transaction {
      ..transaction.placeholder,
      inputs: [
        // Some input to pay for fuel, which has to be 1st input in this scenario, so we enforce the id
        // to be lexicographically before the second.
        Input {
          output_reference: OutputReference {
            transaction_id: #"6ef7ec1c8b5dc017042fed2eff90c3f6e4742e8a686099f95eaf73a1d403c402",
            output_index: 3,
          },
          output: fixture.some_input_fuel("fuel input").output,
        },
        // An input holding programmable tokens being spent.
        Input {
          output_reference: OutputReference {
            transaction_id: #"c5972f88da7442689b281d8a85c43321d0fbf32b8f41d4e9a968e0d3edda9a71",
            output_index: 1,
          },
          output: fixture.some_input_with_programmable_tokens(
            [
              (
                policy_programmable_token,
                asset_name_programmable_token,
                999999999999,
              ),
            ],
            "programmable tokens",
          ).output,
        },
      ],
      outputs: [
        // Some dust/noise
        fixture.some_output_change("noise output"),
        // All unburned seized tokens sent to a single output
        fixture.some_output_with_seized_tokens(
          [
            (
              policy_programmable_token,
              asset_name_programmable_token,
              999999999999,
            ),
          ],
        ),
        // The first seized input, minus the (partially) seized tokens
        fixture.some_output_with_programmable_tokens([]),
        // Some change output
        fixture.some_output_change("change output"),
      ],
      reference_inputs: [
        // Reference inputs with the protocol params. Identified by a specific NFT.
        // Holds a ProtocolParams inline datum with configuration.
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        // Token registry node holding the programmable policy being spent.
        fixture.some_reference_input_tokens_registry_node(
          policy_programmable_token,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "current",
        ),
      ],
      withdrawals: fixture.withdrawals_3rd_party,
    }
  }

const fixture_redeemer_plutarch_baseline_3rd_party: ProgrammableLogicGlobalRedeemer =
  ThirdPartyAct {
    registry_node_idx: 1,
    input_idxs: [1],
    outputs_start_idx: 2,
    length_input_idxs: 1,
  }

// Plutarch => [mem: 228.09K cpu: 85.23M]
test plutarch_baseline_3rd_party() {
  programmable_logic(
    fixture_plutarch_baseline_3rd_party,
    fixture_redeemer_plutarch_baseline_3rd_party,
  )
}

/// -------------------------------------------------------------------------------------------------
/// --- Plutarch baseline 2 (3rd party) -------------------------------------------------------------
///
/// A slightly more interesting scenario than the baseline #1, which mostly adds "noise":
///
/// - inputs contain other tokens
/// - seizing from multiple inputs
/// - one partial and one total seizing
/// - burning tokens
/// -------------------------------------------------------------------------------------------------
const fixture_plutarch_baseline_3rd_party_2: Transaction = {
    let policy_programmable_token: PolicyId =
      #"76658c4afd597ba7524f85bf32ac59d9e58856593a2e8399326f853a"

    let asset_name_programmable_token: AssetName = "tUSDT"

    let other_prog_tokens_1 =
      (#"00000000000000000000000000000000000000000000000000000000", "foo", 14)

    let other_prog_tokens_2 =
      (#"11111111111111111111111111111111111111111111111111111111", "bar", 42)

    let other_prog_tokens_3 =
      (#"99999999999999999999999999999999999999999999999999999999", "baz", 1)

    Transaction {
      ..transaction.placeholder,
      inputs: [
        // An input holding programmable tokens being spent.
        Input {
          output_reference: OutputReference {
            transaction_id: #"00072f88da7442689b281d8a85c43321d0fbf32b8f41d4e9a968e0d3edda9a71",
            output_index: 1,
          },
          output: fixture.some_input_with_programmable_tokens(
            [
              other_prog_tokens_1,
              (
                policy_programmable_token,
                asset_name_programmable_token,
                999999999999,
              ),
            ],
            "programmable tokens",
          ).output,
        },
        // Some input to pay for fuel
        Input {
          output_reference: OutputReference {
            transaction_id: #"6ef7ec1c8b5dc017042fed2eff90c3f6e4742e8a686099f95eaf73a1d403c402",
            output_index: 3,
          },
          output: fixture.some_input_fuel("fuel input").output,
        },
        // An input holding programmable tokens being spent.
        Input {
          output_reference: OutputReference {
            transaction_id: #"c5972f88da7442689b281d8a85c43321d0fbf32b8f41d4e9a968e0d3edda9a71",
            output_index: 1,
          },
          output: fixture.some_input_with_programmable_tokens(
            [
              other_prog_tokens_2,
              (
                policy_programmable_token,
                asset_name_programmable_token,
                999999999999,
              ), other_prog_tokens_3,
            ],
            "programmable tokens",
          ).output,
        },
      ],
      outputs: [
        // Some dust/noise
        fixture.some_output_change("noise output"),
        // All unburned seized tokens sent to a single output
        fixture.some_output_with_seized_tokens(
          [
            (
              policy_programmable_token,
              asset_name_programmable_token,
              500000000000,
            ),
          ],
        ),
        // The first seized input, minus the (partially) seized tokens
        fixture.some_output_with_programmable_tokens(
          [
            other_prog_tokens_1,
            (
              policy_programmable_token,
              asset_name_programmable_token,
              999999999998,
            ),
          ],
        ),
        // The second seized input, minus the (integrally) seized tokens
        fixture.some_output_with_programmable_tokens(
          [other_prog_tokens_2, other_prog_tokens_3],
        ),
        // Some change output
        fixture.some_output_change("change output"),
      ],
      mint: assets.zero
        |> assets.add(
            policy_programmable_token,
            asset_name_programmable_token,
            -500000000000,
          ),
      reference_inputs: [
        // Reference inputs with the protocol params. Identified by a specific NFT.
        // Holds a ProtocolParams inline datum with configuration.
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        // Token registry node holding the programmable policy being spent.
        fixture.some_reference_input_tokens_registry_node(
          policy_programmable_token,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "current",
        ),
      ],
      withdrawals: fixture.withdrawals_3rd_party,
    }
  }

const fixture_redeemer_plutarch_baseline_3rd_party_2: ProgrammableLogicGlobalRedeemer =
  ThirdPartyAct {
    registry_node_idx: 1,
    input_idxs: [0, 1],
    outputs_start_idx: 2,
    length_input_idxs: 2,
  }

test plutarch_baseline_3rd_party_2() {
  programmable_logic(
    fixture_plutarch_baseline_3rd_party_2,
    fixture_redeemer_plutarch_baseline_3rd_party_2,
  )
}

/// --- Plutarch baseline (transfer) ---------------------------------------------------------------
///
/// Replicate a Preview transfer transaction based on the Plutarch version of the
/// programmable logic validator. This transaction has been used as a benchmark
/// for optimisation and improvements over the Aiken version.
///
/// Characteristics:
/// - 2 inputs: one script-locked, one for fuel
/// - 3 outputs: two with programmable tokens, and one for change
/// - one programmable token kind (i.e. two nodes from the registry referenced)
/// - transfer logic is script-based, provided as withdrawal
///
/// Source: https://preview.cexplorer.io/tx/d29ce2a9f79a70a91d83a40e0e1cf346ab94979b6f0ba001de8a89895aa518df
/// ------------------------------------------------------------------------------------------------
const fixture_plutarch_baseline_transfer: Transaction = {
    let policy_programmable_token: PolicyId =
      #"00000000000000000000000000000000000000000000000000000f00"

    let asset_name_programmable_token: AssetName = "FOO"

    Transaction {
      ..transaction.placeholder,
      inputs: [
        // An input holding programmable tokens being spent.
        fixture.some_input_with_programmable_tokens(
          [(policy_programmable_token, asset_name_programmable_token, 42)],
          "programmable tokens input",
        ),
        // Some input to pay for fuel
        fixture.some_input_fuel("fuel input"),
      ],
      outputs: [
        // A first output with (still trapped) programmable tokens to some recipient
        fixture.some_output_with_programmable_tokens(
          [(policy_programmable_token, asset_name_programmable_token, 28)],
        ),
        // A second output with (still trapped) programmable tokens to some recipient
        fixture.some_output_with_programmable_tokens(
          [(policy_programmable_token, asset_name_programmable_token, 14)],
        ),
        // Some change output
        fixture.some_output_change("change output"),
      ],
      reference_inputs: [
        // Reference inputs with the protocol params. Identified by a specific NFT.
        // Holds a ProtocolParams inline datum with configuration.
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        // Token registry node ancestor, for inclusion validation
        fixture.some_reference_input_tokens_registry_node(
          "",
          policy_programmable_token,
          "ancestor",
        ),
        // Token registry node holding the programmable policy being spent.
        fixture.some_reference_input_tokens_registry_node(
          policy_programmable_token,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "current",
        ),
      ],
      withdrawals: fixture.withdrawals_transfer,
    }
  }

/// Corresponding redeemer with a single proof of a token in the registry,
/// located at position #2 in reference inputs
const fixture_redeemer_plutarch_baseline_transfer: ProgrammableLogicGlobalRedeemer =
  TransferAct { proofs: [TokenExists { node_idx: 2 }] }

test plutarch_baseline_transfer() {
  programmable_logic(
    fixture_plutarch_baseline_transfer,
    fixture_redeemer_plutarch_baseline_transfer,
  )
}

/// --- Plutarch baseline 2 (transfer) ---------------------------------------------------------------
///
/// Another baseline from the transfer act that is obtained by making the first one slightly more complexe,
/// although still plausible, having multiple policies and minting and collecting tokens over several
/// inputs.
/// ------------------------------------------------------------------------------------------------
const fixture_plutarch_baseline_transfer_2: Transaction = {
    let policy_programmable_token_1: PolicyId =
      #"00000000000000000000000000000000000000000000000000000f00"

    let asset_name_programmable_token_1: AssetName = "FOO"

    let policy_programmable_token_2: PolicyId =
      #"00000000000000000000000000000000000000000000000000000ba5"

    let asset_name_programmable_token_2: AssetName = "BAR"

    let policy_unexisting_token: PolicyId =
      #"000000000000000000000000000000000000000000000000aaaaffff"

    let asset_name_unexisting_token: PolicyId = "e_e"

    Transaction {
      ..transaction.placeholder,
      inputs: [
        // An input holding programmable tokens being spent, as well as some unregistered token
        fixture.some_input_with_programmable_tokens(
          [
            (policy_programmable_token_1, asset_name_programmable_token_1, 42),
            (policy_programmable_token_2, asset_name_programmable_token_2, 1),
            (policy_unexisting_token, asset_name_unexisting_token, 1),
          ],
          "programmable tokens input",
        ),
        // Some input to pay for fuel
        fixture.some_input_fuel("fuel input"),
      ],
      outputs: [
        // A first output with (still trapped) programmable tokens to some recipient
        fixture.some_output_with_programmable_tokens(
          [
            (policy_programmable_token_1, asset_name_programmable_token_1, 28),
            (policy_programmable_token_2, asset_name_programmable_token_2, 1),
          ],
        ),
        // A second output with (still trapped) programmable tokens to some recipient
        fixture.some_output_with_programmable_tokens(
          [(policy_programmable_token_1, asset_name_programmable_token_1, 113)],
        ),
        // Unregistered programmable tokens moved out of a programmable output
        Output {
          ..fixture.some_output_change("fake prog tokens"),
          value: fixture.min_ada_value
            |> assets.add(
                policy_unexisting_token,
                asset_name_unexisting_token,
                1,
              ),
        },
        // Some change output
        fixture.some_output_change("change output"),
      ],
      mint: assets.zero
        |> assets.add(
            policy_programmable_token_1,
            asset_name_programmable_token_1,
            99,
          ),
      reference_inputs: [
        // Reference inputs with the protocol params. Identified by a specific NFT.
        // Holds a ProtocolParams inline datum with configuration.
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        // Token registry node ancestor, for inclusion validation
        fixture.some_reference_input_tokens_registry_node(
          "",
          policy_programmable_token_2,
          "ancestor",
        ),
        // Token registry node holding the programmable policy being spent.
        fixture.some_reference_input_tokens_registry_node(
          policy_programmable_token_2,
          policy_programmable_token_1,
          "token_2",
        ),
        // Token registry node holding the programmable policy being spent.
        fixture.some_reference_input_tokens_registry_node(
          policy_programmable_token_1,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "token_1",
        ),
      ],
      withdrawals: fixture.withdrawals_transfer,
    }
  }

/// Corresponding redeemer with a single proof of a token in the registry,
/// located at position #2 in reference inputs
const fixture_redeemer_plutarch_baseline_transfer_2: ProgrammableLogicGlobalRedeemer =
  TransferAct {
    proofs: [
      TokenExists { node_idx: 2 },
      TokenExists { node_idx: 3 },
      TokenDoesNotExist { node_idx: 3 },
    ],
  }

test plutarch_baseline_transfer_2() {
  programmable_logic(
    fixture_plutarch_baseline_transfer_2,
    fixture_redeemer_plutarch_baseline_transfer_2,
  )
}

/// --- Bench: tokens ------------------------------------------------------------------------------
///
/// A benchmark evaluating the impact of increasing the number of tokens from a
/// same policy in a transfer. All tokens are located at a single TxO, and
/// transfered to a single address.
/// ------------------------------------------------------------------------------------------------
fn sample_many_tokens(
  size: Int,
) -> Fuzzer<(Transaction, ProgrammableLogicGlobalRedeemer)> {
  let policy_programmable_token: PolicyId =
    #"00000000000000000000000000000000000000000000000000000f00"

  let tokens <-
    fuzz.map(
      fuzz.list_between(
        {
          let asset_name <- fuzz.and_then(cardano.asset_name())
          let quantity <- fuzz.and_then(fuzz.int_at_least(1))
          fuzz.constant((policy_programmable_token, asset_name, quantity))
        },
        size + 1,
        size + 1,
      ),
    )

  fixture.some_transfer(tokens)
}

bench many_tokens((self, redeemer) via sample_many_tokens) {
  programmable_logic(self, redeemer)
}

/// --- Bench: inputs ------------------------------------------------------------------------------
///
/// A benchmark evaluating the impact of increasing the number of inputs
/// holding programmable tokens. For the sake of benchmarking the influence of
/// inputs, every input is identical and holds tokens coming from a single
/// policy.
/// For similar reasons, everything is sent back to a single output.
/// ------------------------------------------------------------------------------------------------
fn sample_many_inputs(
  size: Int,
) -> Fuzzer<(Transaction, ProgrammableLogicGlobalRedeemer)> {
  let policy_programmable_token: PolicyId =
    #"00000000000000000000000000000000000000000000000000000f00"

  let asset_name_programmable_token: AssetName = "FOO"

  let inputs <-
    fuzz.map(
      fuzz.list_between(
        fixture.any_input_with_programmable_tokens(
          [(policy_programmable_token, asset_name_programmable_token, 1)],
        ),
        size + 1,
        size + 1,
      ),
    )

  let (transaction, redeemer) =
    fixture.some_transfer(
      [(policy_programmable_token, asset_name_programmable_token, size + 1)],
    )

  (Transaction { ..transaction, inputs }, redeemer)
}

bench many_inputs((self, redeemer) via sample_many_inputs) {
  programmable_logic(self, redeemer)
}

/// --- Bench: policies ----------------------------------------------------------------------------
///
/// A benchmark evaluating the impact of increasing the number of unique
/// policies. For the sake of benchmarking the influence of policies alone, we
/// only use a single token per policy, and originate all tokens from a single
/// TxO; sent to a single output.
/// ------------------------------------------------------------------------------------------------
fn sample_many_policies(
  size: Int,
) -> Fuzzer<(Transaction, ProgrammableLogicGlobalRedeemer)> {
  let tokens: List<(PolicyId, AssetName, Int)> <-
    fuzz.map(
      fuzz.list_between(
        cardano.policy_id() |> fuzz.map(fn(policy) { (policy, "FOO", 42) }),
        size + 1,
        size + 1,
      ),
    )

  fixture.some_transfer(tokens)
}

bench many_policies((self, redeemer) via sample_many_policies) {
  programmable_logic(self, redeemer)
}

/// --- Bench: outputs ----------------------------------------------------------------------------
///
/// A benchmark showing the impact of increasing the number of (programmable)
/// outputs in a transfer action. All tokens are from the same policy, and come from a single TxO.
/// ------------------------------------------------------------------------------------------------
fn sample_many_outputs(
  size: Int,
) -> Fuzzer<(Transaction, ProgrammableLogicGlobalRedeemer)> {
  let policy_programmable_token: PolicyId =
    #"00000000000000000000000000000000000000000000000000000f00"

  let asset_name_programmable_token: AssetName = "FOO"

  let outputs: List<Output> =
    list.repeat(
      fixture.some_output_with_programmable_tokens(
        [(policy_programmable_token, asset_name_programmable_token, 1)],
      ),
      size + 1,
    )

  let (transaction, redeemer) =
    fixture.some_transfer(
      [(policy_programmable_token, asset_name_programmable_token, size + 1)],
    )

  fuzz.constant((Transaction { ..transaction, outputs }, redeemer))
}

bench many_outputs((self, redeemer) via sample_many_outputs) {
  programmable_logic(self, redeemer)
}
