// Unit tests for utility functions
use aiken/collection/dict
use aiken/interval
use cardano/assets.{ada_asset_name, ada_policy_id, add, from_asset, zero}
use cardano/transaction.{Transaction}
use utils.{
  bytearray_lt, count_unique_tokens, has_currency_symbol, is_signed_by,
  match_assets,
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

// Test 'match_assets' with exact match
test match_exact() {
  let cs = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let value =
    from_asset(cs, #"746f6b656e", 100)
      |> assets.to_dict

  match_assets(value, value)
}

// Test 'match_assets' with more an ada mismatch
test match_more_lovelace() {
  let cs = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let in =
    from_asset(cs, #"746f6b656e", 100)
      |> add(ada_policy_id, ada_asset_name, 1234)
      |> assets.to_dict
  let out =
    from_asset(cs, #"746f6b656e", 100)
      |> add(ada_policy_id, ada_asset_name, 4321)
      |> assets.to_dict

  and {
    match_assets(in, out),
    match_assets(out, in),
  }
}

// Test 'match_assets' with non-matching assets
test match_less_lovelace() {
  let cs = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let in =
    from_asset(cs, #"746f6b656e", 50)
      |> assets.to_dict
  let out =
    from_asset(cs, #"746f6b656e", 100)
      |> assets.to_dict

  and {
    !match_assets(in, out),
    !match_assets(out, in),
  }
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
