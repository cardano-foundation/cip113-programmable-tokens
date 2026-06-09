//// Unit tests for utility functions

use aiken/collection/dict
use aiken/collection/list
use cardano/assets.{
  PolicyId, Value, ada_asset_name, ada_policy_id, add, from_asset, zero,
}
use utils.{
  bytearray_lt, count_unique_tokens, has_currency_symbol, mint_has_policy,
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

  let value = zero
    |> add(ada_policy_id, ada_asset_name, 1000000)
    |> add(cs1, #"746f6b656e31", 100)
    |> add(cs2, #"746f6b656e32", 200)

  count_unique_tokens(value) == 3
}

// Test has_currency_symbol
test has_currency_symbol_present() {
  let cs = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let value = from_asset(cs, #"746f6b656e", 100)
    |> add(ada_policy_id, ada_asset_name, 1000000)
  has_currency_symbol(value, cs)
}

// Test has_currency_symbol absent
test has_currency_symbol_absent() fail {
  let cs1 = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let cs2 = #"1112131415161718191a1b1c0d0e0f0102030405060708090a0b0c0d"
  let value = from_asset(cs1, #"746f6b656e", 100)
    |> add(ada_policy_id, ada_asset_name, 1000000)

  has_currency_symbol(value, cs2)
}

// ============================================================================
// Benchmarks — cheapest way to assert "(no) tokens of policy `cs` minted"
//
// Motivation: `is_programmable_token_minted` and `is_no_programmable_tokens_minted`
// (lib/utils.ak) check overlapping conditions on `tx.mint`. If one approach is
// strictly cheaper than another we could unify them into a single primitive
// and negate the result for the inverse case.
//
// Cardano-stdlib doc on `assets.tokens` notes: there is NEVER any lovelace
// in `tx.mint`. So `utils.has_currency_symbol` (which assumes the first
// dict entry is Ada and skips it) would be unsafe here — it would miss the
// first policy. Excluded from benchmarks; mentioned for completeness.
//
// Each test calls ONE approach on ONE realistic mint shape:
//   * case_a_mint() — Mode A (RegisterOnly): only the registry NFT minted.
//   * case_b_mint() — Mode B (RegisterAndMint): registry NFT + one
//     programmable token under `bench_key`.
//
// All tests check the SAME question: does `tx.mint` contain any entry
// under policy `bench_key`? Run `aiken check` and compare the
// `execution_units` per test in the JSON output. Note that `cardano/assets.tokens`
// uses `self.inner |> dict.get_or_else(_, _, dict.empty)` internally, so
// approaches 3 and 4 are likely close in cost.
// ============================================================================

const bench_registry_policy: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const bench_key: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

/// Mode A (RegisterOnly): only the registry NFT is minted.
fn case_a_mint() -> Value {
  zero |> add(bench_registry_policy, bench_key, 1)
}

/// Mode B (RegisterAndMint): registry NFT + one programmable token of `bench_key`.
fn case_b_mint() -> Value {
  zero
    |> add(bench_registry_policy, bench_key, 1)
    |> add(bench_key, #"746f6b656e", 100)
}

// ── Approach 1: assets.tokens |> dict.is_empty ─────────────────────────────
// Uses stdlib's `dict.get_or_else` internally (returns `dict.empty` for
// absent policies), then `dict.is_empty` on the inner dict.

test bench_a1_tokens_is_empty_case_a() {
  dict.is_empty(assets.tokens(case_a_mint(), bench_key))
}

test bench_a1_tokens_is_empty_case_b() {
  !dict.is_empty(assets.tokens(case_b_mint(), bench_key))
}

// ── Approach 2 (WINNER, now `mint_has_policy`): dict.has_key ──────────
// Direct outer-dict membership query, no inner-dict materialisation. This
// is the implementation chosen for `mint_has_policy` in lib/utils.ak —
// cheapest in both directions per the benchmark run.

test bench_a2_has_key_case_a() {
  !mint_has_policy(case_a_mint(), bench_key)
}

test bench_a2_has_key_case_b() {
  mint_has_policy(case_b_mint(), bench_key)
}

// ── Approach 3 (other): assets.policies |> list.has ────────────────────────
// Materialises the policy list, then linear-search. Most expensive of the
// boolean-returning alternatives — included as an upper-bound reference.

test bench_a3_policies_list_has_case_a() {
  !list.has(assets.policies(case_a_mint()), bench_key)
}

test bench_a3_policies_list_has_case_b() {
  list.has(assets.policies(case_b_mint()), bench_key)
}
// Note on previously-benchmarked approaches:
//   * The original `is_programmable_token_minted` (used `expect Some(_)` +
//     inner-dict iteration for `> 0`) was the most expensive in the
//     "present" case (38K mem / 10M cpu) and had no clean boolean branch
//     for absence — it fails loudly. Replaced by `mint_has_policy`.
//   * `is_no_programmable_tokens_minted` (used `dict.get` + pattern match)
//     was ~14% more expensive than `dict.has_key`. Replaced by
//     `!mint_has_policy`.
//   * `utils.has_currency_symbol` was excluded because its skip-first-as-Ada
//     optimisation misfires on `tx.mint` (which never contains Ada).
