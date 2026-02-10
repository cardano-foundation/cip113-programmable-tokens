//// Utility functions for CIP-0143 validators
//// Migrated from various Plutarch utility modules

use aiken/builtin.{head_list, tail_list}
use aiken/collection/dict.{Dict}
use aiken/collection/dict/strategy as dict_strategy
use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId, Value, flatten, quantity_of}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}

/// Check if a value contains at least the required amount of a specific asset
pub fn value_contains(value: Value, required: Value) -> Bool {
  list.all(
    flatten(required),
    fn(asset) {
      let (policy, name, req_qty) = asset
      quantity_of(value, policy, name) >= req_qty
    },
  )
}

// Is there any chance values have same assets.....
pub fn value_contains_v2(value: Value, required: Value) -> Bool {
  assets.reduce(
    required,
    True,
    fn(policy, name, req_qty, acc) {
      acc && quantity_of(value, policy, name) >= req_qty
    },
  )
}

// Is there any chance values have same assets.....
pub fn expect_value_contains_v3(value: RawValue, required: Value) -> Void {
  assets.reduce(
    required,
    Void,
    fn(policy, name, req_qty, _acc) {
      let qty =
        value
          |> dict.get_or_else(policy, fn() { fail })
          |> dict.get_or_else(name, fn() { fail })
      expect qty >= req_qty
    },
  )
}

/// Get the datum from an output, expecting an inline datum
pub fn expect_inline_datum(output: Output) -> Data {
  expect InlineDatum(d) = output.datum
  d
}

/// Find an input by a predicate
pub fn find_input(
  inputs: List<Input>,
  predicate: fn(Input) -> Bool,
) -> Option<Input> {
  list.find(inputs, predicate)
}

/// Must find an input by predicate (fails if not found)
pub fn must_find_input(
  inputs: List<Input>,
  predicate: fn(Input) -> Bool,
) -> Input {
  when find_input(inputs, predicate) is {
    Some(input) -> input
    None -> fail @"Required input not found"
  }
}

/// Check if a currency symbol is present in a value
pub fn has_currency_symbol(haystack: Value, needle: PolicyId) -> Bool {
  // Fast skip first pair which is always ada
  let haystack = haystack |> assets.to_dict |> dict.to_pairs |> tail_list
  do_has_currency_symbol(haystack, needle)
}

fn do_has_currency_symbol(
  haystack: List<Pair<PolicyId, a>>,
  needle: PolicyId,
) -> Bool {
  let Pair(candidate, _) = head_list(haystack)
  candidate == needle || do_has_currency_symbol(tail_list(haystack), needle)
}

/// Count unique tokens in a value (number of distinct currency symbol + token name pairs)
pub fn count_unique_tokens(value: Value) -> Int {
  // Original
  // flatten(value) |> list.length
  assets.reduce(value, 0, fn(_policy, _name, _amount, acc) { acc + 1 })
}

/// Get all outputs paying to a specific credential
pub fn outputs_at_credential(
  outputs: List<Output>,
  cred: Credential,
) -> List<Output> {
  list.filter(outputs, fn(output) { output.address.payment_credential == cred })
}

/// Get all inputs spending from a specific credential
pub fn inputs_from_credential(
  inputs: List<Input>,
  cred: Credential,
) -> List<Input> {
  list.filter(
    inputs,
    fn(input) { input.output.address.payment_credential == cred },
  )
}

/// Count inputs from a specific credential
pub fn count_inputs_from_credential(
  inputs: List<Input>,
  cred: Credential,
) -> Int {
  inputs_from_credential(inputs, cred) |> list.length
}

/// Check if a transaction is signed by a public key hash
pub fn is_signed_by(tx: Transaction, pkh: ByteArray) -> Bool {
  list.any(tx.extra_signatories, fn(sig) { sig == pkh })
}

