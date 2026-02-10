// Unit tests for utility functions
use aiken/collection/dict.{Dict}
use aiken/interval
use cardano/assets.{
  AssetName, PolicyId, ada_asset_name, ada_policy_id, add, from_asset, zero,
}
use cardano/transaction.{Transaction}
use utils.{
  bytearray_lt, count_unique_tokens, has_currency_symbol, is_signed_by,
  value_contains,
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

const fixture_value_contains_policy_id: PolicyId =
  #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"

const fixture_value_contains_asset_name: AssetName = #"746f6b656e"

const fixture_value_contains_superset: Pairs<PolicyId, Dict<AssetName, Int>> =
  from_asset(
    fixture_value_contains_policy_id,
    fixture_value_contains_asset_name,
    100,
  )
    |> assets.to_dict
    |> dict.to_pairs

const fixture_value_contains_superset_with_ada: Pairs<
    PolicyId,
    Dict<AssetName, Int>,
  > =
  from_asset(
    fixture_value_contains_policy_id,
    fixture_value_contains_asset_name,
    100,
  )
    |> assets.add(ada_policy_id, ada_asset_name, 1234)
    |> assets.to_dict
    |> dict.to_pairs

const fixture_value_contains_subset: Pairs<PolicyId, Dict<AssetName, Int>> =
  from_asset(
    fixture_value_contains_policy_id,
    fixture_value_contains_asset_name,
    50,
  )
    |> assets.to_dict
    |> dict.to_pairs

// Test 'value_contains' with exact match
test value_contains_exact_match() {
  value_contains(
    fixture_value_contains_superset,
    fixture_value_contains_superset,
  )
}

// Test 'value_contains' with subset
test value_contains_subset() {
  and {
    value_contains(
      fixture_value_contains_superset,
      fixture_value_contains_subset,
    )?,
    value_contains(
      fixture_value_contains_superset_with_ada,
      fixture_value_contains_subset,
    )?,
  }
}

// Test 'value_contains' with insufficient funds
test value_contains_insufficient() {
  !value_contains(
    fixture_value_contains_subset,
    fixture_value_contains_superset,
  )
}

// Test is_signed_by
test is_signed_by_present() {
  let pkh = #"aabbccdd"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: zero,
      certificates: [],
      withdrawals: [],
      validity_range: interval.everything,
      extra_signatories: [pkh],
      redeemers: [],
      datums: dict.empty,
      id: #"00",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }

  is_signed_by(tx, pkh)
}

// Test is_signed_by absent
test is_signed_by_absent() {
  let pkh1 = #"aabbccdd"
  let pkh2 = #"ddeeff00"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: zero,
      certificates: [],
      withdrawals: [],
      validity_range: interval.everything,
      extra_signatories: [pkh1],
      redeemers: [],
      datums: dict.empty,
      id: #"00",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }

  !is_signed_by(tx, pkh2)
}
