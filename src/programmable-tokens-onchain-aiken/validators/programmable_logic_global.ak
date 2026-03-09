//// Programmable Logic Global Stake Validator
//// This is the core CIP-0143 validator that coordinates all programmable token transfers
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use aiken/builtin.{head_list, tail_list, unconstr_fields}
use aiken/collection/dict.{Dict}
use aiken/collection/list
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Datum, InlineDatum, Input, Output, Transaction}
use types.{
  ProgrammableLogicGlobalRedeemer, RegistryProof, ThirdPartyAct,
  TokenDoesNotExist, TokenExists, TransferAct,
}
use utils.{
  RawValue, Tokens, bytearray_lt, drop_until, elem_at, has_currency_symbol,
  has_key, has_signatory, skip_assert, split_at, sum_output_assets,
  tokens_contains, union_tokens,
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
        validate_3rd_party(
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
  // Collect all programmable tokens across inputs and minted/burned values.
  let input_prog_value: RawValue = get_signed_prog_value(self, prog_logic_cred)

  // Collect all outputs that carry programmable tokens. We use them to ensure that
  // prog tokens cannot escape their fate.
  let output_prog_value: RawValue =
    sum_output_assets(
      self.outputs,
      dict.empty,
      fn(output, select, discard) {
        if output.address.payment_credential == prog_logic_cred {
          expect Some(Inline(_stake_cred)) = output.address.stake_credential
          select(output)
        } else {
          discard()
        }
      },
    )

  // Check transfer logic for each programmable token type and filter to only programmable tokens.
  check_transfer_and_compute_prog_value(
    input_prog_value,
    output_prog_value,
    proofs,
    validate_single_cs(self, _, _, registry_node_cs),
  )
}

fn validate_3rd_party(
  tx: Transaction,
  prog_logic_cred: Credential,
  registry_node_cs: PolicyId,
  registry_node_idx: Int,
  input_idxs: List<Int>,
  outputs_start_idx: Int,
  length_input_idxs: Int,
) -> Bool {
  let Input { output: registry_ref_input, .. } =
    elem_at(tx.reference_inputs, registry_node_idx)

  // Extract registry details from datum
  let
    policy_id,
    _,
    _,
    third_party_transfer_logic_script,
  <- expect_registry_node(registry_ref_input.datum)

  // Validate registry node is authentic
  expect has_currency_symbol(registry_ref_input.value, registry_node_cs)

  // The third party transfer logic script must be invoked
  expect has_key(tx.withdrawals, third_party_transfer_logic_script)

  // Minted/Burned tokens are used as the 'zero value' for computing the delta
  // between outputs and inputs:
  //
  // - burns (negative quantity) reduces the expected output
  // - mints (positive quantity) increases it
  //
  // At the end, all programmable tokens must be account for.
  let minted_or_burned = tx.mint |> assets.tokens(policy_id)

  let
    output_tokens,
    outputs,
  <-
    drop_accum_tokens(
      tx.outputs,
      outputs_start_idx,
      prog_logic_cred,
      policy_id,
      dict.empty,
    )

  check_seized_tokens(
    prog_logic_cred,
    policy_id,
    tx.inputs,
    input_idxs,
    length_input_idxs,
    outputs,
    minted_or_burned,
    output_tokens,
  )
}

/// Drop 'n' output from the list, while accumulating tokens of a given policy present in dropped outputs
fn drop_accum_tokens(
  outputs: List<Output>,
  n: Int,
  prog_logic_cred: Credential,
  policy_id: PolicyId,
  tokens: Tokens,
  return: fn(Tokens, List<Output>) -> result,
) -> result {
  if n <= 0 {
    return(tokens, outputs)
  } else {
    expect [output, ..tail_outputs] = outputs
    let loop =
      drop_accum_tokens(
        tail_outputs,
        n - 1,
        prog_logic_cred,
        policy_id,
        _,
        return,
      )
    if output.address.payment_credential == prog_logic_cred {
      loop(union_tokens(output.value |> assets.tokens(policy_id), tokens))
    } else {
      loop(tokens)
    }
  }
}

/// Analyze inputs and outputs affected by the 3rd-party action (grossly named *seized_tokens* here).
fn check_seized_tokens(
  prog_logic_cred: Credential,
  policy_id: PolicyId,
  inputs: List<Input>,
  input_idxs: List<Int>,
  length_input_idxs: Int,
  outputs: List<Output>,
  input_tokens: Dict<AssetName, Int>,
  output_tokens: Dict<AssetName, Int>,
) -> Bool {
  // This is an optimisation where the transaction builder also provides the length of the input indexes. This
  // allows to not have to repeatedly pattern match on the input indices list to grab the next one; and converts
  // that check into a null check on an integer.
  //
  // This is safe because:
  //
  // - if a larger length than the real one is given:
  //     we'll attempt to 'head_list' on an empty list and the whole validation blows up.
  //
  // - if a smaller length than the real one is given:
  //     we do ensures that there are no unprocessed programmable input once we
  //     reach 0 (which would indicate someone tried to bypass validations).
  //
  if length_input_idxs <= 0 {
    // Any remaining inputs must NOT be locked by the programmable logic
    // credential, so that they don't escape validations.
    list.for_each(
      inputs,
      fn(input) {
        expect input.output.address.payment_credential != prog_logic_cred
      },
    )

    // Finish accumulating relevant tokens in remaining outputs. This ensure
    // that tokens that have moved to new outputs that weren't paired with a
    // seized input are still accounted for.
    let total_output_tokens =
      list.foldl(
        outputs,
        output_tokens,
        fn(output, acc) {
          // Ensure to only count programmable outputs, to not allow tokens to escape.
          if output.address.payment_credential == prog_logic_cred {
            union_tokens(
              // We can safely restrict to the given policy id, to prevent arbitrarily large values
              // from being too costly to merge. We check inclusion in the end, from tokens that have
              // also been filtered by policy id. So other tokens are irrelevant.
              //
              // If anything, it only makes the inclusion stronger by restricting the superset further.
              output.value |> assets.tokens(policy_id),
              acc,
            )
          } else {
            acc
          }
        },
      )

    // All the inputs tokens (seized or not) must still be sent to the prog
    // logic validator. This is checked by ensuring all collected tokens are
    // contained within all programmable outputs, while allowing those outputs
    // to contain other things.
    utils.tokens_contains(
      dict.to_pairs(total_output_tokens),
      dict.to_pairs(input_tokens),
    )?
  } else {
    expect [idx, ..tail_idxs] = input_idxs

    expect [Input { output: input, .. }, ..tail_inputs] =
      skip_assert(
        inputs,
        idx,
        fn(input) {
          // Ensure that any input we skip is NOT locked by a prog logic credential,
          // in case one attempt to spend programmable tokens by simply skipping over
          // them.
          input.output.address.payment_credential != prog_logic_cred
        },
      )

    // All inputs pointed by a proof must be programmable inputs.
    expect input.address.payment_credential == prog_logic_cred

    // Extract the paired output and ensures it preserves address and datum
    let output = head_list(outputs)
    expect output.address == input.address
    expect output.datum == input.datum

    // Extract seized tokens as the delta between outputs and inputs for the
    // given policy, ensuring all else is equal.
    let input_value = assets.to_dict(input.value)
    let output_value = assets.to_dict(output.value)
    let
      input_tokens_at,
      output_tokens_at,
    <- extract_seized_tokens(policy_id, input_value, output_value)

    check_seized_tokens(
      prog_logic_cred,
      policy_id,
      tail_inputs,
      tail_idxs,
      length_input_idxs - 1,
      tail_list(outputs),
      union_tokens(input_tokens_at, input_tokens),
      union_tokens(output_tokens_at, output_tokens),
    )
  }
}

fn extract_seized_tokens(
  policy_id: PolicyId,
  input_tokens: Dict<PolicyId, Tokens>,
  output_tokens: Dict<PolicyId, Tokens>,
  return: fn(Tokens, Tokens) -> result,
) -> result {
  let
    input_tokens_before,
    input_tokens_at,
    input_tokens_after,
  <- split_at(input_tokens, policy_id)

  let
    output_tokens_before,
    output_tokens_at,
    output_tokens_after,
  <- split_at(output_tokens, policy_id)

  // Seized tokens must change, but only them.
  expect and {
      (input_tokens_before == output_tokens_before)?,
      (input_tokens_after == output_tokens_after)?,
      (input_tokens_at != output_tokens_at)?,
    }

  return(input_tokens_at, output_tokens_at)
}

fn get_signed_prog_value(
  tx: Transaction,
  prog_logic_cred: Credential,
) -> RawValue {
  sum_output_assets(
    tx.inputs,
    assets.to_dict(tx.mint),
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
  input_value: RawValue,
  output_value: RawValue,
  proofs: List<RegistryProof>,
  check_policy: fn(PolicyId, RegistryProof) -> Bool,
) -> Bool {
  let input_assets = dict.to_pairs(input_value)
  let output_assets = dict.to_pairs(output_value)

  let remaining_proofs =
    do_check_transfer(proofs, check_policy, input_assets, output_assets)

  [] == remaining_proofs
}

fn do_check_transfer(
  proofs: List<RegistryProof>,
  check_policy: fn(PolicyId, RegistryProof) -> Bool,
  input_assets: Pairs<PolicyId, Dict<AssetName, Int>>,
  output_assets: Pairs<PolicyId, Dict<AssetName, Int>>,
) -> List<RegistryProof> {
  when input_assets is {
    [] -> proofs
    [Pair(cs, head_input_tokens), ..tail_input_assets] -> {
      // We expect one proof per policy, if not, this blows up and halts the validation.
      let proof = head_list(proofs)

      let loop =
        do_check_transfer(tail_list(proofs), check_policy, tail_input_assets, _)

      if check_policy(cs, proof) {
        // Existing programmable token, must be in output.

        // Outputs must be a superset of inputs, so they may contain extra
        // policies not found in validated inputs. Yet, both input assets and
        // output assets are in ascending policy order.
        let
          head_output_tokens,
          tail_output_assets,
        <- drop_until(output_assets, cs)

        expect
          tokens_contains(
            dict.to_pairs(head_output_tokens),
            dict.to_pairs(head_input_tokens),
          )

        loop(tail_output_assets)
      } else {
        // Not a programmable token, skip it
        loop(output_assets)
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
  expect node_idx: Int = head_list(unconstr_fields(proof))

  // Get the registry node details
  let node_input = elem_at(self.reference_inputs, node_idx)
  let
    key,
    next,
    transfer_logic_script,
    _,
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
  return: fn(ByteArray, ByteArray, Credential, Credential) -> result,
) -> result {
  expect InlineDatum(inline_datum) = datum
  let fields = unconstr_fields(inline_datum)
  expect key: ByteArray = head_list(fields)
  let fields = tail_list(fields)
  expect next: ByteArray = head_list(fields)
  let fields = tail_list(fields)
  expect transfer_logic_script: Credential = head_list(fields)
  let fields = tail_list(fields)
  expect third_party_transfer_logic_script: Credential = head_list(fields)
  return(key, next, transfer_logic_script, third_party_transfer_logic_script)
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
