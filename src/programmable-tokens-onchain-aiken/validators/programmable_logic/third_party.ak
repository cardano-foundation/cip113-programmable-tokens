//// Programmable Logic Global Stake Validator
//// This is the core CIP-0143 validator that coordinates all programmable token transfers
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use aiken/collection/dict
use aiken/collection/list.{foldl, for_each} as aiken_list
use assets
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{Input, Output, Transaction}
use list
use pairs
use registry_node.{with_key_and_3rd_party_logic}
use tokens.{Tokens}

pub fn validate_3rd_party(
  self: Transaction,
  prog_logic_cred: Credential,
  registry_node: Data,
  input_idxs: List<Int>,
  outputs_start_idx: Int,
  length_input_idxs: Int,
) -> Bool {
  // Extract registry details from datum
  let policy_id, third_party_logic <- with_key_and_3rd_party_logic(
    registry_node,
  )

  // The third party transfer logic script must be invoked
  expect pairs.has_key_or_fail(self.withdrawals, third_party_logic)

  let output_tokens, outputs <- drop_accum_tokens(
    self.outputs,
    outputs_start_idx,
    prog_logic_cred,
    policy_id,
    dict.empty,
  )

  // Minted/Burned tokens are used as the 'zero value' for computing the delta
  // between outputs and inputs:
  //
  // - burns (negative quantity) reduces the expected output
  // - mints (positive quantity) increases it
  //
  // At the end, all programmable tokens must be account for.
  let minted_or_burned = self.mint |> value.tokens(policy_id)

  check_seized_tokens(
    prog_logic_cred,
    policy_id,
    self.inputs,
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

    let loop = drop_accum_tokens(
      tail_outputs,
      n - 1,
      prog_logic_cred,
      policy_id,
      _,
      return,
    )

    if output.address.payment_credential == prog_logic_cred {
      loop(tokens.union(tokens, output.value |> value.tokens(policy_id)))
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
  input_tokens: Tokens,
  output_tokens: Tokens,
) -> Bool {
  // This is an optimisation where the transaction builder also provides the length of the input indexes. This
  // allows to not have to repeatedly pattern match on the input indices list to grab the next one; and converts
  // that check into a null check on an integer.
  //
  // This is safe because:
  //
  // - if a larger length than the real one is given:
  //     we'll attempt to 'list.head' on an empty list and the whole validation blows up.
  //
  // - if a smaller length than the real one is given:
  //     we do ensures that there are no unprocessed programmable input once we
  //     reach 0 (which would indicate someone tried to bypass validations).
  //
  if length_input_idxs <= 0 {
    // Any remaining inputs must NOT be locked by the programmable logic
    // credential, so that they don't escape validations.
    for_each(
      inputs,
      fn(input) {
        expect input.output.address.payment_credential != prog_logic_cred
      },
    )

    // Finish accumulating relevant tokens in remaining outputs. This ensure
    // that tokens that have moved to new outputs that weren't paired with a
    // seized input are still accounted for.
    let total_output_tokens = foldl(
      outputs,
      output_tokens,
      fn(output, acc) {
        // Ensure to only count programmable outputs, to not allow tokens to escape.
        if output.address.payment_credential == prog_logic_cred {
          tokens.union(
            // We can safely restrict to the given policy id, to prevent arbitrarily large values
            // from being too costly to merge. We check inclusion in the end, from tokens that have
            // also been filtered by policy id. So other tokens are irrelevant.
            //
            // If anything, it only makes the inclusion stronger by restricting the superset further.
            output.value |> value.tokens(policy_id),
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
    tokens.contains(
      dict.to_pairs(total_output_tokens),
      dict.to_pairs(input_tokens),
    )?
  } else {
    expect [idx, ..tail_idxs] = input_idxs

    expect [Input { output: input, .. }, ..tail_inputs] = list.skip_assert_or_fail(
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
    let output = list.head(outputs)
    expect output.address == input.address
    expect output.datum == input.datum

    // Extract seized tokens as the delta between outputs and inputs for the
    // given policy, ensuring all else is equal.
    let input_tokens_before, input_tokens_at, input_tokens_after <- assets.split_at(
      input.value,
      policy_id,
    )

    let output_tokens_before, output_tokens_at, output_tokens_after <- assets.split_at(
      output.value,
      policy_id,
    )

    // Seized tokens must change, but only them.
    expect and {
        (input_tokens_before == output_tokens_before)?,
        (input_tokens_after == output_tokens_after)?,
        (input_tokens_at != output_tokens_at)?,
      }

    check_seized_tokens(
      prog_logic_cred,
      policy_id,
      tail_inputs,
      tail_idxs,
      length_input_idxs - 1,
      list.tail(outputs),
      tokens.union(input_tokens, input_tokens_at),
      tokens.union(output_tokens_at, output_tokens),
    )
  }
}
