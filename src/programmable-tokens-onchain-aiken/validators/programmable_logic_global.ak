//// Programmable Logic Global Stake Validator
//// This is the core CIP-0143 validator that coordinates all programmable token transfers
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use aiken/builtin.{head_list, tail_list, unconstr_fields}
use aiken/collection/dict.{Dict}
use aiken/collection/dict/strategy as dict_strategy
use aiken/collection/list
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Datum, InlineDatum, Input, Output, Transaction}
use types.{
  ProgrammableLogicGlobalRedeemer, RegistryNode, RegistryProof, ThirdPartyAct,
  TokenDoesNotExist, TokenExists, TransferAct,
}
use utils.{
  RawValue, bytearray_lt, elem_at, expect_inline_datum, has_currency_symbol,
  has_key, has_signatory, merge_raw_values, sum_output_values,
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
      TransferAct { proofs, mint_proofs } ->
        validate_transfer(
          self,
          prog_logic_cred,
          registry_node_cs,
          proofs,
          mint_proofs,
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
  mint_proofs: List<RegistryProof>,
) -> Bool {
  // Sum all inputs from the programmable logic credential
  let total_prog_value: RawValue = get_signed_prog_value(self, prog_logic_cred)

  // Check transfer logic for each programmable token type and filter to only programmable tokens
  let validated_prog_value =
    check_transfer_and_compute_prog_value(
      total_prog_value,
      proofs,
      validate_single_cs(self, _, _, registry_node_cs),
    )

  // Always validate minted/burned programmable tokens against the directory.
  // Gate on tx.mint content (not mint_proofs), matching Plutarch behavior.
  // If self.mint is empty and mint_proofs is empty: no-op (returns dict.empty, merge is identity).
  // If self.mint is non-empty but mint_proofs is empty: crashes on head_list([]) → tx rejected.
  // If self.mint is empty but mint_proofs is non-empty: remaining_proofs != [] → tx rejected.
  let mint_dict: RawValue = assets.to_dict(self.mint)
  let validated_mint_value =
    check_mint_and_compute_prog_value(
      mint_dict,
      mint_proofs,
      validate_single_cs(self, _, _, registry_node_cs),
    )
  let expected_value =
    merge_raw_values(validated_prog_value, validated_mint_value)

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

  // The output must contain all the expected programmable tokens (inputs + mints)
  // Pre-condition of 'value_contains' is guaranteed since both pairs
  // come from 'Dict', thus guaranteeing key uniqueness and ordering.
  dict.to_pairs(output_prog_value)
    |> utils.value_contains(dict.to_pairs(expected_value))
}

/// Validate a third party action (seizure, freeze, etc.) on multiple UTxOs.
///
/// Implements delta tracking (matching Plutarch's checkBalanceInvariant):
/// 1. For each input/output pair: verify non-policy assets are unchanged,
///    accumulate the seized policy's input tokens.
/// 2. Sum all outputs at prog_logic_cred for the seized policy.
/// 3. Verify: total output tokens >= total input tokens (balance invariant).
///
/// This ensures seized tokens stay within prog_logic_cred and enables
/// partial seizure (seize some tokens, leave others with the owner).
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

  // Get the registry node for this token policy
  let registry_ref_input = elem_at(tx.reference_inputs, registry_node_idx)
  let registry_datum = expect_inline_datum(registry_ref_input.output)
  expect registry_node: RegistryNode = registry_datum

  // Get the policy ID from the registry
  let policy_id = registry_node.key

  // Process each input-output pair:
  // - Verify non-policy assets are unchanged
  // - Verify address and datum preserved
  // - Accumulate the seized policy's input tokens for the balance invariant
  let (_last_index, input_size, total_input_policy_tokens) =
    list.indexed_foldr(
      input_idxs,
      (-1, 0, dict.empty),
      fn(idx, input_idx, (prev_idx, acc, input_tokens_acc)) {
        // Ensures inputs are sorted with no duplicates
        expect prev_idx > input_idx || prev_idx == -1

        let input = elem_at(tx.inputs, input_idx)
        let output_idx = outputs_start_idx + idx
        let output = elem_at(tx.outputs, output_idx)

        let input_dict = assets.to_dict(input.output.value)
        let output_dict = assets.to_dict(output.value)

        // Must be from prog_logic_cred
        expect input.output.address.payment_credential == prog_logic_cred
        // Output must preserve address and datum
        expect output.address == input.output.address
        expect output.datum == input.output.datum

        // Non-policy assets must be exactly equal (only the seized policy can change)
        expect
          dict.delete(input_dict, policy_id) == dict.delete(
            output_dict,
            policy_id,
          )

        // Policy tokens must actually change (prevent DDOS with no-op seizures)
        let input_policy_tokens = get_policy_tokens(input_dict, policy_id)
        let output_policy_tokens = get_policy_tokens(output_dict, policy_id)
        expect input_policy_tokens != output_policy_tokens

        // Accumulate input policy tokens for balance invariant
        let new_tokens_acc = union_tokens(input_tokens_acc, input_policy_tokens)

        (input_idx, acc + 1, new_tokens_acc)
      },
    )

  // Verify length parameter matches actual list length
  expect input_size == length_input_idxs

  // Validate registry node is authentic
  expect has_currency_symbol(registry_ref_input.output.value, registry_node_cs)
  // The third party transfer logic script must be invoked
  expect
    has_key(tx.withdrawals, registry_node.third_party_transfer_logic_script)

  // Verify that ONLY the specified inputs from prog_logic_cred are consumed
  let prog_input_count =
    list.count(
      tx.inputs,
      fn(input) { input.output.address.payment_credential == prog_logic_cred },
    )
  expect prog_input_count == length_input_idxs

  // Balance invariant: total output policy tokens at prog_logic_cred
  // must be >= total input policy tokens.
  // This ensures seized tokens stay within the programmable system.
  let total_output_policy_tokens =
    sum_policy_tokens_at_cred(tx.outputs, prog_logic_cred, policy_id)

  // Check: for each token name, output >= input
  check_balance_invariant(
    dict.to_pairs(total_output_policy_tokens),
    dict.to_pairs(total_input_policy_tokens),
  )
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

/// Validate minted/burned programmable tokens and filter to only programmable tokens.
/// Unlike check_transfer_and_compute_prog_value, this does NOT skip ADA
/// (mint values never contain ADA).
fn check_mint_and_compute_prog_value(
  mint_value: RawValue,
  mint_proofs: List<RegistryProof>,
  check_policy: fn(PolicyId, RegistryProof) -> Bool,
) -> RawValue {
  let mint_assets = dict.to_pairs(mint_value)

  let
    remaining_proofs,
    acc_value,
  <- do_check_transfer(mint_assets, mint_proofs, check_policy, dict.empty)

  expect [] == remaining_proofs

  acc_value
}

/// Extract tokens for a specific policy from a value dict.
/// Returns dict.empty if the policy is not present.
fn get_policy_tokens(
  value_dict: RawValue,
  policy: PolicyId,
) -> Dict<AssetName, Int> {
  when dict.get(value_dict, policy) is {
    Some(tokens) -> tokens
    None -> dict.empty
  }
}

/// Merge two token maps by summing quantities per token name.
fn union_tokens(
  a: Dict<AssetName, Int>,
  b: Dict<AssetName, Int>,
) -> Dict<AssetName, Int> {
  dict.union_with(a, b, dict_strategy.sum())
}

/// Sum policy tokens from all outputs at prog_logic_cred.
/// Used by the balance invariant to verify seized tokens stay in the system.
fn sum_policy_tokens_at_cred(
  outputs: List<Output>,
  prog_logic_cred: Credential,
  policy_id: PolicyId,
) -> Dict<AssetName, Int> {
  list.foldr(
    outputs,
    dict.empty,
    fn(output, acc) {
      if output.address.payment_credential == prog_logic_cred {
        let output_dict = assets.to_dict(output.value)
        let policy_tokens = get_policy_tokens(output_dict, policy_id)
        union_tokens(acc, policy_tokens)
      } else {
        acc
      }
    },
  )
}

/// Check that for every token name in `subset`, `superset` has >= that quantity.
/// Implements Plutarch's checkBalanceInvariant for seized token tracking.
///
/// Pre-condition: both lists are well-formed Pairs from Dict (sorted, no duplicates).
fn check_balance_invariant(
  superset: Pairs<AssetName, Int>,
  subset: Pairs<AssetName, Int>,
) -> Bool {
  when subset is {
    [] -> True
    [Pair(name, qty), ..tail_subset] -> {
      let sup_qty, tail_superset <- drop_until_token(superset, name)
      sup_qty >= qty && check_balance_invariant(tail_superset, tail_subset)
    }
  }
}

fn drop_until_token(
  self: Pairs<ByteArray, Int>,
  until: ByteArray,
  return: fn(Int, Pairs<ByteArray, Int>) -> result,
) -> result {
  let head = head_list(self)
  if head.1st == until {
    return(head.2nd, tail_list(self))
  } else {
    drop_until_token(tail_list(self), until, return)
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