/// Check if a script is invoked (via withdrawal)
pub fn is_script_invoked(tx: Transaction, script_cred: Credential) -> Bool {
  list.any(
    tx.withdrawals,
    fn(withdrawal) {
      let Pair(cred, _amount) = withdrawal
      cred == script_cred
    },
  )
}

/// Get element at index from a list
pub fn elem_at(lst: List<a>, idx: Int) -> a {
  when list.drop(lst, idx) is {
    [elem, ..] -> elem
    [] -> fail @"Index out of bounds"
  }
}

/// Check if a bytearray is lexicographically less than another
pub fn bytearray_lt(a: ByteArray, b: ByteArray) -> Bool {
  builtin.less_than_bytearray(a, b)
}

/// Apply hashed parameter to prefix and postfix to compute policy ID
/// This reconstructs the minting policy script and hashes it to get the currency symbol
/// Follows Plutus V3 script format: version_header + prefix + serialized_param + postfix
pub fn apply_hashed_parameter(
  prefix: ByteArray,
  postfix: ByteArray,
  hashed_param: ByteArray,
) -> ByteArray {
  // Plutus V3 version header: most significant first encoding of version 3
  let version_header = #"03"

  // Build the script: version + prefix + serialized_param + postfix
  let script_bytes =
    builtin.append_bytearray(
      version_header,
      builtin.append_bytearray(
        prefix,
        builtin.append_bytearray(hashed_param, postfix),
      ),
    )

  // Hash with blake2b_224 to get the policy ID (28 bytes)
  builtin.blake2b_224(script_bytes)
}

/// Check if a currency symbol is a valid programmable token registration
/// Validates that:
/// 1. Tokens with this policy ID are being minted in the transaction
/// 2. The computed policy ID (from prefix + hashed_param + postfix) matches the currency symbol
pub fn is_programmable_token_registration(
  cs_to_insert: ByteArray,
  prefix: ByteArray,
  postfix: ByteArray,
  hashed_param: ByteArray,
  mint_value: Value,
) -> Bool {
  // Check 1: The policy must be minting tokens in this transaction
  let has_minting =
    list.any(
      flatten(mint_value),
      fn(asset) {
        let (policy, _tn, amt) = asset
        policy == cs_to_insert && amt > 0
      },
    )

  // Check 2: The computed policy ID must match the currency symbol being inserted
  let computed_cs = apply_hashed_parameter(prefix, postfix, hashed_param)
  let cs_matches = computed_cs == cs_to_insert

  has_minting? && cs_matches?
}

/// Search a specific key in an associative list, and fail if not found.
pub fn expect_key(
  haystack: List<Pair<Credential, a>>,
  needle: Credential,
) -> Bool {
  head_list(haystack).1st == needle || expect_key(tail_list(haystack), needle)
}

// A faster version of assets.merge that is specialized to positive values
// (typically found in outputs). This allows to bypass the null check on value
// since quantities can only ever increase.
//
// The function handles recurses over a list or input-like objects, and let the
// caller select whether to add an output or not.
pub fn sum_output_values(
  elems: List<i>,
  strategy: fn(i, fn(Output) -> RawValue, fn() -> RawValue) -> RawValue,
) -> RawValue {
  do_sum_output_values(elems, strategy, dict.empty)
}

pub type RawValue =
  Dict<PolicyId, Dict<AssetName, Int>>

fn do_sum_output_values(
  elems: List<i>,
  strategy: fn(i, fn(Output) -> RawValue, fn() -> RawValue) -> RawValue,
  sum: RawValue,
) -> RawValue {
  when elems is {
    [] -> sum
    [head, ..tail] ->
      do_sum_output_values(
        tail,
        strategy,
        strategy(
          head,
          // Output is selected
          fn(output) {
            output.value
              |> assets.to_dict
              |> dict.union_with(
                  sum,
                  _,
                  fn(_, left, right, keep, _discard) {
                    keep(dict.union_with(left, right, dict_strategy.sum()))
                  },
                )
          },
          // Output is discarded
          fn() { sum },
        ),
      )
  }
}
