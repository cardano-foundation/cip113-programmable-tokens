use aiken/collection/dict.{Dict}
use aiken/collection/list
use aiken/collection/pairs
// Programmable Logic Global Stake Validator
// This is the core CIP-0143 validator that coordinates all programmable token transfers
// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, Value, ada_policy_id, merge, zero}
use cardano/transaction.{Input, Output, Transaction}
use types.{
  ProgrammableLogicGlobalParams, ProgrammableLogicGlobalRedeemer, RegistryNode,
  RegistryProof, ThirdPartyAct, TokenDoesNotExist, TokenExists, TransferAct,
}
use utils.{
  bytearray_lt, elem_at, expect_inline_datum, expect_value_contains_v3,
  has_currency_symbol, is_script_invoked, is_signed_by,
}

/// Check if a credential is in the withdrawals list (script invocation check)
/// Optimized: Direct check without pre-mapping
fn withdrawal_has_cred(
  withdrawals: Pairs<Credential, Int>,
  cred: Credential,
) -> Bool {
  when withdrawals is {
    [] -> False
    [Pair(w_cred, _amount), ..rest] ->
      if w_cred == cred {
        True
      } else {
        withdrawal_has_cred(rest, cred)
      }
  }
}

validator programmable_logic_global(protocol_params_cs: PolicyId) {
  withdraw(
    redeemer: ProgrammableLogicGlobalRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_global validation"

    // Extract protocol parameters from reference inputs
    let protocol_params_ref <-
      get_protocol_params_ref(protocol_params_cs, self.reference_inputs)

    let protocol_params_utxo = protocol_params_ref.output
    let params_datum = expect_inline_datum(protocol_params_utxo)
    expect params: ProgrammableLogicGlobalParams = params_datum

    let prog_logic_cred = params.prog_logic_cred
    let registry_node_cs = params.registry_node_cs

    // Pass withdrawals directly - check invocation inline instead of pre-mapping
    when redeemer is {
      TransferAct { proofs } ->
        validate_transfer(
          self,
          prog_logic_cred,
          registry_node_cs,
          proofs,
          self.withdrawals,
        )

      ThirdPartyAct {
        registry_node_idx,
        input_idxs,
        outputs_start_idx,
        length_input_idxs,
      } ->
        validate_third_party(
          self,
          prog_logic_cred,
          registry_node_cs,
          registry_node_idx,
          input_idxs,
          outputs_start_idx,
          length_input_idxs,
          self.withdrawals,
        )
    }
  }

  else(_) {
    fail
  }
}

fn get_protocol_params_ref(
  protocol_params_cs: PolicyId,
  ref_inputs: List<Input>,
  return: fn(Input) -> result,
) -> result {
  when ref_inputs is {
    [] -> fail @"Protocol parameters reference input not found"
    [first_ref, ..rest_refs] ->
      if has_currency_symbol(first_ref.output.value, protocol_params_cs) {
        return(first_ref)
      } else {
        get_protocol_params_ref(protocol_params_cs, rest_refs, return)
      }
  }
}

/// Validate a transfer action
fn validate_transfer(
  tx: Transaction,
  prog_logic_cred: Credential,
  registry_node_cs: PolicyId,
  proofs: List<RegistryProof>,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  // Calculate the total value of programmable tokens being transferred
  // by summing all inputs from the programmable logic credential
  let total_prog_value = get_signed_prog_value(tx, prog_logic_cred)

  // Check transfer logic for each programmable token type and filter to only programmable tokens
  let validated_prog_value =
    check_transfer_and_compute_prog_value(
      total_prog_value,
      registry_node_cs,
      tx.reference_inputs,
      proofs,
      withdrawals,
    )

  let output_prog_value =
    list.foldl(
      tx.outputs,
      assets.zero,
      fn(output, acc) {
        if output.address.payment_credential == prog_logic_cred {
          expect Some(Inline(_stake_cred)) = output.address.stake_credential
          merge(acc, output.value)
        } else {
          acc
        }
      },
    )

  // The output must contain all the validated programmable tokens
  expect_value_contains_v3(output_prog_value, validated_prog_value)
  True
}

/// Validate a third party action (seizure, freeze, etc.) on multiple UTxOs
/// Migrated from Plutarch multi-seize PR #99
fn validate_third_party(
  tx: Transaction,
  prog_logic_cred: Credential,
  registry_node_cs: PolicyId,
  registry_node_idx: Int,
  input_idxs: List<Int>,
  outputs_start_idx: Int,
  length_input_idxs: Int,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  trace @"validate_third_party: processing multiple inputs"

  // Verify length parameter matches actual list length
  // expect list.length(input_idxs) == length_input_idxs
  // Get the registry node for this token policy
  let registry_ref_input = elem_at(tx.reference_inputs, registry_node_idx)
  let registry_datum = expect_inline_datum(registry_ref_input.output)
  expect registry_node: RegistryNode = registry_datum

  // Get the policy ID from the registry
  let policy_id = registry_node.key

  // Process each input-output pair
  // For each input at input_idxs[i], there should be a corresponding output at outputs_start_idx + i
  let input_size =
    list.indexed_foldr(
      input_idxs,
      0,
      fn(idx, input_idx, acc) {
        // Note: Input ordering is implicitly validated because:
        // 1. Currency symbols in Value are ordered lexicographically (Aiken's pairs)
        // 2. Proofs must match currency symbols in order via validate_single_cs (node.key == cs check)
        // 3. If proofs are out of order, the key validation will fail
        // Get the input being processed
        let input = elem_at(tx.inputs, input_idx)

        // Calculate corresponding output index
        let output_idx = outputs_start_idx + idx
        let output = elem_at(tx.outputs, output_idx)

        let expected_output_dict =
          assets.to_dict(input.output.value) |> dict.delete(policy_id)

        // // Filter the input value to only include tokens from this policy
        // let filtered_value = restricted_to(input.output.value, [policy_id])
        // // Expected output value is input value with policy tokens removed
        // let expected_output_value =
        //   merge(input.output.value, negate(filtered_value))
        // Must be from prog_logic_cred
        expect input.output.address.payment_credential == prog_logic_cred
        // Validate the output matches expectations:
        // - Same address
        // - Value with tokens removed
        // - Same datum
        expect output.address == input.output.address
        expect assets.to_dict(output.value) == expected_output_dict
        expect output.datum == input.output.datum
        // Prevent DDOS: must actually remove some tokens
        expect assets.to_dict(input.output.value) != expected_output_dict
        acc + 1
      },
    )

  expect input_size == length_input_idxs
  // Verify that ONLY the specified inputs from prog_logic_cred are consumed
  // Count how many inputs from prog_logic_cred are in the transaction
  let prog_input_count =
    list.count(
      tx.inputs,
      fn(input) { input.output.address.payment_credential == prog_logic_cred },
    )
  and {
    // Validate registry node is authentic
    has_currency_symbol(registry_ref_input.output.value, registry_node_cs),
    // The third party transfer logic script must be invoked
    withdrawal_has_cred(withdrawals, registry_node.third_party_transfer_logic_script),
    // matching_outputs,
    // Must match the number of inputs we're processing
    prog_input_count == length_input_idxs,
  }
}

