use aiken/collection/dict
use aiken/collection/list
use aiken/fuzz
use assets.{Assets}
use cardano/address
use cardano/assets.{AssetName, Value, ada_asset_name, ada_policy_id} as value
use cardano/fuzz as cardano
use cardano/transaction.{NoDatum, Output}

// ------------------------------------------------------------ Assets generator

/// A generator for assets.
fn any_assets(is_output: Bool) -> Fuzzer<Assets> {
  let policies <- fuzz.and_then(fuzz.list_between(cardano.policy_id(), 0, 3))
  let zero =
    if is_output {
      let quantity <- fuzz.map(fuzz.int_between(1, 3))
      dict.from_ascending_pairs(
        [
          Pair(
            ada_policy_id,
            dict.from_ascending_pairs([Pair(ada_asset_name, quantity)]),
          ),
        ],
      )
    } else {
      fuzz.constant(dict.empty)
    }
  list.foldr(
    policies,
    zero,
    fn(policy, step) {
      let assets <- fuzz.and_then(step)
      let lo =
        if is_output {
          0
        } else {
          1
        }
      let tokens <- fuzz.map(fuzz.list_between(any_token(is_output), lo, 3))
      dict.insert(assets, policy, dict.from_pairs(tokens))
    },
  )
    |> fuzz.map(dict.to_pairs)
}

/// A generator for a single token pair.
fn any_token(is_output: Bool) -> Fuzzer<Pair<AssetName, Int>> {
  let asset_name <- fuzz.and_then(cardano.asset_name())
  let quantity <-
    fuzz.map(
      if is_output {
        fuzz.int_between(1, 3)
      } else {
        fuzz.either(fuzz.int_between(-3, -1), fuzz.int_between(1, 3))
      },
    )
  Pair(asset_name, quantity)
}

// 1. Must have ADA
// 2. Policies must be in ascending orders
test prop_assets_generator_is_output_ok(assets via any_assets(True)) {
  // This gives us (2), without what 'from_pairs' crashes.
  let value = dict.from_pairs(assets)
  // This and below gives us (1)
  expect Some(tokens) = dict.get(value, ada_policy_id)
  expect [Pair(asset_name, quantity)] = dict.to_pairs(tokens)
  and {
    (asset_name == ada_asset_name)?,
    (quantity > 0)?,
  }
}

// 1. Must never have ADA
// 2. Policies must be in ascending orders
test prop_assets_generator_is_mint_ok(assets via any_assets(False)) {
  // This gives us (2), without what 'from_pairs' crashes.
  let value = dict.from_pairs(assets)
  // This and below gives us (1)
  expect None = dict.get(value, ada_policy_id)
}

test prop_assets_generator_is_mint_sometimes_empty(
  assets via any_assets(False),
) fail once {
  assets != []
}

test prop_assets_generator_is_output_never_empty(
  assets via any_assets(True),
) fail {
  assets == []
}

test prop_assets_generator_is_output_sometimes_ada_only(
  assets via any_assets(True),
) fail once {
  list.length(assets) > 1
}

// --------------------------------------------------------------------- collect

const output_placeholder =
  Output {
    address: address.from_verification_key(
      #"00000000000000000000000000000000000000000000000000000000",
    ),
    value: value.zero,
    datum: NoDatum,
    reference_script: None,
  }

fn all(o, keep, _discard) {
  keep(o)
}

test collect_many_assets() {
  let out1 =
    Output {
      ..output_placeholder,
      value: value.from_lovelace(42)
        |> value.add("foo", "bar", 1),
    }

  let out2 =
    Output {
      ..output_placeholder,
      value: value.from_lovelace(1337)
        |> value.add("foo", "bar", 1)
        |> value.add("baz", "", 1),
    }

  let out3 =
    Output {
      ..output_placeholder,
      value: value.from_lovelace(14)
        |> value.add("bar", "foo", 1),
    }

  let expected =
    value.zero
      |> value.add("bar", "foo", 1)
      |> value.add("baz", "", 1)
      |> value.add("foo", "bar", 2)
      |> assets.from_value

  assets.collect([out1, out2, out3], [], all) == expected
}

test collect_mixed_mint_and_output() {
  let mint =
    value.from_asset("foo", "bar", 1)
      |> assets.from_value

  let output_value =
    Output {
      ..output_placeholder,
      value: value.from_lovelace(1337)
        |> value.add("foo", "bar", 1),
    }

  let expected =
    value.from_asset("foo", "bar", 2)
      |> assets.from_value

  assets.collect([output_value], mint, all) == expected
}

