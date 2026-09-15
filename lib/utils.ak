//// Utility functions for CIP-113 validators.

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

/// Is `needle` among the value's policies? Returns `False` when it is not.
///
/// ⚠ UTxO VALUES ONLY. The first pair is skipped as ada — true of any input or
/// output value (min-UTxO guarantees a lovelace entry, and the ada policy `""`
/// sorts first), but NOT of a `tx.mint` value, which carries no ada entry. On a
/// mint this would skip the first real policy and report a present policy as
/// absent. Use `mint_has_policy` there; do not "optimise" it into this.
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

/// Count distinct currency-symbol + token-name pairs in a value, including
/// the ada entry if present.
pub fn count_unique_tokens(value: Value) -> Int {
  assets.reduce(value, 0, fn(_policy, _name, _amount, acc) { acc + 1 })
}

/// Check if a bytearray is lexicographically less than another
pub fn bytearray_lt(a: ByteArray, b: ByteArray) -> Bool {
  builtin.less_than_bytearray(a, b)
}

/// Apply the inner hashed parameter to prefix and postfix to compute the
/// policy id: version_header + prefix + hashed_param + postfix. Any CBOR
/// framing for the parameter lives inside `prefix`/`postfix`.
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
/// registered credential to the policy id.
///
/// `minting_logic_script` must be a `Script` credential — a `VerificationKey`
/// aborts here. The `Constr` variant tag (VerificationKey vs Script) is
/// embedded in `prefix` by the off-chain bootstrap, so once past that check
/// the policy id derivation pins the tag bytes inside the hash alongside the
/// inner hash bytes.
pub fn expect_programmable_token_id_valid(
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
/// Used by the `registry` validator's spend handler (Re-audit R-01): a
/// registry-node spend must not mint or burn tokens of the spent node's own
/// `key`.
///
/// Note on burn-only entries: a `tx.mint` containing only negative
/// quantities under `policy` returns `True` from this function (the
/// outer-dict entry still exists).
/// Stays on `dict.has_key` deliberately: `has_currency_symbol` skips the first
/// pair as ada and a mint value has none. See its doc comment.
pub fn mint_has_policy(mint_value: Value, policy: PolicyId) -> Bool {
  assets.to_dict(mint_value) |> dict.has_key(policy)
}
