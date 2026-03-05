//// Unit tests for utility functions

use aiken/collection/dict
use cardano/address.{from_verification_key}
use cardano/assets.{
  AssetName, ada_asset_name, ada_policy_id, add, from_asset, zero,
}
use cardano/transaction.{NoDatum, Output}
use utils.{
  bytearray_lt, count_unique_tokens, has_currency_symbol, has_signatory,
  sum_output_assets, tokens_contains,
}

// Test bytearray_lt with different bytearrays
test bytearray_lt_works() {
  bytearray_lt(#"00", #"01") && bytearray_lt(#"aa", #"ab") && !bytearray_lt(
    #"ff",
    #"00",
  ) && !bytearray_lt(#"aa", #"aa")
}

// Test bytearray_lt with empty bytearrays
test bytearray_lt_empty() {
  bytearray_lt(#"", #"01") && !bytearray_lt(#"01", #"")
}

// Test count_unique_tokens with Ada only
test count_unique_tokens_ada_only() {
  let value = from_asset(ada_policy_id, ada_asset_name, 1000000)
  count_unique_tokens(value) == 1
}

// Test count_unique_tokens with multiple tokens
test count_unique_tokens_multiple() {
  let cs1 = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let cs2 = #"1112131415161718191a1b1c0d0e0f0102030405060708090a0b0c0d"

  let value =
    zero
      |> add(ada_policy_id, ada_asset_name, 1000000)
      |> add(cs1, #"746f6b656e31", 100)
      |> add(cs2, #"746f6b656e32", 200)

  count_unique_tokens(value) == 3
}

// Test has_currency_symbol
test has_currency_symbol_present() {
  let cs = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let value =
    from_asset(cs, #"746f6b656e", 100)
      |> add(ada_policy_id, ada_asset_name, 1000000)
  has_currency_symbol(value, cs)
}

// Test has_currency_symbol absent
test has_currency_symbol_absent() fail {
  let cs1 = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let cs2 = #"1112131415161718191a1b1c0d0e0f0102030405060708090a0b0c0d"
  let value =
    from_asset(cs1, #"746f6b656e", 100)
      |> add(ada_policy_id, ada_asset_name, 1000000)

  has_currency_symbol(value, cs2)
}

const fixture_tokens_contains_asset_name: AssetName = #"746f6b656e"

const fixture_tokens_contains_superset: Pairs<AssetName, Int> =
  dict.empty
    |> dict.insert(fixture_tokens_contains_asset_name, 100)
    |> dict.to_pairs

const fixture_tokens_contains_superset_with_ada: Pairs<AssetName, Int> =
  dict.empty
    |> dict.insert(fixture_tokens_contains_asset_name, 100)
    |> dict.to_pairs

const fixture_tokens_contains_subset: Pairs<AssetName, Int> =
  dict.empty
    |> dict.insert(fixture_tokens_contains_asset_name, 50)
    |> dict.to_pairs

// Test 'tokens_contains' with exact match
test tokens_contains_exact_match() {
  tokens_contains(
    fixture_tokens_contains_superset,
    fixture_tokens_contains_superset,
  )
}

// Test 'tokens_contains' with subset
test tokens_contains_subset() {
  and {
    tokens_contains(
      fixture_tokens_contains_superset,
      fixture_tokens_contains_subset,
    )?,
    tokens_contains(
      fixture_tokens_contains_superset_with_ada,
      fixture_tokens_contains_subset,
    )?,
  }
}

// Test 'tokens_contains' with insufficient funds
test tokens_contains_insufficient() {
  !tokens_contains(
    fixture_tokens_contains_subset,
    fixture_tokens_contains_superset,
  )
}

// Test has_signatory
test has_signatory_present() {
  let vkh = #"aabbccdd"
  has_signatory([vkh], vkh)
}

// Test has_signatory absent
test has_signatory_absent() fail {
  let vkh1 = #"aabbccdd"
  let vkh2 = #"ddeeff00"
  has_signatory([vkh1], vkh2)
}

const output_placeholder =
  Output {
    address: from_verification_key(
      #"00000000000000000000000000000000000000000000000000000000",
    ),
    value: assets.zero,
    datum: NoDatum,
    reference_script: None,
  }

test sum_output_assets_many_assets() {
  let out1 =
    Output {
      ..output_placeholder,
      value: assets.zero
        |> assets.add("", "", 42)
        |> assets.add("foo", "bar", 1),
    }

  let out2 =
    Output {
      ..output_placeholder,
      value: assets.zero
        |> assets.add("", "", 1337)
        |> assets.add("foo", "bar", 1)
        |> assets.add("baz", "", 1),
    }

  let out3 =
    Output {
      ..output_placeholder,
      value: assets.zero
        |> assets.add("", "", 14)
        |> assets.add("bar", "foo", 1),
    }

  let expected =
    assets.zero
      |> assets.add("bar", "foo", 1)
      |> assets.add("baz", "", 1)
      |> assets.add("foo", "bar", 2)
      |> assets.to_dict

  sum_output_assets(
    [out1, out2, out3],
    dict.empty,
    fn(o, keep, _discard) { keep(o) },
  ) == expected
}

test sum_output_assets_mixed_mint_and_output() {
  let mint =
    assets.zero
      |> assets.add("foo", "bar", 1)
      |> assets.to_dict

  let output_value =
    Output {
      ..output_placeholder,
      value: assets.zero
        |> assets.add("", "", 1337)
        |> assets.add("foo", "bar", 1),
    }

  let expected =
    assets.zero
      |> assets.add("foo", "bar", 2)
      |> assets.to_dict

  sum_output_assets([output_value], mint, fn(o, keep, _discard) { keep(o) }) == expected
}
