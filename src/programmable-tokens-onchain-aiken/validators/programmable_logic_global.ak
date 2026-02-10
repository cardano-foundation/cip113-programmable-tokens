use aiken/builtin.{head_list, tail_list}
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
  RawValue, bytearray_lt, elem_at, expect_inline_datum, expect_key,
  expect_value_contains_v3, has_currency_symbol, is_script_invoked, is_signed_by,
  sum_output_values,
}

validator programmable_logic_global(protocol_params_cs: PolicyId) {
  withdraw(
    redeemer: ProgrammableLogicGlobalRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_global validation"

    // Extract protocol parameters from reference inputs
    let protocol_params_ref =
      get_protocol_params_ref(protocol_params_cs, self.reference_inputs)
    let protocol_params_utxo = protocol_params_ref.output
    let params_datum = expect_inline_datum(protocol_params_utxo)
    expect params: ProgrammableLogicGlobalParams = params_datum
    let prog_logic_cred = params.prog_logic_cred
    let registry_node_cs = params.registry_node_cs

    when redeemer is {
      TransferAct { proofs } ->
        validate_transfer(self, prog_logic_cred, registry_node_cs, proofs)
      ThirdPartyAct {
        registry_node_idx,
        input_idxs,
        outputs_start_idx,
        length_input_idxs,
      } -> {
        // FIXME: Inconsistent invoked scripts check
        //
        // This code used to be shared between the transfer and 3rd party
        // actions; we refactored transfered to use a pre-applied function
        // instead, but not this branch (yet).
        let invoked_scripts =
          list.map(
            self.withdrawals,
            fn(wdrl) {
              let Pair(cred, _amount) = wdrl
              cred
            },
          )

        validate_third_party(
          self,
          prog_logic_cred,
          registry_node_cs,
          registry_node_idx,
          input_idxs,
          outputs_start_idx,
          length_input_idxs,
          invoked_scripts,
        )
      }
    }
  }

  else(_) {
    fail
  }
}

pub fn get_protocol_params_ref(
  protocol_params_cs: PolicyId,
  ref_inputs: List<Input>,
) -> Input {
  let head = head_list(ref_inputs)
  if has_currency_symbol(head.output.value, protocol_params_cs) {
    head
  } else {
    get_protocol_params_ref(protocol_params_cs, tail_list(ref_inputs))
  }
}

/// Validate a transfer action
fn validate_transfer(
  tx: Transaction,
  prog_logic_cred: Credential,
  registry_node_cs: PolicyId,
  proofs: List<RegistryProof>,
) -> Bool {
  // Calculate the total value of programmable tokens being transferred
  // by summing all inputs from the programmable logic credential

  // Get all inputs from prog_logic_cred where the owner (stake credential) has signed
  // let prog_inputs = get_signed_prog_inputs(tx, prog_logic_cred)

  // Sum up the value from those inputs
  // let total_prog_value = sum_input_values(prog_inputs)
  let total_prog_value: RawValue = get_signed_prog_value(tx, prog_logic_cred)

  // Check transfer logic for each programmable token type and filter to only programmable tokens
  let validated_prog_value =
    check_transfer_and_compute_prog_value(
      tx,
      total_prog_value,
      registry_node_cs,
      proofs,
    )

  let output_prog_value: RawValue =
    sum_output_values(
      tx.outputs,
      fn(output, select, discard) {
        if output.address.payment_credential == prog_logic_cred {
          expect Some(Inline(_stake_cred)) = output.address.stake_credential
          select(output)
        } else {
          discard()
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
  invoked_scripts: List<Credential>,
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
        // TODO: improvements Check if the inputs are ordered
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

  // All conditions must pass or transaction fails
  // Validate registry node is authentic
  expect has_currency_symbol(registry_ref_input.output.value, registry_node_cs)
  // The third party transfer logic script must be invoked
  expect
    list.has(invoked_scripts, registry_node.third_party_transfer_logic_script)
  // Must match the number of inputs we're processing
  expect prog_input_count == length_input_idxs

  True
}

fn get_signed_prog_value(
  tx: Transaction,
  prog_logic_cred: Credential,
) -> RawValue {
  sum_output_values(
    tx.inputs,
    fn(input, select, discard) {
      let output = input.output
      if output.address.payment_credential == prog_logic_cred {
        expect Some(Inline(stake_cred)) = output.address.stake_credential
        when stake_cred is {
          VerificationKey(pkh) -> {
            expect is_signed_by(tx, pkh)
          }
          Script(_hash) -> {
            expect expect_key(tx.withdrawals, stake_cred)
          }
        }
        select(output)
      } else {
        discard()
      }
    },
  )
}

/// Get inputs from prog_logic_cred and verify ALL have proper authorization
/// This function enforces ownership by requiring that every input from prog_logic_cred
/// is authorized by its stake credential (signature or script invocation).
/// If ANY input lacks authorization, the transaction FAILS.
/// Sum values from a list of inputs
/// Check transfer logic for each currency symbol and filter to only programmable tokens
fn check_transfer_and_compute_prog_value(
  self: Transaction,
  value: RawValue,
  registry_node_cs: PolicyId,
  proofs: List<RegistryProof>,
) -> Value {
  let
    remaining_proofs,
    acc_value,
  <-
    do_check_transfer(
      self,
      value
        |> dict.to_pairs
        |> pairs.delete_first(ada_policy_id),
      registry_node_cs,
      proofs,
      zero,
    )
  expect [] == remaining_proofs
  acc_value
}

fn do_check_transfer(
  self: Transaction,
  my_value: Pairs<PolicyId, Dict<ByteArray, Int>>,
  registry_node_cs: PolicyId,
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
          let validated = validate_single_cs(self, cs, proof, registry_node_cs)

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
            self,
            rest,
            registry_node_cs,
            rest_proofs,
            new_acc,
            return,
          )
        }
      }
  }
}

