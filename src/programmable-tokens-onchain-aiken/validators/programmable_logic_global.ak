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
  RawValue, Tokens, bytearray_lt, elem_at, has_currency_symbol, has_key,
  has_signatory, merge_raw_values, skip_assert, split_at, sum_output_values,
  union_tokens,
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
  let minted_or_burned =
    dict.get_or_else(assets.to_dict(tx.mint), policy_id, fn() { dict.empty })

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

  // NOTE: check_seized_tokens "consumes" inputs it validates as it goes, whereas
  // indices refer to the number of inputs to skip since the last input. So that
  // means we have to skip one less input than advertised by the indexes...
  //
  // ...except for the first index! So we artificially increment this index to ensure
  // we can handle all input in an homogeneous fashion.
  expect [head_idx, ..tail_idxs] = input_idxs

  check_seized_tokens(
    prog_logic_cred,
    policy_id,
    tx.inputs,
    [head_idx + 1, ..tail_idxs],
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
      loop(
        union_tokens(
          dict.get_or_else(
            assets.to_dict(output.value),
            policy_id,
            fn() { dict.empty },
          ),
          tokens,
        ),
      )
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
              dict.get_or_else(
                assets.to_dict(output.value),
                policy_id,
                fn() { dict.empty },
              ),
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
    utils.token_contains(
      dict.to_pairs(total_output_tokens),
      dict.to_pairs(input_tokens),
    )?
  } else {
    expect [idx, ..tail_idxs] = input_idxs

    expect [Input { output: input, .. }, ..tail_inputs] =
      skip_assert(
        inputs,
        idx - 1,
        fn(input) {
          // Ensure that any input we skip is NOT locked by a prog logic credential,
          // in case one attempt to spend programmable tokens by simply skipping over
          // them.
          input.output.address.payment_credential != prog_logic_cred
        },
      )

    // Alleviate a bit the reading by pre-applying arguments for the next
    // iteration. From there, we may or may not consume the next output.
    let loop =
      check_seized_tokens(
        prog_logic_cred,
        policy_id,
        tail_inputs,
        tail_idxs,
        length_input_idxs - 1,
        _,
        _,
        _,
      )

    if input.address.payment_credential == prog_logic_cred {
      let output = head_list(outputs)

      let input_value = assets.to_dict(input.value)
      let output_value = assets.to_dict(output.value)

      // Output must preserve address and datum
      expect output.address == input.address
      expect output.datum == input.datum

      // Extract seized tokens as the delta between outputs and inputs for the
      // given policy, ensuring all else is equal.
      let
        input_tokens_at,
        output_tokens_at,
      <- extract_seized_tokens(policy_id, input_value, output_value)

      loop(
        tail_list(outputs),
        union_tokens(input_tokens_at, input_tokens),
        union_tokens(output_tokens_at, output_tokens),
      )
    } else {
      // NOTE: clarify this ?
      // I am missing context to understand this but this is what the Plutarch implementation does; it allows
      // script other than the programmable logic to be pointed by the index list? I don't see why this is a
      // good (or even convenient) thing? Why can't one simply NOT target non-programmable input in their
      // redeemer? Seems odd.
      expect Script(..) = input.address.payment_credential
      loop(outputs, input_tokens, output_tokens)
    }
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
