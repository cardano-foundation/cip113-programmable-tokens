//// Unfracking invariants — v2 (registry-gated, third-party-shaped)
////
//// This module is the engine of the standalone `unfracking` withdraw-0
//// validator, which programmable_logic_base dispatches to directly under a
//// `SpendViaUnfracking` redeemer — the `transfer` validator plays no part in
//// an unfracking transaction, keeping the hot-path transfer reference script
//// small. See `unfracking`'s module docs for the delegation rationale.
////
//// An unfracking action lets a holder restructure the PLB UTxOs they
//// own for ONE registered policy — the motivating case being a
//// "fracked" UTxO holding several policies, where a freeze scoped to
//// one policy locks them all together. Acting on that one policy moves
//// its tokens into their own UTxO(s) while everything else stays put.
////
//// v2 changes vs v1 (see design doc `unfracking-v2-registry-hook.md`):
////
////   * SINGLE-POLICY per action, named by a registry node — no longer a
////     whole-UTxO free-for-all restructuring.
////   * REGISTRY-GATED, least permission by default: the acted-on
////     policy's `unfracking_logic_script` withdraw-0 must be invoked in
////     the same transaction. An UNSET hook (`empty_vkey`) means
////     unfracking is FORBIDDEN for that policy. No script, no party.
////     Issuers opt in explicitly; stateful (datum-carrying) tokens get
////     their restructuring constraints enforced by their own hook.
////   * ThirdPartyAct-SHAPED pairing, FULL STRIP: every PLB input is
////     paired positionally with a continuing output; per pair the
////     address, datum, reference script and every NON-acted policy's
////     tokens are byte-identical, ada is free, and the acted policy is
////     stripped ENTIRELY — present in the input, absent from the
////     continuing output. Partial strips are rejected: a continuing
////     output still carrying the acted policy would still require that
////     policy's transfer proof on every future spend (still stuck, in
////     the freeze case), and any partial same-owner rebalancing is
////     a transfer's job — with the policy's transfer logic as the
////     proper bouncer — not this bypass's.
////
//// Invariants enforced here:
////
////   * `tx.mint` is zero — unfracking is strictly value-preserving;
////     mint/burn is issuance_mint's job.
////   * The acted-on policy's hook withdraw-0 is invoked. Default-deny
////     falls out: an unset hook is `empty_vkey`, and no ledger tx can
////     carry a withdrawal keyed by an empty hash.
////   * SINGLE OWNER: every PLB input carries the same full address —
////     payment `prog_logic_cred` + the stake credential pinned by the
////     first PLB input. The owner authorises once: a vkey stake
////     credential signs (`extra_signatories`), a script stake
////     credential's withdraw-0 must be invoked (same pattern as
////     a transfer). Restructuring across owners would be a transfer in
////     disguise, bypassing `transfer_logic_script`.
////   * PER PAIR: `address`, `datum`, `reference_script` byte-identical;
////     the ada-less asset lists are compared in ONE lockstep walk that
////     requires them byte-identical EXCEPT the acted policy's entry,
////     which must be present on the input side and absent on the output
////     side (full strip; a pair without the acted policy has no
////     business in an unfracking action). Ada is deliberately
////     UNCONSTRAINED: the single owner authorised the action, ada is
////     not a programmable asset, and any equality would re-create the
////     issue-#96 hazard (a min-ADA parameter rise bricking the action).
////   * CONSERVATION, strict equality: the acted policy's total over
////     the NON-PAIRED outputs at the OWNER address equals its total
////     over the PLB inputs (paired outputs cannot carry it at all).
////     Equality (not containment) because mint is zero and PLB tokens
////     cannot enter from non-PLB inputs — and it pins both directions:
////     no leak (shortfall) and no fabrication (surplus). Counting ONLY
////     owner-address outputs is what forces acted tokens to land at
////     the owner: a token routed to any other stake credential leaves
////     the owner-side total short and the equality fails.
////
//// What falls out for free:
////
////   * Non-acted tokens (registered or not) cannot move or escape — the
////     per-pair byte-identity pins them where they are.
////   * A co-resident policy's stateful DATUM is untouched by another
////     policy's unfracking — datums continue byte-for-byte in pairs.
////   * Acted tokens cannot escape the PLB: they may only land at the
////     owner address, whose payment credential IS the PLB.

