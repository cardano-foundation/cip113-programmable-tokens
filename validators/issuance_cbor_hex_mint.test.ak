//// Comprehensive tests for the issuance_cbor_hex_mint validator.
////
//// Tests invoke the validator's mint handler directly, covering:
//// - Happy path (all conditions met)
//// - One-shot UTxO consumption
//// - Token name and quantity checks
//// - Always-fail address enforcement
//// - InlineDatum and IssuanceCborHex datum validation

use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use issuance_cbor_hex_mint
use types.{
  IssuanceCborHex, issuance_cbor_hex_token_name, max_issuance_template_bytes,
}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_utxo_ref =
  OutputReference {
    transaction_id: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    output_index: 0,
  }

const test_always_fail_hash: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const test_policy_id: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn always_fail_address() -> Address {
  Address {
    payment_credential: Script(test_always_fail_hash),
    stake_credential: None,
  }
}

fn valid_issuance_datum() -> Data {
  as_data(
    IssuanceCborHex { prefix_cbor_hex: #"aabb", postfix_cbor_hex: #"ccdd" },
  )
}

fn valid_nft_output() -> Output {
  Output {
    address: always_fail_address(),
    value: min_ada
      |> assets.add(test_policy_id, issuance_cbor_hex_token_name, 1),
    datum: InlineDatum(valid_issuance_datum()),
    reference_script: None,
  }
}

fn valid_input() -> Input {
  Input {
    output_reference: test_utxo_ref,
    output: Output {
      address: Address {
        payment_credential: VerificationKey(
          #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        ),
        stake_credential: None,
      },
      value: min_ada,
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn valid_transaction() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, issuance_cbor_hex_token_name, 1),
    outputs: [valid_nft_output()],
  }
}

fn call_validator(
  utxo_ref: OutputReference,
  af_hash: ByteArray,
  tx: Transaction,
) -> Bool {
  issuance_cbor_hex_mint.issuance_cbor_hex_mint.mint(
    utxo_ref,
    af_hash,
    as_data(Void),
    test_policy_id,
    tx,
  )
}

// ========================================================================
// Happy path — all conditions met
// ========================================================================

test issuance_cbor_hex_mint_valid() {
  call_validator(test_utxo_ref, test_always_fail_hash, valid_transaction())
}

// ========================================================================
// One-shot UTxO not consumed
// ========================================================================

test fails_when_utxo_not_consumed() fail {
  let wrong_utxo_ref = OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 99,
  }
  call_validator(wrong_utxo_ref, test_always_fail_hash, valid_transaction())
}

// ========================================================================
// Wrong token name — the `tn == issuance_cbor_hex_token_name` check
//
// We mint "WrongName" but keep the output NFT as "IssuanceCborHex" so
// has_nft_strict and datum checks pass; only the token-name check fails.
// ========================================================================

test fails_with_wrong_token_name() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, "WrongName", 1),
    outputs: [valid_nft_output()],
  }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// Quantity != 1 — the `qty == 1` check
//
// We mint qty=2 but keep the output with qty=1 so has_nft_strict passes;
// only the quantity check in the and-block fails.
// ========================================================================

test fails_when_quantity_is_not_one() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, issuance_cbor_hex_token_name, 2),
    outputs: [valid_nft_output()],
  }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// Multiple token names minted under the same policy
//
// The `expect [(_, tn, qty)] = own_minted` pattern crashes because
// the list has 2 elements instead of 1.
// ========================================================================

test fails_with_multiple_token_names_minted() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, issuance_cbor_hex_token_name, 1)
      |> assets.add(test_policy_id, "ExtraToken", 1),
    outputs: [valid_nft_output()],
  }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// No tokens minted from own policy
//
// The mint contains a different policy entirely, so `own_minted` is empty
// and `expect [(_, tn, qty)]` crashes.
// ========================================================================

test fails_when_no_tokens_minted_from_own_policy() fail {
  let other_policy: PolicyId = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(other_policy, "SomeToken", 1),
    outputs: [valid_nft_output()],
  }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// No output at the always-fail address
//
// The NFT goes to a completely different address.
// `expect Some(nft_output) = list.find(...)` crashes because no output
// matches the expected always-fail address.
// ========================================================================

