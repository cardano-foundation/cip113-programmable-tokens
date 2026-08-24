//// End-to-end tests / benchmarks for the programmable-logic validators.
////
//// Validator split (PR #110) — before/after record. The former
//// `programmable_logic_global` coordinator dispatched transfer / third-party
//// / unfracking itself; now `programmable_logic_base` dispatches straight to
//// one of three standalone withdraw-0 validators (`transfer`, `third_party`,
//// `unfracking`). Compiled reference-script sizes, measured with
//// `aiken build` on this branch vs the pre-split base:
////
////   validator                 before   after    delta
////   transfer (was PLG)          3163    2177     -986   (-31.2%)
////   PLB (base)                   496     868     +372   (3-arm dispatch)
////   third_party (NEW)              0    1806    +1806
////   unfracking                  1832    1832       +0
////   issuance_mint               1925    2063     +138
////
//// Reference scripts are attached once and paid for (as a size-proportional
//// fee) by EVERY transaction that references them, so what matters is the
//// per-transaction reference-script footprint, which is now exactly
//// PLB + ONE delegate for every transaction kind:
////
////   * transfer   tx (PLB + transfer) ..... 3659 -> 3045 B = -614 B  every transfer
////   * seize      tx (PLB + third_party) .. 3659 -> 2674 B = -985 B  every seize
////   * unfracking tx (PLB + unfracking) ... 5491 -> 2700 B = -2791 B every unfracking
////
//// The transfer hot path shrinks because the transfer validator no longer
//// carries the seize invariants nor the unfracking gate; the seize and
//// unfracking paths shrink MORE because they no longer load the transfer
//// script at all — each loads only PLB + its own script.
////
//// Replace double datum unwrapping — record (2026-08-24).
//// `programmable_logic_base` used to unwrap its redeemer twice: once for
//// `params_idx`, once again to pick the delegate credential. It now decodes
//// once and hoists the whole shared body — params lookup, withdrawal
//// resolution, comparison — into one function taking the differing field
//// accessor as an argument, leaving each arm a one-line call. Net: 868 B ->
//// 829 B and -1.22M cpu per invocation, so cheaper on BOTH axes — no
//// size-versus-cpu trade to weigh. (The validator runs once per programmable
//// input; these harnesses call `spend` once, so cpu figures are per
//// invocation and the ledger multiplies them.)
////
//// Measured and rejected: selecting the credential by an integer tag (the tag
//// comparison outweighed the decode it removed); inlining the withdrawal
//// lookup per arm instead of sharing it (+25 B for no cpu gain). Does not
//// compile: returning the field accessor inside a TUPLE — tuple inhabitants
//// must be serialisable to Data. Passing a function as an argument is fine,
//// which is what makes the shipped shape possible.
////
//// Execution (CPU/mem) on the composed happy paths below is roughly neutral:
//// the PLB spend gains a 3-arm dispatch (a few M cpu at withdrawal-index 0,
//// where the old `has_key_or_fail` scan also stopped at the first entry);
//// the unfracking path additionally drops a whole validator run (the former
//// PLG gate). The benches here all witness `wdrl_idx = 0`, so they do NOT
//// measure the off-first-position case; `wdrl_idx_cost.test.ak` does, at
//// widths 1-16 and positions 0-15. Note `list.expect_at` is O(`wdrl_idx`)
//// (one cell drop per step), not O(1) — what the witness removes is the
//// credential COMPARISON at every entry the old scan walked past. The
//// headline win is the reference-script SIZE reduction, paid on every tx.

use aiken/collection/list
use aiken/fuzz
use aiken/primitive/bytearray
use cardano/address.{VerificationKey}
use cardano/assets.{AssetName, PolicyId}
use cardano/fuzz as cardano
use cardano/transaction.{Input, Output, OutputReference, Transaction}
use programmable_logic/fixture
use programmable_logic_base
use third_party
use transfer
use types.{
  SpendViaThirdParty, SpendViaTransfer, SpendViaUnfracking, ThirdPartyRedeemer,
  TokenDoesNotExist, TokenExists, TransferRedeemer, UnfrackingRedeemer,
}
use unfracking

fn programmable_logic(self: Transaction, redeemer: TransferRedeemer) -> Bool {
  // Include both the base and global in the benchmark
  and {
    programmable_logic_base.programmable_logic_base.spend(
      fixture.policy_protocol_params,
      None,
      SpendViaTransfer { params_idx: 0, wdrl_idx: 0 },
      Void,
      self,
    ),
    transfer.transfer.withdraw(
      fixture.policy_protocol_params,
      redeemer,
      fixture.credential_validator_transfer,
      self,
    ),
  }
}