use aiken/collection/dict
use aiken/collection/list.{foldl} as aiken_list
use assets.{Assets}
use cardano/address.{Address, Credential}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{Input, Output, Transaction}
use list
use pairs
use programmable_logic/owner.{authorised_stake_cred}
use registry_node.{with_key_and_unfracking_logic}
use tokens.{Tokens}

/// Validate an Unfracking action. See module docstring for the full
/// invariant list. `registry_node` is the acted-on policy's registry
/// datum (located and NFT-authenticated by the caller);
/// `outputs_start_idx` is the index where the paired continuing outputs
/// begin, same discipline as ThirdPartyAct.
pub fn validate_unfracking(
  self: Transaction,
  prog_logic_cred: Credential,
  registry_node: Data,
  outputs_start_idx: Int,
  max_inline_datum_bytes: Int,
) -> Bool {
  // Unfracking is value-preserving by construction: any mint/burn would
  // silently change the totals the conservation equality compares.
  expect value.is_zero(self.mint)

  let policy_id, unfracking_logic <- with_key_and_unfracking_logic(
    registry_node,
  )

  // The hook is always executed — same invocation style as the transfer
  // and third-party logic scripts. This single check also carries the
  // default-deny: an unset hook is `empty_vkey`, and no transaction can
  // carry a withdrawal keyed by an empty hash (a reward account is a
  // header byte + 28-byte hash; anything shorter fails phase-1
  // deserialisation), so an issuer who never set the hook has FORBIDDEN
  // unfracking for this policy. No script, no party. Same ledger
  // impossibility the transfer / third-party invocations already rely
  // on for the origin node's empty credentials.
  expect pairs.has_key_or_fail(self.withdrawals, unfracking_logic)

  // Pin the single owner from the first PLB input and authorise it once
  // (signature for a vkey stake credential, withdraw-0 for a script one).
  let owner_address = pin_and_authorise_owner(
    self.inputs,
    prog_logic_cred,
    self.extra_signatories,
    self.withdrawals,
  )

  // Outputs before the paired region: accumulate acted-policy tokens
  // sitting at the owner address (the "optional other UTxOs" that
  // receive regrouped tokens).
  let output_tokens, outputs <- drop_accum_owner_tokens(
    self.outputs,
    outputs_start_idx,
    owner_address,
    policy_id,
    max_inline_datum_bytes,
    dict.empty,
  )

  validate_pairs_and_conservation(
    prog_logic_cred,
    owner_address,
    policy_id,
    max_inline_datum_bytes,
    self.inputs,
    outputs,
    dict.empty,
    output_tokens,
  )
}

/// Find the FIRST PLB input, authorise its stake credential, and return
/// its full address as the pinned owner address. Aborts if no PLB input
/// exists — unfracking with zero PLB inputs is meaningless.
fn pin_and_authorise_owner(
  inputs: List<Input>,
  prog_logic_cred: Credential,
  extra_signatories: List<ByteArray>,
  withdrawals: Pairs<Credential, Int>,
) -> Address {
  when inputs is {
    [] -> fail
    [input, ..tail] -> {
      let output = input.output
      if output.address.payment_credential == prog_logic_cred {
        expect _stake_cred = authorised_stake_cred(
          output.address,
          list.has_or_fail(extra_signatories, _),
          pairs.has_key_or_fail(withdrawals, _),
        )
        output.address
      } else {
        pin_and_authorise_owner(
          tail,
          prog_logic_cred,
          extra_signatories,
          withdrawals,
        )
      }
    }
  }
}

/// Drop `n` outputs from the list, accumulating acted-policy tokens from
/// the dropped outputs that sit at the OWNER address. Same shape as
/// ThirdPartyAct's `drop_accum_tokens`, but filtered on the full owner
/// address (payment + stake) rather than the payment credential alone —
/// acted tokens may only regroup at the owner.
fn drop_accum_owner_tokens(
  outputs: List<Output>,
  n: Int,
  owner_address: Address,
  policy_id: PolicyId,
  max_inline_datum_bytes: Int,
  acc: Tokens,
  return: fn(Tokens, List<Output>) -> result,
) -> result {
  if n <= 0 {
    return(acc, outputs)
  } else {
    expect [output, ..tail_outputs] = outputs

    let loop = drop_accum_owner_tokens(
      tail_outputs,
      n - 1,
      owner_address,
      policy_id,
      max_inline_datum_bytes,
      _,
      return,
    )

    if output.address == owner_address {
      // Destination outputs are freshly created PLB UTxOs; keep them seizable
      // (no datum hash, no reference script).
      expect
        assets.is_seizable_output_shape_bounded(output, max_inline_datum_bytes)?
      loop(tokens.union(acc, output.value |> value.tokens(policy_id)))
    } else {
      loop(acc)
    }
  }
}

