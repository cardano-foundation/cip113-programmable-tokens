//// Utility functions for CIP-0143 validators
//// Migrated from various Plutarch utility modules

use aiken/builtin.{head_list, tail_list}
use aiken/collection/dict.{Dict}
use aiken/collection/dict/strategy as dict_strategy
use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId, Value, ada_policy_id, flatten}
use cardano/transaction.{InlineDatum, Input, Output}

pub type RawValue =
  Dict<PolicyId, Dict<AssetName, Int>>

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
  let Pair(candidate, _) = head_list(haystack)
  candidate == needle || do_has_currency_symbol(tail_list(haystack), needle)
}

/// Count unique tokens in a value (number of distinct currency symbol + token name pairs)
pub fn count_unique_tokens(value: Value) -> Int {
  assets.reduce(value, 0, fn(_policy, _name, _amount, acc) { acc + 1 })
}

/// Check if a transaction is signed by a public key hash. Fails loudly otherwise.
pub fn has_signatory(
  signatories: List<VerificationKeyHash>,
  vkh: VerificationKeyHash,
) -> Bool {
  head_list(signatories) == vkh || has_signatory(tail_list(signatories), vkh)
}

/// Get element at index from a list
pub fn elem_at(lst: List<a>, idx: Int) -> a {
  if idx >= 2 {
    elem_at(tail_list(tail_list(lst)), idx - 2)
  } else if idx >= 1 {
    elem_at(tail_list(lst), idx - 1)
  } else {
    head_list(lst)
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
pub fn has_key(haystack: List<Pair<Credential, a>>, needle: Credential) -> Bool {
  head_list(haystack).1st == needle || has_key(tail_list(haystack), needle)
}

/// A faster version of assets.merge that is specialized to positive values
/// (typically found in outputs). This allows to bypass the null check on value
/// since quantities can only ever increase.
///
/// The function handles recurses over a list or input-like objects, and let the
/// caller select whether to add an output or not.
///
/// ## Example
///
/// ```aiken
/// sum_output_values(
///   self.inputs,
///   fn(input, select, discard) {
///     let output = input.output
///     if output.address.payment_credential == needle {
///       select(output)
///     } else {
///       discard()
///     }
///   },
/// )
/// ```
pub fn sum_output_values(
  elems: List<i>,
  strategy: fn(i, fn(Output) -> RawValue, fn() -> RawValue) -> RawValue,
) -> RawValue {
  do_sum_output_values(elems, strategy, dict.empty)
}

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

/// Compare two 'RawValue' to check if they have matchings assets.
pub fn match_assets(left: RawValue, right: RawValue) -> Bool {
  let without_lovelace =
    fn(pairs: Pairs<PolicyId, Dict<AssetName, Int>>) {
      if head_list(pairs).1st == ada_policy_id {
        tail_list(pairs)
      } else {
        pairs
      }
    }

  let left_assets = without_lovelace(dict.to_pairs(left))
  let right_assets = without_lovelace(dict.to_pairs(right))

  left_assets == right_assets
}

/// A fast check for inclusion of a value inside another. It checks if the
/// first value contains all the tokens of the second value and the quantities
/// of the tokens in the first value are greater than or equal to the quantities
/// of the tokens in the second value.
///
/// /!\ PRE-CONDITION /!\
/// Given pairs are assumed to be well-formed and semantically 'correct'. That
/// is, keys contain no duplicates and are in ascending order.
///
/// In practice, this means we suppose both values have been constructed from
/// existing well-formed Values.
pub fn value_contains(
  superset: Pairs<PolicyId, Dict<AssetName, Int>>,
  subset: Pairs<PolicyId, Dict<AssetName, Int>>,
) -> Bool {
  when subset is {
    [] -> True
    [head_subset, ..tail_subset] -> {
      let head_superset, tail_superset <- drop_until(superset, head_subset.1st)
      and {
        token_contains(
          dict.to_pairs(head_superset),
          dict.to_pairs(head_subset.2nd),
        ),
        value_contains(tail_subset, tail_superset),
      }
    }
  }
}

fn token_contains(
  superset: Pairs<AssetName, Int>,
  subset: Pairs<AssetName, Int>,
) -> Bool {
  when subset is {
    [] -> True
    [head_subset, ..tail_subset] -> {
      let head_superset, tail_superset <- drop_until(superset, head_subset.1st)
      and {
        head_superset >= head_subset.2nd,
        token_contains(tail_superset, tail_subset),
      }
    }
  }
}

fn drop_until(
  self: Pairs<ByteArray, v>,
  until: ByteArray,
  return: fn(v, Pairs<ByteArray, v>) -> result,
) -> result {
  let head = head_list(self)
  if head.1st == until {
    return(head.2nd, tail_list(self))
  } else {
    drop_until(tail_list(self), until, return)
  }
}
