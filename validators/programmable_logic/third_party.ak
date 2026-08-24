//// Third-party transfer invariants (seize / clawback / freeze enforcement),
//// hosted by the standalone `third_party` withdraw-0 validator.
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use aiken/collection/dict
use aiken/collection/list.{foldl} as aiken_list
use assets
use cardano/address.{Credential, Inline}
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
  outputs_start_idx: Int,
  max_inline_datum_bytes: Int,
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
    max_inline_datum_bytes,
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

  validate_io_constraints_and_balance(
    prog_logic_cred,
    policy_id,
    max_inline_datum_bytes,
    self.inputs,
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
  max_inline_datum_bytes: Int,
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
      max_inline_datum_bytes,
      _,
      return,
    )

    if output.address.payment_credential == prog_logic_cred {
      expect Some(Inline(..)) = output.address.stake_credential
      expect
        assets.is_seizable_output_shape_bounded(output, max_inline_datum_bytes)?
      loop(tokens.union(tokens, output.value |> value.tokens(policy_id)))
    } else {
      loop(tokens)
    }
  }
}

/// Walk PLB inputs paired positionally with PLB outputs, enforcing the two
/// invariants a well-formed ThirdPartyAct transaction must satisfy:
///
///   1. **Per-pair constraints** (per PLB input/output pair):
///        * `address`, `datum`, and `reference_script` are byte-identical
///          across the pair (so the seizure doesn't move tokens between
///          owners, change ownership metadata, or attach/strip reference
///          scripts).
///        * For the policy being acted on: the input must already hold
///          tokens of this policy (Finding 12 — the paired UTxO can be
///          modified but not contaminated with a foreign policy injected
///          as if seized from it).
///        * For every NON-acted-on policy: the input's tokens for that
///          policy and the paired output's tokens for that policy must be
///          byte-identical (no spam, no foreign-policy injection — the
///          `before`/`after` halves of the two `split_at`s must match).
///
///   2. **Conservation balance** (once inputs are exhausted): the sum of
///      the acted-on policy's tokens across all PLB outputs must be a
///      superset of the sum across all PLB inputs PLUS any mint/burn of
///      that policy in this transaction. This is what guarantees seized
///      tokens cannot escape PLB.
fn validate_io_constraints_and_balance(
  prog_logic_cred: Credential,
  policy_id: PolicyId,
  max_inline_datum_bytes: Int,
  inputs: List<Input>,
  outputs: List<Output>,
  input_tokens: Tokens,
  output_tokens: Tokens,
) -> Bool {
  when inputs is {
    [] -> {
      // Finish accumulating relevant tokens in remaining outputs. This ensure
      // that tokens that have moved to new outputs that weren't paired with a
      // seized input are still accounted for.
      let total_output_tokens = foldl(
        outputs,
        output_tokens,
        fn(output, acc) {
          // Ensure to only count programmable outputs, to not allow tokens to escape.
          if output.address.payment_credential == prog_logic_cred {
            // Issue #106, fourth creation site: a third-party action creates
            // fresh PLB outputs (the destinations the seized tokens land in),
            // and those must stay seizable in turn — no datum hash, no
            // reference script. Without this an administrator, or a hostile
            // substandard's third-party logic, could produce a UTxO nobody can
            // ever seize again. The PAIRED outputs need no check here: they are
            // byte-identical to their inputs, which were themselves shape-checked
            // when created.
            //
            // The inline stake credential is required for the same reason
            // `no_escape` requires it on the issuance path: a PLB output without
            // one has no owner `owner.ak` can ever authorise, so it is
            // permanently unspendable. `issuance_mint` skips `no_escape` when it
            // delegates custody here, so this is the only place that catches a
            // mint composed with a seize.
            expect Some(Inline(..)) = output.address.stake_credential
            expect
              assets.is_seizable_output_shape_bounded(
                output,
                max_inline_datum_bytes,
              )?
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
    }

    [Input { output: input, .. }, ..tail_inputs] ->
      // Validate all inputs pointing at a programmable proof
      if input.address.payment_credential == prog_logic_cred {
        // Extract the paired output and ensure it preserves address, datum,
        // AND reference_script. Finding 13: without the reference_script
        // equality, a third-party-act tx could swap or attach a reference
        // script on the continuing output, dropping a legitimate one or
        // inserting a misleading attestation while seizing tokens.
        let output = list.head(outputs)
        expect output.address == input.address
        expect output.datum == input.datum
        expect output.reference_script == input.reference_script

        // [AL] issue #96: peel the ada entry (empty policy id — always the
        // first entry, since every UTxO holds lovelace) off BOTH sides before
        // comparing the halves, and RATCHET it: the paired output must carry
        // at least the input's lovelace. Splitting the full value put ada in
        // the `before` half, so its byte-equality forced exact lovelace
        // conservation per pair — and a protocol-parameter rise of the
        // min-ADA calculation above an existing UTxO's lovelace made every
        // ThirdPartyAct on it unsatisfiable forever (equality forbade the
        // top-up that would absorb the rise). `>=` ONLY: lovelace is not a
        // programmable asset, so accepting less would let the admin drain
        // the holder's ada while seizing.
        let input_lovelace, input_assets <- assets.split_lovelace(input.value)
        let output_lovelace, output_assets <- assets.split_lovelace(
          output.value,
        )
        expect (output_lovelace >= input_lovelace)?

        // Extract seized tokens as the delta between outputs and inputs for the
        // given policy, ensuring all else is equal.
        let input_tokens_before, input_tokens_at, input_tokens_after <- assets.assets_split_at(
          input_assets,
          policy_id,
        )

        let output_tokens_before, output_tokens_at, output_tokens_after <- assets.assets_split_at(
          output_assets,
          policy_id,
        )

        // Non-acted-on policies must be byte-identical between input and
        // paired output (no foreign-policy injection / spam). The acted-on
        // policy must already be present in the input (Finding 12 —
        // otherwise this third-party action would CONTAMINATE an innocent
        // UTxO that never held the policy).
        //
        // R-03 (re-audit): a former `input_tokens_at != output_tokens_at`
        // guard tried to reject no-op forced respends as an anti-DoS measure.
        // It was removed. It was PAIR-LOCAL, so it never delivered the
        // aggregate guarantee it appeared to: an admin can restore a holder's
        // exact balance in an UNPAIRED output (any output before
        // `outputs_start_idx`, or a trailing output past the paired inputs)
        // that the per-pair check never inspects, making the whole seizure a
        // net no-op while every pair still shows a local delta. A proper
        // per-owner aggregate anti-churn check was measured and costs ~+22%
        // in script size, CPU and memory on the coordinator (the script every
        // transfer references) — disproportionate for a threat Cardano's fee
        // model already mitigates: each forced respend costs the (trusted)
        // admin real fees, so sustained no-op churn is self-limiting. The
        // `!is_empty` line below is a SEPARATE Finding-12 anti-injection
        // invariant (the input must already hold the acted-on policy) and
        // stays.
        expect !dict.is_empty(input_tokens_at)
        expect and {
            (input_tokens_before == output_tokens_before)?,
            (input_tokens_after == output_tokens_after)?,
          }

        validate_io_constraints_and_balance(
          prog_logic_cred,
          policy_id,
          max_inline_datum_bytes,
          tail_inputs,
          list.tail(outputs),
          tokens.union(input_tokens, input_tokens_at),
          tokens.union(output_tokens_at, output_tokens),
        )
      } else {
        validate_io_constraints_and_balance(
          prog_logic_cred,
          policy_id,
          max_inline_datum_bytes,
          tail_inputs,
          outputs,
          input_tokens,
          output_tokens,
        )
      }
  }
}