/// Third-party (seize) composition: the base spend dispatches via
/// SpendViaThirdParty to the standalone third_party validator — the transfer
/// validator is not invoked at all on a third-party transaction.
fn third_party_logic(self: Transaction, redeemer: ThirdPartyRedeemer) -> Bool {
  and {
    programmable_logic_base.programmable_logic_base.spend(
      fixture.policy_protocol_params,
      None,
      SpendViaThirdParty { params_idx: 0, wdrl_idx: 0 },
      Void,
      self,
    ),
    third_party.third_party.withdraw(
      fixture.policy_protocol_params,
      redeemer,
      fixture.credential_validator_third_party,
      self,
    ),
  }
}

/// --- Baseline 1 (3rd party) ---------------------------------------------------------------
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
const fixture_baseline_3rd_party_1: Transaction = {
    let policy_programmable_token: PolicyId = #"76658c4afd597ba7524f85bf32ac59d9e58856593a2e8399326f853a"

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

const fixture_redeemer_baseline_3rd_party_1: ThirdPartyRedeemer =
  ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 2,
  }

test baseline_3rd_party_1() {
  third_party_logic(
    fixture_baseline_3rd_party_1,
    fixture_redeemer_baseline_3rd_party_1,
  )
}

/// --- Baseline 2 (3rd party) -------------------------------------------------------------
///
/// A slightly more interesting scenario than the baseline #1, which mostly adds "noise":
///
/// - inputs contain other tokens
/// - seizing from multiple inputs
/// - one partial and one total seizing
/// - burning tokens
///
const fixture_baseline_3rd_party_2: Transaction = {
    let policy_programmable_token: PolicyId = #"76658c4afd597ba7524f85bf32ac59d9e58856593a2e8399326f853a"

    let asset_name_programmable_token: AssetName = "tUSDT"

    let other_prog_tokens_1 = (
      #"00000000000000000000000000000000000000000000000000000000",
      "foo",
      14,
    )

    let other_prog_tokens_2 = (
      #"11111111111111111111111111111111111111111111111111111111",
      "bar",
      42,
    )

    let other_prog_tokens_3 = (
      #"99999999999999999999999999999999999999999999999999999999",
      "baz",
      1,
    )

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

const fixture_redeemer_baseline_3rd_party_2: ThirdPartyRedeemer =
  ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 2,
  }

test baseline_3rd_party_2() {
  third_party_logic(
    fixture_baseline_3rd_party_2,
    fixture_redeemer_baseline_3rd_party_2,
  )
}

/// --- Baseline 3 (3rd party) -------------------------------------------------------------
///
/// A scenario with MANY seized programmable inputs
const length_baseline_3rd_party_3: Int = 150

