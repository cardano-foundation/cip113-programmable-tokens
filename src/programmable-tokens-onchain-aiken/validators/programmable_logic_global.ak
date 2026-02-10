//// Programmable Logic Global Stake Validator
//// This is the core CIP-0143 validator that coordinates all programmable token transfers
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use aiken/builtin.{head_list, tail_list, un_constr_data, unconstr_fields}
use aiken/collection/dict.{Dict}
use aiken/collection/dict/strategy as dict_strategy
use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId, Value, ada_policy_id, merge, zero}
use cardano/transaction.{Datum, InlineDatum, Input, Output, Transaction}
use types.{
  ProgrammableLogicGlobalParams, ProgrammableLogicGlobalRedeemer, RegistryNode,
  RegistryProof, ThirdPartyAct, TokenDoesNotExist, TokenExists, TransferAct,
}
use utils.{
  RawValue, bytearray_lt, elem_at, expect_inline_datum, has_currency_symbol,
  has_key, has_signatory, sum_output_values,
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
    let
      registry_node_cs,
      prog_logic_cred,
    <- expect_programmable_logic_params(protocol_params_ref.output.datum)

    when redeemer is {
      TransferAct { proofs } ->
        validate_transfer(self, prog_logic_cred, registry_node_cs, proofs)
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
        )
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
  self: Transaction,
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
  let total_prog_value: RawValue = get_signed_prog_value(self, prog_logic_cred)

  // Check transfer logic for each programmable token type and filter to only programmable tokens
  let validated_prog_value =
    check_transfer_and_compute_prog_value(
      total_prog_value,
      proofs,
      validate_single_cs(self, _, _, registry_node_cs),
    )

  let output_prog_value: RawValue =
    sum_output_values(
      self.outputs,
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
  // TODO: Check whether we can strengthen output requirement on prog tokens.
  //
  // Right now, the smart contract checks for inclusion of the validated tokens
  // in outputs. Although, outputs are also already filtered by programmable
  // logic credentials. So it seems to me that we could require that the
  // filtered output value *exactly* matches the validated inputs' one, modulo
  // lovelaces.
  //
  // The motivation: checking for exact match is MUCH faster.
  //
  // The cons: it doesn't allow one to add non-validated programmable tokens to
  // the outputs, yet I fail to see when this can happen apart from when
  // issuing new tokens (in which case, it would suffice to add the minting
  // quantities to the 'input' value...).
  //
  // So, TL; DR; I believe this can be replaced with:
  //
  //   utils.match_assets(validated_prog_value, output_prog_value)
  //
  // But I need more familiarity with the desired specs to really confirm that.
  //
  // == Pre-condition ==
  // The pre-condition of 'value_contains' is guaranteed here since both pairs
  // are coming from 'Dict', thus guaranteeing key uniqueness and ordering.
  dict.to_pairs(output_prog_value)
    |> utils.value_contains(dict.to_pairs(validated_prog_value))
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
    has_key(tx.withdrawals, registry_node.third_party_transfer_logic_script)
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
            expect has_signatory(tx.extra_signatories, pkh)
          }
          Script(_hash) -> {
            expect has_key(tx.withdrawals, stake_cred)
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
  value: RawValue,
  proofs: List<RegistryProof>,
  check_policy: fn(PolicyId, RegistryProof) -> Bool,
) -> RawValue {
  let assets = tail_list(dict.to_pairs(value))

  let
    remaining_proofs,
    acc_value,
  <- do_check_transfer(assets, proofs, check_policy, dict.empty)

  expect [] == remaining_proofs

  acc_value
}

fn do_check_transfer(
  assets: Pairs<PolicyId, Dict<AssetName, Int>>,
  proofs: List<RegistryProof>,
  check_policy: fn(PolicyId, RegistryProof) -> Bool,
  acc: RawValue,
  return: fn(List<RegistryProof>, RawValue) -> result,
) -> result {
  when assets is {
    [] -> return(proofs, acc)
    [Pair(cs, tokens), ..rest] -> {
      let proof = head_list(proofs)

      // TODO: Failing-fast when finding non-validated programmable tokens?
      //
      // This seems a little suspicious but I do not want to alter the logic
      // without diving more into the spec and what's the expected behaviour
      // here.
      //
      // What is "suspicious" here is that we are already iterating over an
      // asset list that was obtained from looping over the inputs, and
      // selecting only tokens that were locked by the programmable logic
      // script, and with a matching transfer logic as stake script.
      //
      // Couldn't we simply fail if any such token found in inputs appear to be
      // unauthenticated? It would save quite some cost, as we are otherwise
      // forced to re-create a whole new value object, which in the nominal
      // case end up being the same as the original object.
      let new_acc =
        if check_policy(cs, proof) {
          // Validated programmable token, keep it.
          dict.insert(acc, cs, tokens)
        } else {
          // Not a programmable token, skip it
          acc
        }

      do_check_transfer(rest, tail_list(proofs), check_policy, new_acc, return)
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
  expect node_idx: Int = head_list(unconstr_fields(proof))

  // Get the registry node details
  let node_input = elem_at(self.reference_inputs, node_idx)
  let
    key,
    next,
    transfer_logic_script,
  <- expect_registry_node(node_input.output.datum)

  // Validate this is a legitimate registry node
  expect has_currency_symbol(node_input.output.value, registry_node_cs)

  when proof is {
    TokenExists { .. } -> {
      // Validate the node's key matches the currency symbol
      expect key == cs
      // Validate the transfer logic script is invoked
      has_key(self.withdrawals, transfer_logic_script)
    }

    TokenDoesNotExist { .. } -> {
      // Validate the node covers the currency symbol (nodeKey < cs < nodeNext)
      expect bytearray_lt(key, cs)
      expect bytearray_lt(cs, next)
      // This is NOT a programmable token (proof is valid)
      False
    }
  }
}

/// Extract useful information from an inlined 'RegistryNode' datum. Note that
/// we need not to 'validate' the full shape of the datum here, because we do not
/// produce it. We're only consuming it, and its well-formedness is guaranteed by the
/// linked list contract when producing the datum.
///
/// This even makes the contract more 'interoperable', as the linked-list datum
/// can change in addititive manner without invalidating this contract.
fn expect_registry_node(
  datum: Datum,
  return: fn(ByteArray, ByteArray, Credential) -> result,
) -> result {
  expect InlineDatum(inline_datum) = datum
  let fields = unconstr_fields(inline_datum)
  expect key: ByteArray = head_list(fields)
  let fields = tail_list(fields)
  expect next: ByteArray = head_list(fields)
  let fields = tail_list(fields)
  expect transfer_logic_script: Credential = head_list(fields)
  return(key, next, transfer_logic_script)
}

/// See note on 'expect_registry_node'.
fn expect_programmable_logic_params(
  datum: Datum,
  return: fn(PolicyId, Credential) -> result,
) -> result {
  expect InlineDatum(inline_datum) = datum
  let fields = unconstr_fields(inline_datum)
  expect registry_node_cs: PolicyId = head_list(fields)
  let fields = tail_list(fields)
  expect prog_logic_cred: Credential = head_list(fields)
  return(registry_node_cs, prog_logic_cred)
}
