use aiken/builtin.{less_than_bytearray}
use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId} as value
use cardano/transaction.{Input, Output, Transaction}
use prog_assets
use programmable_logic/owner.{authorised_stake_cred}
use registry_node.{with_key_and_next_key, with_key_and_transfer_logic}
use types.{RegistryProof, TokenDoesNotExist, TokenExists}
use unsafe_list

/// Validate a transfer action
pub fn validate_transfer(
  self: Transaction,
  programmable_logic_base_cred: Credential,
  get_registry_node: fn(Int) -> Data,
  proofs: List<RegistryProof>,
  max_inline_datum_bytes: Int,
) -> Bool {
  // NOTE: The transfer validator is always invoked via a withdrawal, so
  // we know there's AT LEAST ONE withdrawal.
  let first_withdrawal = unsafe_list.expect_head(self.withdrawals).1st
  let has_withdrawal = new_withdrawal_checker(
    fn(script_hash) { script_hash == first_withdrawal },
    unsafe_list.expect_tail(self.withdrawals),
  )

  // Collect all programmable tokens across inputs and minted/burned values.
  // A policy that appears only in `tx.mint` (a pure mint, not present in any
  // input) is dropped — `issuance_logic` owns its custody, not the transfer
  // path (Finding 02; see `collect_input_assets`).
  let input_value, input_assets <- collect_input_assets(
    self,
    has_withdrawal,
    programmable_logic_base_cred,
  )

  // Collect all outputs that carry programmable tokens. We use them to ensure that
  // prog tokens cannot escape their fate.
  let output_value = prog_assets.collect_output_assets(
    self.outputs,
    programmable_logic_base_cred,
    max_inline_datum_bytes,
  )

  // One proof per input policy, in ascending policy order, and the proof
  // list must be exactly consumed — a transaction carrying a trailing proof
  // is rejected.
  expect [], actual_input_value <- verify_proofs(
    get_registry_node,
    has_withdrawal,
    proofs,
    input_value,
    input_assets,
  )

  builtin.contains_value(output_value, actual_input_value)
}

fn new_withdrawal_checker(
  has_withdrawal: fn(Credential) -> Bool,
  withdrawals: Pairs<Credential, Int>,
) -> fn(Credential) -> Bool {
  when withdrawals is {
    [] -> has_withdrawal
    [Pair(head, _), ..tail] ->
      new_withdrawal_checker(
        fn(script_hash) { head == script_hash || has_withdrawal(script_hash) },
        tail,
      )
  }
}

fn collect_input_assets(
  tx: Transaction,
  has_withdrawal: fn(Credential) -> Bool,
  programmable_logic_base_cred: Credential,
  return: fn(Value, Pairs<PolicyId, Data>) -> result,
) -> result {
  let has_signatory = unsafe_list.has_or_fail(tx.extra_signatories, _)

  // Seeded with EMPTY assets (Finding 02). Mint contributions are folded in
  // AFTER the input scan via `apply_mint_to_known_policies`, which keeps
  // mint deltas ONLY for policies that appear in PLB inputs. Mint-only
  // ("purely minted") policies are dropped here — a pure mint routed to a
  // non-PLB address is not this path's concern. That custody check belongs
  // in `issuance_logic`, whose precise per-registry-node delegation
  // (Finding 04) covers both the third-party + mint escape and this
  // transfer + mint variant: it delegates only to a validator whose
  // redeemer names the minted policy's node, and otherwise enforces
  // `no_escape` itself.
  let programmable_logic_base_inputs = prog_assets.collect(
    tx.inputs,
    {},
    fn(input, select, discard) {
      let output = input.output
      if output.address.payment_credential == programmable_logic_base_cred {
        expect _stake_cred = authorised_stake_cred(
          output.address,
          has_signatory,
          has_withdrawal,
        )
        select(output)
      } else {
        discard()
      }
    },
  )

  expect input_assets: Pairs<PolicyId, Data> = builtin.value_data(
    programmable_logic_base_inputs,
  )

  return(
    apply_mint_to_known_policies(programmable_logic_base_inputs, tx.mint),
    input_assets,
  )
}