fn get_signed_prog_value(tx: Transaction, prog_logic_cred: Credential) -> Value {
  // Optimized: Combine authorization check into single fold
  // Uses expect for fail-fast behavior instead of if-then-fail
  list.foldl(
    tx.inputs,
    assets.zero,
    fn(input, acc) {
      if input.output.address.payment_credential == prog_logic_cred {
        expect Some(Inline(stake_cred)) = input.output.address.stake_credential
        // Authorization check - fail immediately if not authorized
        let is_authorized =
          when stake_cred is {
            VerificationKey(pkh) -> is_signed_by(tx, pkh)
            Script(_hash) -> is_script_invoked(tx, stake_cred)
          }
        expect is_authorized
        merge(acc, input.output.value)
      } else {
        acc
      }
    },
  )
}

/// Check transfer logic for each currency symbol and filter to only programmable tokens
/// This function iterates through the value's currency symbols and validates each proof
fn check_transfer_and_compute_prog_value(
  value: Value,
  registry_node_cs: PolicyId,
  reference_inputs: List<Input>,
  proofs: List<RegistryProof>,
  withdrawals: Pairs<Credential, Int>,
) -> Value {
  let
    remaining_proofs,
    acc_value,
  <-
    do_check_transfer(
      value
        |> assets.to_dict
        |> dict.to_pairs
        |> pairs.delete_first(ada_policy_id),
      registry_node_cs,
      reference_inputs,
      withdrawals,
      proofs,
      zero,
    )
  expect [] == remaining_proofs
  acc_value
}

fn do_check_transfer(
  my_value: Pairs<PolicyId, Dict<ByteArray, Int>>,
  registry_node_cs: PolicyId,
  reference_inputs: List<Input>,
  withdrawals: Pairs<Credential, Int>,
  proofs: List<RegistryProof>,
  acc: Value,
  return: fn(List<RegistryProof>, Value) -> result,
) -> result {
  when my_value is {
    [] -> return(proofs, acc)
    [Pair(cs, tokens), ..rest] ->
      when proofs is {
        [] -> fail @"Not enough proofs for currency symbols"
        [proof, ..rest_proofs] -> {
          let validated =
            validate_single_cs(
              cs,
              proof,
              reference_inputs,
              registry_node_cs,
              withdrawals,
            )

          let new_acc =
            if validated {
              // Add this CS's tokens from the original value to the accumulator
              dict.foldl(
                tokens,
                acc,
                fn(name, amount, acc) { assets.add(acc, cs, name, amount) },
              )
            } else {
              // Not a programmable token, skip it
              acc
            }

          do_check_transfer(
            rest,
            registry_node_cs,
            reference_inputs,
            withdrawals,
            rest_proofs,
            new_acc,
            return,
          )
        }
      }
  }
}

/// Validate a single currency symbol against its proof
/// Returns true if the CS is a programmable token that passed validation,
/// false if it's not a programmable token (TokenDoesNotExist proof valid)
fn validate_single_cs(
  cs: PolicyId,
  proof: RegistryProof,
  reference_inputs: List<Input>,
  registry_node_cs: PolicyId,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  when proof is {
    TokenExists { node_idx } -> {
      // Get the registry node
      let node_input = elem_at(reference_inputs, node_idx)
      let node_datum = expect_inline_datum(node_input.output)
      expect node: RegistryNode = node_datum

      and {
        // Validate this is a legitimate registry node
        has_currency_symbol(node_input.output.value, registry_node_cs),
        // Validate the node's key matches the currency symbol
        node.key == cs,
        // Validate the transfer logic script is invoked
        withdrawal_has_cred(withdrawals, node.transfer_logic_script),
      }
    }

    TokenDoesNotExist { node_idx } -> {
      // Get the covering node
      let node_input = elem_at(reference_inputs, node_idx)
      let node_datum = expect_inline_datum(node_input.output)
      expect node: RegistryNode = node_datum

      // This is not a programmable token
      !and {
        // Validate this is a legitimate registry node
        has_currency_symbol(node_input.output.value, registry_node_cs),
        // Validate the node covers the currency symbol
        bytearray_lt(node.key, cs),
        bytearray_lt(cs, node.next),
      }
    }
  }
}
