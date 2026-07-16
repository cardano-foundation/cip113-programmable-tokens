//// Utility functions for CIP-113 validators
//// Migrated from various Plutarch utility modules

use aiken/builtin.{tail_list}
use aiken/collection/dict
use cardano/address.{Credential, Script}
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
  let script_bytes = builtin.append_bytearray(
    version_header,
    builtin.append_bytearray(
      prefix,
      builtin.append_bytearray(hashed_param, postfix),
    ),
  )

  // Hash with blake2b_224 to get the policy ID (28 bytes)
  builtin.blake2b_224(script_bytes)
}

/// Verify that `cs_to_insert` is the policy id derived from applying the
/// issuance template (`prefix` + `postfix`) to the inner 28-byte hash of
/// `minting_logic_script`. This is the *cryptographic binding* tying the
/// registered credential to the policy id; mode-independent.
///
/// The `Constr` variant tag (VerificationKey vs Script) is embedded in
/// `prefix` by the off-chain bootstrap, so this on-chain code only needs
/// to sandwich the inner hash bytes — the policy id derivation
/// indirectly enforces variant agreement.
pub fn is_programmable_token_id_valid(
  cs_to_insert: ByteArray,
  prefix: ByteArray,
  postfix: ByteArray,
  minting_logic_script: Credential,
) -> Bool {
  expect Script(hashed_param) = minting_logic_script
  apply_hashed_parameter(prefix, postfix, hashed_param) == cs_to_insert
}

/// True iff `mint_value` contains any entry under `policy`, regardless of
/// quantity sign.
///
/// Used by `registry_mint.ak` for the mode ↔ tx.mint consistency check:
///   * RegisterOnly  ⇒ `!mint_has_policy(self.mint, key)`
///   * RegisterAndMint ⇒ `mint_has_policy(self.mint, key)`
///
/// Cheapest primitive among the candidates benchmarked in
/// `lib/utils.test.ak` (`bench_a4_has_key_*`) — ~14–18% fewer ex-units than
/// the previous split-helper implementation, both in the "absent" and
/// "present" directions.
///
/// Note on burn-only entries: a `tx.mint` containing only negative
/// quantities under `policy` returns `True` from this function (the
/// outer-dict entry still exists). For a registration tx, burn-only of
/// the new policy is impossible at the ledger level (no prior tokens to
/// burn), so the looser semantics are safe in practice.
pub fn mint_has_policy(mint_value: Value, policy: PolicyId) -> Bool {
  assets.to_dict(mint_value) |> dict.has_key(policy)
}