/// Apply mint deltas onto known input policies. Mint-only policies are
/// dropped — issuance_mint owns their custody (Finding 02 fix).
///
/// Outer recursion walks `inputs`; for each input policy we call
/// `prog_assets.assets_split_at` on the remaining `mint`. The split_at trichotomy
/// maps 1:1 onto what the contract needs:
///
///   * `before`         = mint policies with id < `i_policy`. Pure mints by
///                        contract — dropped. They fall out of the output
///                        naturally because we never include them; the cons
///                        cells `do_split_at` allocates while skipping them
///                        ARE the work of identifying them, not waste.
///   * `mint_at_policy` = mint tokens for `i_policy` (or `dict.empty`). When
///                        non-empty, merged via `tokens.union` (per-name
///                        `sum_if_non_zero`, so a full burn collapses to an
///                        empty entry that `verify_proofs` already treats as
///                        "burned").
///   * `mint_after`     = mint policies with id > `i_policy`. Becomes the
///                        new search space for the next input policy, so
///                        total split_at work across all iterations is
///                        O(|mint|).
///
/// When `inputs` runs out, any remaining `mint_after` is dropped by virtue
/// of the `[] -> []` base case — the rest of the pure-mint pile.
///
/// Pre-condition (held at every call site): both arguments are sorted
/// ascending by policy id. `prog_assets.collect` and `prog_assets.from_value` both
/// produce canonically-sorted Assets.
///
/// Cost: O(|inputs| + |mint|); `tokens.union` paid only at exact matches.
fn apply_mint_to_known_policies(inputs: Value, mint: value.Value) -> Value {
  // Mint-empty short-circuit at the OUTER level: a transfer-only tx (no
  // mint) skips the per-input `assets_split_at` calls entirely, so it pays
  // no per-policy split cost.
  if value.zero == mint {
    inputs
  } else {
    builtin.union_value(inputs, builtin.un_value_data(mint))
  }
}

/// Consume one proof per input policy, in ascending order. A programmable
/// policy (`TokenExists`) must be contained in the paired output policy
/// unless fully burned, in which case it is not expected in the outputs at
/// all. An unregistered policy (`TokenDoesNotExist`) is skipped. Aborts on
/// an invalid proof.
fn verify_proofs(
  get_registry_node: fn(Int) -> Data,
  has_withdrawal: fn(Credential) -> Bool,
  proofs: List<RegistryProof>,
  input_value: Value,
  input_assets: Pairs<PolicyId, Data>,
  return: fn(List<RegistryProof>, Value) -> result,
) -> result {
  when input_assets is {
    [] -> return(proofs, input_value)
    [Pair(policy, head_input_tokens), ..tail_input_assets] -> {
      let input_value = when unsafe_list.expect_head(proofs) is {
        TokenExists { node_idx } -> {
          let key, transfer_logic_script <- with_key_and_transfer_logic(
            get_registry_node(node_idx),
          )

          // Validate the node's key matches the currency symbol
          expect key == policy

          // Validate the transfer logic script is invoked
          expect has_withdrawal(transfer_logic_script)

          input_value
        }

        TokenDoesNotExist { node_idx } -> {
          let key, next <- with_key_and_next_key(get_registry_node(node_idx))

          // Validate the node covers the currency symbol (node.key < policy < node.next)
          expect less_than_bytearray(key, policy)
          expect less_than_bytearray(policy, next)

          expect head_input_tokens: Pairs<AssetName, Data> = head_input_tokens

          list.reduce(
            head_input_tokens,
            input_value,
            fn(value, Pair(token, _)) {
              builtin.insert_value(policy, token, 0, value)
            },
          )
        }
      }

      verify_proofs(
        get_registry_node,
        has_withdrawal,
        unsafe_list.expect_tail(proofs),
        input_value,
        tail_input_assets,
        return,
      )
    }
  }
}
