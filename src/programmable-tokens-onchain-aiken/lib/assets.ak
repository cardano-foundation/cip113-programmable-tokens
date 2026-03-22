use aiken/builtin.{less_than_bytearray, less_than_equals_bytearray}
use aiken/collection/dict
use aiken/collection/dict/strategy as dict_strategy
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Output}
use env
use list
use tokens.{Tokens}

pub type Assets =
  Pairs<PolicyId, Tokens>

pub type SumStrategy<i> =
  fn(i, fn(Output) -> Assets, fn() -> Assets) -> Assets

/// A Convenient helper to extract assets from values. Comes at no cost since it is usually inlined by the compiler.
pub fn from_value(self: Value) -> Assets {
  self |> assets.to_dict |> dict.to_pairs
}

/// Split an dictionnary at the given key. Returning the elements before (in reverse key order), the
/// value at the key, and the elements after (in same key order).
pub fn split_at(
  self: Value,
  at: PolicyId,
  return: fn(Assets, Tokens, Assets) -> result,
) -> result {
  do_split_at(from_value(self), at, [], return)
}

fn do_split_at(
  self: Assets,
  at: PolicyId,
  before: Assets,
  return: fn(Assets, Tokens, Assets) -> result,
) -> result {
  when self is {
    [] -> return(before, dict.empty, [])
    [Pair(k, _) as head, ..tail] ->
      if less_than_bytearray(k, at) {
        // Skip while keys are smaller (strictly) than searched key
        do_split_at(tail, at, [head, ..before], return)
      } else {
        if k == at {
          // Done searching, get the value and return the tail after
          return(before, head.2nd, tail)
        } else {
          // The head and tail are all after the key; no need to continue searching.
          return(before, dict.empty, self)
        }
      }
  }
}

/// Lookup the first asset policy from an output, or fails loudly if the output holds no tokens (beyond Ada).
pub fn peek_first(self: Output) -> PolicyId {
  list.head(list.tail(from_value(self.value))).1st
}

/// A faster version of assets.merge that preserves empty maps. This allows to
/// bypass the null check on value since quantities can only ever increase.
/// Importantly, it is also *necessary* to ensure that policies are retained in
/// the map for later validations even if they result in no outputs (e.g. a burn
/// fully compensate a spend).
///
/// It also focuses on assets and completely ignores Ada.
///
/// The function recurses over a list or input-like objects, and let the
/// caller select whether to add an output or not.
///
/// ## Example
///
/// ```aiken
/// collect(
///   self.inputs,
///   [],
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
///
/// /!\ PRE-CONDITION /!\
/// The given zero assets is expected to not contain any Ada. This is enforced
/// when assertions are enabled (`--env with_assertions`).
///
/// This is generally true when the initial zero is an empty list or coming
/// from the mint value.
pub fn collect(elems: List<i>, zero: Assets, strategy: SumStrategy<i>) -> Assets {
  do_collect(elems, strategy, env.assert_no_ada_policy(zero))
}

fn do_collect(elems: List<i>, strategy: SumStrategy<i>, sum: Assets) -> Assets {
  when elems is {
    [] -> sum
    [head, ..tail] ->
      do_collect(
        tail,
        strategy,
        strategy(
          head,
          // Output is selected
          fn(output) {
            output.value
              |> from_value
              // Drop ADA, guaranteed to be present in outputs.
              |> list.tail
              // NOTE: left-optimised union
              // The `union` consumes the left argument into the right argument. So it is
              // generally better to provide the smallest argument as left value. The `sum`
              // will generally grow as large as outputs and in many scenario will no be much
              // larger. However, it is very often smaller initially (often empty). Hence why
              // we force it as first argument here.
              |> union(sum, _)
          },
          // Output is discarded
          fn() { sum },
        ),
      )
  }
}

/// Merge two Assets by summing token quantities.
/// Used to combine validated input prog value with validated mint prog value.
pub fn union(left: Assets, right: Assets) -> Assets {
  when left is {
    [] -> right
    // NOTE: Preserving null assets
    // It is primordial here to not discard assets if even they result in an
    // empty dict. This is because the 'left' assets may have negative quantities
    // coming from burns. If a burn is fully cover by a spend, we must preserve
    // the key in the map to ensure that validations necessary to that policy
    // occur as expected.
    [Pair(k, v), ..rest] -> union(rest, do_insert(right, k, v))
  }
}

fn do_insert(self: Assets, k1: PolicyId, v1: Tokens) -> Assets {
  when self is {
    [] -> [Pair(k1, v1)]
    [Pair(k2, _) as head, ..rest] ->
      if less_than_equals_bytearray(k1, k2) {
        if k1 == k2 {
          [Pair(k1, tokens.union(v1, head.2nd)), ..rest]
        } else {
          [Pair(k1, v1), ..self]
        }
      } else {
        [head, ..do_insert(rest, k1, v1)]
      }
  }
}

pub fn has_policy_nft_strictly(
  value: Value,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Bool {
  expect Some(policy_assets) = assets.to_dict(value) |> dict.get(policy_id)
  expect [Pair(actual_asset_name, 1)] = dict.to_pairs(policy_assets)
  actual_asset_name == asset_name
}