test collect_and_filter() {
  let other_address =
    address.from_verification_key(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    )

  let out1 =
    Output {
      ..output_placeholder,
      value: value.from_lovelace(42) |> value.add("foo", "bar", 1),
    }

  let out2 =
    Output {
      ..output_placeholder,
      address: other_address,
      value: value.from_lovelace(1337)
        |> value.add("foo", "bar", 1),
    }

  let out3 =
    Output {
      ..output_placeholder,
      value: value.from_lovelace(1337)
        |> value.add("foo", "bar", 1),
    }

  let expected =
    value.from_asset("foo", "bar", 2)
      |> assets.from_value

  expected == assets.collect(
    [out1, out2, out3],
    [],
    fn(o, keep, discard) {
      if o.address == other_address {
        discard()
      } else {
        keep(o)
      }
    },
  )
}

test collect_keeps_null_policies() {
  let out =
    Output {
      ..output_placeholder,
      value: value.from_lovelace(42) |> value.add("foo", "bar", 1),
    }

  let mint = value.from_asset("foo", "bar", -1) |> assets.from_value

  let expected = [Pair("foo", dict.empty)]

  expected == assets.collect([out], mint, all)
}

test prop_collect_never_contains_ada(
  (zero, values) via fuzz.both(
    any_assets(False),
    fuzz.list_between(any_assets(True), 0, 3),
  ),
) {
  assets.collect(
    list.map(
      values,
      fn(value) {
        Output { ..output_placeholder, value: assets_to_value(value) }
      },
    ),
    zero,
    all,
  )
    |> dict.from_pairs
    |> dict.get(ada_policy_id)
    |> fn(ada_tokens) { ada_tokens == None }
}

// ----------------------------------------------------------------------- union

test prop_union_preserve_ordering(
  (left, right) via fuzz.both(any_assets(False), any_assets(True)),
) {
  // 'from_pairs' explodes if the keys are no longer in ascending order.
  dict.from_pairs(assets.union(left, right)) != dict.empty
}

test prop_union_is_monoid(left_or_right via any_assets(True)) {
  assets.union(left_or_right, []) == assets.union([], left_or_right)
}

test prop_union_is_symmetric(
  (left, right) via fuzz.both(any_assets(False), any_assets(True)),
) {
  assets.union(left, right) == assets.union(right, left)
}

// ------------------------------------------------------------------ peek_first

test prop_peek_first(assets via any_assets(True)) {
  let value = assets_to_value(assets)
  if value.without_lovelace(value) == value.zero {
    fuzz.label(@"ada only (discarded)")
    True
  } else {
    fuzz.label(@"with assets (useful tests)")

    let output = Output { ..output_placeholder, value }

    expect [head, ..] = value |> value.without_lovelace |> value.policies

    assets.peek_first(output) == head
  }
}

test peek_first_no_tokens() fail {
  assets.peek_first(
    Output { ..output_placeholder, value: value.from_lovelace(42) },
  ) != ""
}

// -------------------------------------------------------------------- split_at

test prop_split_at_reify(
  (ix, assets) via fuzz.both(fuzz.int(), any_assets(True)),
) {
  let value = assets_to_value(assets)

  let policies = value.policies(value)
  expect Some(pivot) = list.at(policies, ix % list.length(policies))

  let before, at, after <- assets.split_at(value, pivot)
  let reified =
    assets_to_value(before)
      |> value.merge(value.from_asset_list([Pair(pivot, dict.to_pairs(at))]))
      |> value.merge(assets_to_value(after))

  if after == [] || before == [] {
    fuzz.label(@"before or after is empty")
  } else {
    fuzz.label(@"neither is empty")
  }

  value == reified
}

test prop_split_at_after_still_ordered(
  (ix, assets) via fuzz.both(fuzz.int(), any_assets(True)),
) {
  let value = assets_to_value(assets)

  let policies = value.policies(value)
  expect Some(pivot) = list.at(policies, ix % list.length(policies))

  let _, _, after <- assets.split_at(value, pivot)

  // ensures key are still ordered
  dict.from_pairs(after) == dict.empty || True
}

// --------------------------------------------------------------------- helpers

fn assets_to_value(self: Assets) -> Value {
  list.foldl(
    self,
    value.zero,
    fn(Pair(policy, tokens), acc) {
      dict.foldl(
        tokens,
        acc,
        fn(asset_name, quantity, acc) {
          value.add(acc, policy, asset_name, quantity)
        },
      )
    },
  )
}
