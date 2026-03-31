//// Utility functions for CIP-0143 validators
//// Migrated from various Plutarch utility modules

use aiken/builtin.{tail_list}
use aiken/collection/dict
use cardano/assets.{PolicyId, Value}
use cardano/transaction.{InlineDatum, Output}

/// Get the datum from an output, expecting an inline datum
pub fn expect_inline_datum(output: Output) -> Data {
  expect InlineDatum(d) = output.datum
  d
}

/// Check if a currency symbol is present in a value. Fail loudly if missing
pub fn has_currency_symbol(haystack: Value, needle: PolicyId) -> Bool {
  // Fast skip first pair which is always ada
  let haystack = haystack |> assets.to_dict |> dict.to_pairs |> tail_list
  do_has_currency_symbol(haystack, needle)
}

fn do_has_currency_symbol(
  haystack: List<Pair<PolicyId, a>>,
  needle: PolicyId,
) -> Bool {
  when haystack is {
    [] -> False
    [Pair(head, _), ..tail] ->
      head == needle || do_has_currency_symbol(tail, needle)
  }
}

/// Count unique tokens in a value (number of distinct currency symbol + token name pairs)
pub fn count_unique_tokens(value: Value) -> Int {
  assets.reduce(value, 0, fn(_policy, _name, _amount, acc) { acc + 1 })
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
  expect Some(assets_minted_amount) =
    assets.to_dict(mint_value) |> dict.get(cs_to_insert)
  expect [Pair(_, amount)] = dict.to_pairs(assets_minted_amount)
  expect amount > 0

  // Check 2: The computed policy ID must match the currency symbol being inserted
  let computed_cs = apply_hashed_parameter(prefix, postfix, hashed_param)
  computed_cs == cs_to_insert
}