const fixture_baseline_3rd_party_3: Transaction = {
    let policy_programmable_token = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    let asset_name_programmable_token = "programmable"

    let inputs = list.range(0, length_baseline_3rd_party_3 - 1)
      |> list.map(
          fn(output_index) {
            Input {
              output_reference: OutputReference {
                transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
                output_index,
              },
              output: fixture.some_input_with_programmable_tokens(
                [(policy_programmable_token, asset_name_programmable_token, 1)],
                bytearray.from_int_big_endian(output_index, 0),
              ).output,
            }
          },
        )

    let outputs = list.repeat(
      fixture.some_output_with_programmable_tokens([]),
      length_baseline_3rd_party_3,
    )

    Transaction {
      ..transaction.placeholder,
      inputs,
      // An input holding programmable tokens being spent.
      outputs: list.concat(
        outputs,
        [
          fixture.some_output_with_seized_tokens(
            [
              (
                policy_programmable_token,
                asset_name_programmable_token,
                length_baseline_3rd_party_3,
              ),
            ],
          ),
        ],
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

const fixture_redeemer_baseline_3rd_party_3: ThirdPartyRedeemer =
  ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

test baseline_3rd_party_3() {
  third_party_logic(
    fixture_baseline_3rd_party_3,
    fixture_redeemer_baseline_3rd_party_3,
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
    let policy_programmable_token: PolicyId = #"00000000000000000000000000000000000000000000000000000f00"

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
const fixture_redeemer_plutarch_baseline_transfer: TransferRedeemer =
  TransferRedeemer { params_idx: 0, proofs: [TokenExists { node_idx: 1 }] }

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
    let policy_programmable_token_1: PolicyId = #"00000000000000000000000000000000000000000000000000000f00"

    let asset_name_programmable_token_1: AssetName = "FOO"

    let policy_programmable_token_2: PolicyId = #"00000000000000000000000000000000000000000000000000000ba5"

    let asset_name_programmable_token_2: AssetName = "BAR"

    let policy_unexisting_token: PolicyId = #"000000000000000000000000000000000000000000000000aaaaffff"

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
const fixture_redeemer_plutarch_baseline_transfer_2: TransferRedeemer =
  TransferRedeemer {
    params_idx: 0,
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

/// --- Plutarch baseline 3 (transfer) ---------------------------------------------------------------
///
/// Another baseline mimicking the 'globalTransferMixedManyCtx' from Plutarch's reference implementation
/// ------------------------------------------------------------------------------------------------
const fixture_plutarch_baseline_transfer_3: Transaction = {
    let signer_vkh = #"01010101010101010101010101010101010101010101010101010101"

    let policy_unexisting_token_1 = #"1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a"
    let policy_unexisting_token_2 = #"1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e"

    let policy_programmable_token_1 = #"1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b"
    let policy_programmable_token_2 = #"1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c"
    let policy_programmable_token_3 = #"1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d"

    Transaction {
      ..transaction.placeholder,
      extra_signatories: [signer_vkh],
      inputs: [
        fixture.some_input_with_programmable_tokens_with(
          VerificationKey(signer_vkh),
          [
            (policy_unexisting_token_1, "np1", 4),
            (policy_programmable_token_1, "0c", 5),
            (policy_programmable_token_2, "1c", 7),
            (policy_programmable_token_3, "2c", 9),
            (policy_unexisting_token_2, "np2", 6),
          ],
          "programmable tokens input",
        ),
      ],
      outputs: [
        fixture.some_output_with_programmable_tokens_with(
          VerificationKey(signer_vkh),
          [
            (policy_programmable_token_1, "0c", 5),
            (policy_programmable_token_2, "1c", 7),
            (policy_programmable_token_3, "2c", 9),
          ],
        ),
        Output {
          ..fixture.some_output_change("change"),
          value: fixture.min_ada_value
            |> assets.add(policy_unexisting_token_1, "np1", 4)
            |> assets.add(policy_unexisting_token_2, "np2", 6),
        },
      ],
      reference_inputs: [
        // Reference inputs with the protocol params. Identified by a specific NFT.
        // Holds a ProtocolParams inline datum with configuration.
        fixture.some_reference_input_protocol_params(
          fixture.protocol_params,
          "protocol params",
        ),
        fixture.some_reference_input_tokens_registry_node(
          #"",
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "bb00",
        ),
        fixture.some_reference_input_tokens_registry_node(
          policy_programmable_token_1,
          policy_programmable_token_2,
          "bb10",
        ),
        fixture.some_reference_input_tokens_registry_node(
          policy_programmable_token_2,
          policy_programmable_token_3,
          "bb11",
        ),
        fixture.some_reference_input_tokens_registry_node(
          policy_programmable_token_3,
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          "bb12",
        ),
      ],
      withdrawals: [Pair(fixture.credential_transfer_logic, 0)],
    }
  }

const fixture_redeemer_plutarch_baseline_transfer_3: TransferRedeemer =
  TransferRedeemer {
    params_idx: 0,
    proofs: [
      TokenDoesNotExist { node_idx: 1 },
      TokenExists { node_idx: 2 },
      TokenExists { node_idx: 3 },
      TokenExists { node_idx: 4 },
      TokenDoesNotExist { node_idx: 1 },
    ],
  }

test plutarch_baseline_transfer_3() {
  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    fixture_redeemer_plutarch_baseline_transfer_3,
    fixture.credential_validator_transfer,
    fixture_plutarch_baseline_transfer_3,
  )
}

/// --- Bench: tokens ------------------------------------------------------------------------------
///
/// A benchmark evaluating the impact of increasing the number of tokens from a
/// same policy in a transfer. All tokens are located at a single TxO, and
/// transfered to a single address.
/// ------------------------------------------------------------------------------------------------
fn sample_many_tokens(size: Int) -> Fuzzer<(Transaction, TransferRedeemer)> {
  let policy_programmable_token: PolicyId = #"00000000000000000000000000000000000000000000000000000f00"

  let tokens <- fuzz.map(
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
fn sample_many_inputs(size: Int) -> Fuzzer<(Transaction, TransferRedeemer)> {
  let policy_programmable_token: PolicyId = #"00000000000000000000000000000000000000000000000000000f00"

  let asset_name_programmable_token: AssetName = "FOO"

  let inputs <- fuzz.map(
    fuzz.list_between(
      fixture.any_input_with_programmable_tokens(
        fixture.credential_transfer_logic,
        [(policy_programmable_token, asset_name_programmable_token, 1)],
      ),
      size + 1,
      size + 1,
    ),
  )

  let (transaction, redeemer) = fixture.some_transfer(
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
fn sample_many_policies(size: Int) -> Fuzzer<(Transaction, TransferRedeemer)> {
  let tokens: List<(PolicyId, AssetName, Int)> <- fuzz.map(
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
fn sample_many_outputs(size: Int) -> Fuzzer<(Transaction, TransferRedeemer)> {
  let policy_programmable_token: PolicyId = #"00000000000000000000000000000000000000000000000000000f00"

  let asset_name_programmable_token: AssetName = "FOO"

  let outputs: List<Output> = list.repeat(
    fixture.some_output_with_programmable_tokens(
      [(policy_programmable_token, asset_name_programmable_token, 1)],
    ),
    size + 1,
  )

  let (transaction, redeemer) = fixture.some_transfer(
    [(policy_programmable_token, asset_name_programmable_token, size + 1)],
  )

  fuzz.constant((Transaction { ..transaction, outputs }, redeemer))
}

bench many_outputs((self, redeemer) via sample_many_outputs) {
  programmable_logic(self, redeemer)
}

/// Unfracking composition (Finding 17): an unfracking tx runs base.spend
/// (per PLB input) dispatching via SpendViaUnfracking, AND the standalone
/// unfracking.withdraw where the invariants live — the transfer validator is
/// not part of it. Benching both accounts for the full execution cost of the
/// action.
fn programmable_logic_unfracking(
  self: Transaction,
  unfracking_redeemer: UnfrackingRedeemer,
) -> Bool {
  and {
    programmable_logic_base.programmable_logic_base.spend(
      fixture.policy_protocol_params,
      None,
      SpendViaUnfracking { params_idx: 0, wdrl_idx: 0 },
      Void,
      self,
    ),
    unfracking.unfracking.withdraw(
      fixture.policy_protocol_params,
      unfracking_redeemer,
      fixture.credential_validator_unfracking,
      self,
    ),
  }
}

/// --- Bench: unfracking baseline (v2) --------------------------------------------------------------
///
/// The canonical unfracking case under the v2 single-policy model: a
/// fracked PLB UTxO holding two policies is acted on for policy A — the
/// paired continuing output keeps policy B untouched while all of A
/// regroups into its own UTxO at the same owner address. The acted
/// policy's registry hook withdraw-0 is part of the composition.
///
/// Calls the `programmable_logic_unfracking` wrapper so the base.spend
/// dispatch cost is also accounted for.
/// ------------------------------------------------------------------------------------------------
test unfracking_baseline_two_policies() {
  let policy_a: PolicyId = #"00000000000000000000000000000000000000000000000000000a00"
  let policy_b: PolicyId = #"00000000000000000000000000000000000000000000000000000b00"

  let (self, unfracking_redeemer) = fixture.some_unfracking(
    policy_a,
    [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
    [(policy_b, "BAR", 100)],
    [(policy_a, "FOO", 100)],
  )

  programmable_logic_unfracking(self, unfracking_redeemer)
}

/// --- Bench: unfracking — policies axis (v2) -------------------------------------------------------
///
/// Scales the number of NON-acted policies co-resident in the fracked
/// UTxO. The action extracts the single acted policy; every other
/// policy must be byte-identical across the pair, so the per-pair
/// comparison cost is linear in the co-resident policy count (the
/// before/after halves of the ada-less split).
/// ------------------------------------------------------------------------------------------------
fn sample_unfracking_many_policies(
  size: Int,
) -> Fuzzer<(Transaction, UnfrackingRedeemer)> {
  let acted_policy: PolicyId = #"00000000000000000000000000000000000000000000000000000a00"

  let other_tokens: List<(PolicyId, AssetName, Int)> <- fuzz.map(
    fuzz.list_between(
      cardano.policy_id() |> fuzz.map(fn(policy) { (policy, "FOO", 42) }),
      size + 1,
      size + 1,
    ),
  )

  fixture.some_unfracking(
    acted_policy,
    [(acted_policy, "ACT", 100), ..other_tokens],
    other_tokens,
    [(acted_policy, "ACT", 100)],
  )
}

bench unfracking_many_policies(
  (self, unfracking_redeemer) via sample_unfracking_many_policies,
) {
  programmable_logic_unfracking(self, unfracking_redeemer)
}
