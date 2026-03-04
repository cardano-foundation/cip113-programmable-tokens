//// End-to-end tests / benchmarks for programmable logic base+global validators

use aiken/collection/list
use aiken/fuzz
use cardano/assets.{AssetName, PolicyId}
use cardano/fuzz as cardano
use cardano/transaction.{Output, Transaction}
use programmable_logic/fixture
use programmable_logic_base
use programmable_logic_global
use types.{ProgrammableLogicGlobalRedeemer, TokenExists, TransferAct}

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

/// --- Plutarch baseline --------------------------------------------------------------------------
///
/// Replicate a Preview transaction based on the Plutarch version of the
/// programmable logic validators. This transaction has been used as a benchmark
/// for optimisation and improvements over the Aiken version.
///
/// Characteristics:
/// - 2 inputs: one script-locked, one for fuel
/// - 3 outputs: two with programmable tokens, and one for change
/// - one programmable token kind (i.e. two nodes from the registry referenced)
/// - transfer logic is script-based, provided as withdrawal
///
/// Source: https://preview.cexplorer.io/tx/d29ce2a9f79a70a91d83a40e0e1cf346ab94979b6f0ba001de8a89895aa518df?tab=contracts
/// ------------------------------------------------------------------------------------------------
const fixture_plutarch_baseline: Transaction = {
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
      withdrawals: fixture.withdrawals,
    }
  }

/// Corresponding redeemer with a single proof of a token in the registry,
/// located at position #2 in reference inputs
const fixture_redeemer_plutarch_baseline: ProgrammableLogicGlobalRedeemer =
  TransferAct { proofs: [TokenExists { node_idx: 2 }], mint_proofs: [] }

test plutarch_baseline() {
  programmable_logic(
    fixture_plutarch_baseline,
    fixture_redeemer_plutarch_baseline,
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

  fixture.some_transaction(tokens)
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
    fixture.some_transaction(
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

  fixture.some_transaction(tokens)
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
    fixture.some_transaction(
      [(policy_programmable_token, asset_name_programmable_token, size + 1)],
    )

  fuzz.constant((Transaction { ..transaction, outputs }, redeemer))
}

bench many_outputs((self, redeemer) via sample_many_outputs) {
  programmable_logic(self, redeemer)
}
