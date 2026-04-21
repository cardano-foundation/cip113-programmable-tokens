use aiken/builtin.{equals_bytearray}
use aiken/collection/dict.{Dict}
use aiken/collection/dict/strategy as dict_strategy
use cardano/assets.{AssetName}
use pairs.{pop_until}

pub type Tokens =
  Dict<AssetName, Int>

/// /!\ PRE-CONDITION /!\
/// Given pairs are assumed to be well-formed and semantically 'correct'. That
/// is, keys contain no duplicates and are in ascending order.
///
/// In practice, this means we suppose both values have been constructed from
/// existing well-formed Values.
pub fn contains(
  superset: Pairs<AssetName, Int>,
  subset: Pairs<AssetName, Int>,
) -> Bool {
  when subset is {
    [] -> True
    [head_subset, ..tail_subset] -> {
      let
        head_superset,
        tail_superset,
      <- pop_until(superset, equals_bytearray(head_subset.1st, _))
      and {
        head_superset >= head_subset.2nd,
        contains(tail_superset, tail_subset),
      }
    }
  }
}

/// Merge two token maps by summing quantities per token name.
pub fn union(left: Tokens, right: Tokens) -> Dict<AssetName, Int> {
  dict.union_with(left, right, dict_strategy.sum_if_non_zero())
}