test fails_when_no_output_at_always_fail_address() fail {
  let wrong_address = Address {
    payment_credential: Script(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ),
    stake_credential: None,
  }
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, issuance_cbor_hex_token_name, 1),
    outputs: [
      Output {
        address: wrong_address,
        value: min_ada
          |> assets.add(test_policy_id, issuance_cbor_hex_token_name, 1),
        datum: InlineDatum(valid_issuance_datum()),
        reference_script: None,
      },
    ],
  }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// Output at always-fail address exists but does NOT contain the NFT
//
// `has_nft_strict(nft_output.value, own_policy, ...)` fails because
// the output at the always-fail address has only ADA.
// ========================================================================

test fails_when_nft_missing_from_always_fail_output() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, issuance_cbor_hex_token_name, 1),
    outputs: [
      // Output at always-fail address but WITHOUT the NFT
      Output {
        address: always_fail_address(),
        value: min_ada,
        datum: InlineDatum(valid_issuance_datum()),
        reference_script: None,
      },
    ],
  }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// No inline datum on the always-fail output
//
// `expect InlineDatum(datum) = nft_output.datum` crashes because the
// output uses NoDatum.
// ========================================================================

test fails_when_no_inline_datum() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, issuance_cbor_hex_token_name, 1),
    outputs: [Output { ..valid_nft_output(), datum: NoDatum }],
  }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ========================================================================
// Invalid datum type — datum is not IssuanceCborHex
//
// `expect _issuance_datum: IssuanceCborHex = datum` crashes because
// an Int doesn't match the IssuanceCborHex constructor.
// ========================================================================

test fails_with_invalid_datum_type() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, issuance_cbor_hex_token_name, 1),
    outputs: [Output { ..valid_nft_output(), datum: InlineDatum(as_data(42)) }],
  }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

// ==========================================================================
// The issuance template is the one datum in the protocol with no repair path.
//
// Its NFT is locked at `always_fail`, so this mint is the ONLY moment the
// datum can ever be written. Every `RegistryInsert` afterwards takes the UTxO
// as a reference input and hashes the template to derive the policy id
// (`utils.apply_hashed_parameter`), so an oversized template would disable
// all future registration permanently — and no protocol upgrade can reach a
// UTxO that cannot be spent.
//
// The cast (`expect _: IssuanceCborHex = datum`) checks the constructor tag
// and the field count only; `ByteArray` carries no length. The rail in the
// mint handler is therefore the only thing that keeps this datum small.
// ==========================================================================

/// A template of exactly `n` bytes.
fn template_of_length(n: Int) -> ByteArray {
  bytearray.take(
    list.foldr(
      list.range(1, 128),
      #"",
      fn(_, acc) {
        bytearray.concat(
          acc,
          #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
        )
      },
    ),
    n,
  )
}

fn call_with_template(prefix_len: Int, postfix_len: Int) -> Bool {
  let datum = as_data(
    IssuanceCborHex {
      prefix_cbor_hex: template_of_length(prefix_len),
      postfix_cbor_hex: template_of_length(postfix_len),
    },
  )
  let output = Output { ..valid_nft_output(), datum: InlineDatum(datum) }
  let tx = Transaction { ..valid_transaction(), outputs: [output] }
  call_validator(test_utxo_ref, test_always_fail_hash, tx)
}

test template_of_length_builds_the_stated_size() {
  // Sanity on the helper, so the tests below cannot pass because it silently
  // returned something shorter than asked for.
  and {
    (bytearray.length(template_of_length(0)) == 0)?,
    (bytearray.length(template_of_length(679)) == 679)?,
    (bytearray.length(template_of_length(4096)) == 4096)?,
  }
}

// Accept: the real template. The compiled `issuance_mint` script is 679 bytes,
// so a realistic prefix+postfix sits an order of magnitude under the bound.
test issuance_template_accepts_a_realistic_script_size() {
  call_with_template(600, 79)
}

// Accept: exactly at the bound. `<=`, not `<`.
test issuance_template_accepts_the_exact_bound() {
  call_with_template(max_issuance_template_bytes - 96, 96)
}

// Reject: one byte over the bound. The single delta from the test above.
test issuance_template_fails_one_byte_over_the_bound() fail {
  call_with_template(max_issuance_template_bytes - 96 + 1, 96)
}

// Reject: the brick shape — a template far past anything registration could
// afford to hash on every insert.
test issuance_template_fails_oversized_template() fail {
  call_with_template(4000, 4000)
}

// Reject: the bound is on the SUM, not on either field alone. Each half is
// individually under the bound; together they are not.
test issuance_template_fails_when_only_the_sum_exceeds_the_bound() fail {
  call_with_template(3000, 1200)
}
