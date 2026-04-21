use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/fuzz
use aiken/primitive/bytearray
use cardano/assets.{AssetName}
use cardano/fuzz as cardano
use tokens.{Tokens}

// -------------------------------------------------------------- fuzzers

fn any_tokens() -> Fuzzer<Tokens> {
  let tokens <- fuzz.map(fuzz.list_between(any_token(), 0, 3))
  dict.from_pairs(tokens)
}

fn any_token() -> Fuzzer<Pair<AssetName, Int>> {
  let asset_name <- fuzz.and_then(cardano.asset_name())
  let quantity <- fuzz.map(fuzz.int_between(0, 3))
  Pair(asset_name, quantity)
}

fn any_mutation() -> Fuzzer<Mutation> {
  let ix <- fuzz.and_then(fuzz.byte())
  let quantity <- fuzz.and_then(fuzz.int_between(1, 3))
  let name <- fuzz.and_then(cardano.asset_name())
  fuzz.one_of(
    [
      ReduceQuantity(ix, quantity),
      IncreaseQuantity(ix, quantity),
      InsertAsset(Pair(name, quantity)),
      DeleteAsset(ix),
    ],
  )
}

type Mutation {
  ReduceQuantity(Int, Int)
  IncreaseQuantity(Int, Int)
  InsertAsset(Pair<AssetName, Int>)
  DeleteAsset(Int)
}

// Invariant: assume 'tokens' is not empty.
fn apply_mutation(mutation: Mutation, pairs: Pairs<AssetName, Int>) {
  let len = list.length(pairs)
  when mutation is {
    ReduceQuantity(ix, n) | IncreaseQuantity(ix, n) -> {
      let prefix = list.take(pairs, ix % len)
      expect [Pair(name, quantity), ..tail] = list.drop(pairs, ix % len)
      let new_quantity =
        if mutation == ReduceQuantity(ix, n) {
          quantity - n
        } else {
          quantity + n
        }
      list.concat(prefix, [Pair(name, new_quantity), ..tail])
    }
    InsertAsset(Pair(name, quantity)) ->
      pairs.insert_with_by_ascending_key(
        pairs,
        name,
        quantity,
        bytearray.compare,
        fn(left, right) { left + right },
      )
    DeleteAsset(ix) -> {
      let prefix = list.take(pairs, ix % len)
      expect [_, ..tail] = list.drop(pairs, ix % len)
      list.concat(prefix, tail)
    }
  }
}

// ------------------------------------------------------------- contains

const fixture_asset_name: AssetName = #"746f6b656e"

const fixture_superset: Pairs<AssetName, Int> = [Pair(fixture_asset_name, 100)]

const fixture_superset_with_ada: Pairs<AssetName, Int> =
  [Pair(fixture_asset_name, 100)]

const fixture_subset: Pairs<AssetName, Int> = [Pair(fixture_asset_name, 50)]

test tokens_exact_match() {
  tokens.contains(fixture_superset, fixture_superset)
}

test tokens_subset() {
  and {
    tokens.contains(fixture_superset, fixture_subset)?,
    tokens.contains(fixture_superset_with_ada, fixture_subset)?,
  }
}

test tokens_insufficient() {
  !tokens.contains(fixture_subset, fixture_superset)
}

test prop_contains_reflexive(tokens via any_tokens()) {
  tokens.contains(dict.to_pairs(tokens), dict.to_pairs(tokens))
}

test prop_contains_monoid(tokens via any_tokens()) {
  tokens.contains(dict.to_pairs(tokens), [])
}

test prop_contains_subset_mutation(
  (superset, mutation) via fuzz.both(any_tokens(), any_mutation()),
) fail {
  let superset = dict.to_pairs(superset)
  if superset != [] {
    let subset = apply_mutation(mutation, superset)
    when mutation is {
      IncreaseQuantity(..) -> {
        fuzz.label(@"non-empty superset, increase quantity")
        tokens.contains(superset, subset)
      }
      InsertAsset(..) -> {
        fuzz.label(@"non-empty superset, insert new asset")
        tokens.contains(superset, subset)
      }
      ReduceQuantity(..) -> {
        fuzz.label(@"non-empty superset, reduce quantity")
        !tokens.contains(superset, subset)
      }
      DeleteAsset(..) -> {
        fuzz.label(@"non-empty superset, remove asset")
        !tokens.contains(superset, subset)
      }
    }
  } else {
    fuzz.label(@"empty superset, skipped")
    False
  }
}

test prop_contains_superset_mutation(
  (subset, mutation) via fuzz.both(any_tokens(), any_mutation()),
) fail {
  let subset = dict.to_pairs(subset)
  if subset != [] {
    let superset = apply_mutation(mutation, subset)
    when mutation is {
      IncreaseQuantity(..) -> {
        fuzz.label(@"non-empty subset, increase quantity")
        !tokens.contains(superset, subset)
      }
      InsertAsset(..) -> {
        fuzz.label(@"non-empty subset, insert new asset")
        !tokens.contains(superset, subset)
      }
      ReduceQuantity(..) -> {
        fuzz.label(@"non-empty subset, reduce quantity")
        tokens.contains(superset, subset)
      }
      DeleteAsset(..) -> {
        fuzz.label(@"non-empty subset, remove asset")
        tokens.contains(superset, subset)
      }
    }
  } else {
    fuzz.label(@"empty subset, skipped")
    False
  }
}