/// Validate each currency symbol against proofs
fn validate_currency_symbols(
  self: Transaction,
  currency_symbols: List<PolicyId>,
  proofs: List<RegistryProof>,
  registry_node_cs: PolicyId,
  original_value: Value,
  acc_value: Value,
) -> Value {
  // By the looks of it this multy array traversing/foldin requires the currency_symbols and proofs to be
  // in the right order. Plutarch data structure makes it implicit to have policies in order.
  // In aiken seems to be enforced at pairs level where keys are ordered lexicographically.
  // Is this correct?

  when currency_symbols is {
    [] -> acc_value
    [cs, ..rest_cs] ->
      when proofs is {
        [] -> fail @"Not enough proofs for currency symbols"
        [proof, ..rest_proofs] -> {
          let validated = validate_single_cs(self, cs, proof, registry_node_cs)

          let new_acc =
            if validated {
              // Add this CS's tokens from the original value to the accumulator
              dict.foldl(
                assets.tokens(original_value, cs),
                acc_value,
                fn(name, amount, acc) { assets.add(acc, cs, name, amount) },
              )
            } else {
              // Not a programmable token, skip it
              acc_value
            }

          validate_currency_symbols(
            self,
            rest_cs,
            rest_proofs,
            registry_node_cs,
            original_value,
            new_acc,
          )
        }
      }
  }
}

/// Validate a single currency symbol against its proof
/// Returns True if the token IS a programmable token (TokenExists with valid proof)
/// Returns False if the token is NOT a programmable token (TokenDoesNotExist with valid proof)
/// FAILS the transaction if any proof is invalid
fn validate_single_cs(
  self: Transaction,
  cs: PolicyId,
  proof: RegistryProof,
  registry_node_cs: PolicyId,
) -> Bool {
  when proof is {
    TokenExists { node_idx } -> {
      // Get the registry node
      let node_input = elem_at(self.reference_inputs, node_idx)
      let node_datum = expect_inline_datum(node_input.output)
      expect node: RegistryNode = node_datum

      // All checks must pass or transaction fails
      // Validate this is a legitimate registry node
      expect has_currency_symbol(node_input.output.value, registry_node_cs)
      // Validate the node's key matches the currency symbol
      expect node.key == cs

      // Validate the transfer logic script is invoked
      expect_key(self.withdrawals, node.transfer_logic_script)
    }

    TokenDoesNotExist { node_idx } -> {
      // Get the covering node
      let node_input = elem_at(self.reference_inputs, node_idx)
      let node_datum = expect_inline_datum(node_input.output)
      expect node: RegistryNode = node_datum

      // All checks must pass to prove non-membership, or transaction fails
      // Validate this is a legitimate registry node
      expect has_currency_symbol(node_input.output.value, registry_node_cs)

      // Validate the node covers the currency symbol (nodeKey < cs < nodeNext)
      expect bytearray_lt(node.key, cs)
      expect bytearray_lt(cs, node.next)

      // This is NOT a programmable token (proof is valid)
      False
    }
  }
}