/// Walk PLB inputs paired positionally with continuing outputs (the
/// ThirdPartyAct walk, single-owner flavoured), then settle the
/// conservation equality once inputs are exhausted.
fn validate_pairs_and_conservation(
  prog_logic_cred: Credential,
  owner_address: Address,
  policy_id: PolicyId,
  max_inline_datum_bytes: Int,
  inputs: List<Input>,
  outputs: List<Output>,
  input_tokens: Tokens,
  output_tokens: Tokens,
) -> Bool {
  when inputs is {
    [] -> {
      // Accumulate acted-policy tokens from the remaining (unpaired)
      // outputs at the owner address — under full strip these are the
      // ONLY outputs that may carry the acted policy — then require
      // STRICT equality with the input-side total: no leak, no
      // fabrication, owner-only destinations.
      let total_output_tokens = foldl(
        outputs,
        output_tokens,
        fn(output, acc) {
          if output.address == owner_address {
            // Destination outputs are freshly created PLB UTxOs; keep them
            // seizable (no datum hash, no reference script).
            expect
              assets.is_seizable_output_shape_bounded(
                output,
                max_inline_datum_bytes,
              )?
            tokens.union(output.value |> value.tokens(policy_id), acc)
          } else {
            acc
          }
        },
      )

      (total_output_tokens == input_tokens)?
    }

    [Input { output: input, .. }, ..tail_inputs] ->
      if input.address.payment_credential == prog_logic_cred {
        // Single-owner invariant: every PLB input carries the pinned
        // owner address (payment + stake). A second stake credential in
        // the input set would make this a cross-owner transfer in
        // disguise.
        expect (input.address == owner_address)?

        // The paired continuing output preserves address, datum AND
        // reference script (Finding 13 applies to unfracking too).
        let output = list.head(outputs)
        expect (output.address == input.address)?
        expect (output.datum == input.datum)?
        expect (output.reference_script == input.reference_script)?

        // Drop ada from both sides (guaranteed present and always first
        // in a ledger Value — same idiom as `assets.collect`); ada is
        // deliberately unconstrained in unfracking pairs (module docs;
        // issue-#96 hazard class), so unlike the ThirdPartyAct ratchet
        // the lovelace is not even read. One lockstep walk then enforces
        // the FULL-STRIP pair rule: byte-identical asset lists except
        // the acted entry, present on the input side only.
        let input_assets = assets.from_value(input.value) |> list.tail
        let output_assets = assets.from_value(output.value) |> list.tail

        let acted_tokens = strip_acted_entry(
          input_assets,
          output_assets,
          policy_id,
        )

        validate_pairs_and_conservation(
          prog_logic_cred,
          owner_address,
          policy_id,
          max_inline_datum_bytes,
          tail_inputs,
          list.tail(outputs),
          tokens.union(input_tokens, acted_tokens),
          output_tokens,
        )
      } else {
        validate_pairs_and_conservation(
          prog_logic_cred,
          owner_address,
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

/// The full-strip pair rule in one lockstep walk over the two ada-less
/// asset lists (both canonically sorted): every entry must be
/// byte-identical across the pair EXCEPT the acted policy's entry,
/// which must be PRESENT on the input side and is skipped — the
/// remaining input tail must then equal the entire remaining output.
/// Returns the acted entry's tokens for the conservation total.
///
/// Failure modes, all loud:
///   * input lacks the acted policy — the walk runs past where the
///     entry would sort (or off the end) and the pairwise equality (or
///     the head `expect`) fails;
///   * output still carries the acted policy (partial strip / no-op) —
///     the tail equality fails on that entry;
///   * any non-acted delta, extra or missing entry — the pairwise
///     equality fails.
fn strip_acted_entry(
  input_assets: Assets,
  output_assets: Assets,
  policy_id: PolicyId,
) -> Tokens {
  expect [Pair(policy, policy_tokens), ..input_rest] = input_assets
  if policy == policy_id {
    expect (input_rest == output_assets)?
    policy_tokens
  } else {
    expect [output_head, ..output_rest] = output_assets
    expect (Pair(policy, policy_tokens) == output_head)?
    strip_acted_entry(input_rest, output_rest, policy_id)
  }
}
