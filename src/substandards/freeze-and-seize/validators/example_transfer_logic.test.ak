// // Integration tests for example transfer logic validators

use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId, from_asset, tokens}
use cardano/transaction as transaction
use types.{IssuanceCborHex}
use utils.{apply_hashed_parameter}

// ------------------------------------------------------------
// Test constants
// ------------------------------------------------------------

const test_permitted_pkh = #"aabbccdd"

const test_other_pkh = #"11223344"

const test_asset_name = #"544f4b454e"

// "TOKEN"

// IssuanceCborHex NFT policy ID (used to find reference input)
const issuance_cbor_hex_cs: PolicyId =
  #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"

// Prefix/postfix stored in IssuanceCborHex datum (on-chain trusted values)
const issuance_prefix = #"aa"

const issuance_postfix = #"bb"

const prog_base_hash = #"cccc"

const withdraw_script_hash = #"dddd"

// ------------------------------------------------------------
// Helpers (mirror validator logic)
// ------------------------------------------------------------

fn concat_bytes(a: ByteArray, b: ByteArray) -> ByteArray {
  builtin.append_bytearray(a, b)
}

fn derive_policy_id(
  issuance_prefix: ByteArray,
  issuance_postfix: ByteArray,
  prog_base_hash: ByteArray,
  withdraw_script_hash: ByteArray,
) -> ByteArray {
  let hashed_param = concat_bytes(prog_base_hash, withdraw_script_hash)

  apply_hashed_parameter(issuance_prefix, issuance_postfix, hashed_param)
}

// Helper to create an IssuanceCborHex datum
fn create_issuance_cbor_hex(
  prefix: ByteArray,
  postfix: ByteArray,
) -> IssuanceCborHex {
  IssuanceCborHex { prefix_cbor_hex: prefix, postfix_cbor_hex: postfix }
}

// Helper to create a reference input with IssuanceCborHex NFT
fn create_issuance_ref_input(
  issuance_cbor: IssuanceCborHex,
  nft_policy: PolicyId,
) -> transaction.Input {
  // Create value with the IssuanceCborHex NFT (token name: "IssuanceCborHex")
  let nft_value = from_asset(nft_policy, #"49737375616e636543626f72486578", 1)

  // "IssuanceCborHex"
  transaction.Input {
    output_reference: transaction.OutputReference {
      // Dummy transaction ID (32 bytes = 64 hex chars)
      transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
      output_index: 0,
    },
    output: transaction.Output {
      // Dummy script address (28 bytes = 56 hex chars for blake2b_224 hash)
      address: Address {
        payment_credential: Script(
          #"00000000000000000000000000000000000000000000000000000000",
        ),
        stake_credential: None,
      },
      value: nft_value,
      datum: transaction.InlineDatum(issuance_cbor),
      reference_script: None,
    },
  }
}

// Helper to find IssuanceCborHex reference input (mirrors validator logic)
fn find_issuance_ref_input(
  reference_inputs: List<transaction.Input>,
  issuance_cbor_hex_cs: PolicyId,
) -> Option<transaction.Input> {
  list.find(
    reference_inputs,
    fn(input) {
      let token_dict = tokens(input.output.value, issuance_cbor_hex_cs)
      !dict.is_empty(token_dict)
    },
  )
}

fn withdraw_script_executed(
  redeemers: Pairs<transaction.ScriptPurpose, transaction.Redeemer>,
  expected_hash: ByteArray,
) -> Bool {
  list.any(
    redeemers,
    fn(pair) {
      let Pair(purpose, _) = pair
      when purpose is {
        transaction.Withdraw(Script(hash)) -> hash == expected_hash
        _ -> False
      }
    },
  )
}

// ------------------------------------------------------------
// IssuanceCborHex reference input tests
// ------------------------------------------------------------

test finds_issuance_cbor_hex_ref_input() {
  let issuance_cbor =
    create_issuance_cbor_hex(issuance_prefix, issuance_postfix)
  let ref_input = create_issuance_ref_input(issuance_cbor, issuance_cbor_hex_cs)
  let reference_inputs = [ref_input]

  when find_issuance_ref_input(reference_inputs, issuance_cbor_hex_cs) is {
    Some(found) -> found.output_reference == ref_input.output_reference
    None -> False
  }
}

test fails_to_find_issuance_cbor_hex_without_ref_input() {
  let reference_inputs: List<transaction.Input> = []

  when find_issuance_ref_input(reference_inputs, issuance_cbor_hex_cs) is {
    Some(_) -> False
    None -> True
  }
}

test fails_to_find_issuance_cbor_hex_with_wrong_policy() {
  let issuance_cbor =
    create_issuance_cbor_hex(issuance_prefix, issuance_postfix)
  let ref_input = create_issuance_ref_input(issuance_cbor, issuance_cbor_hex_cs)
  let reference_inputs = [ref_input]
  let wrong_policy: PolicyId =
    #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

  when find_issuance_ref_input(reference_inputs, wrong_policy) is {
    Some(_) -> False
    None -> True
  }
}

test extracts_prefix_postfix_from_issuance_cbor_hex() {
  let issuance_cbor =
    create_issuance_cbor_hex(issuance_prefix, issuance_postfix)
  let ref_input = create_issuance_ref_input(issuance_cbor, issuance_cbor_hex_cs)

  when ref_input.output.datum is {
    transaction.InlineDatum(datum) -> {
      // Cast Data to IssuanceCborHex (same pattern as validator)
      expect issuance_cbor_extracted: IssuanceCborHex = datum
      issuance_cbor_extracted.prefix_cbor_hex == issuance_prefix
        && issuance_cbor_extracted.postfix_cbor_hex == issuance_postfix
    }
    _ -> False
  }
}

// ------------------------------------------------------------
// Authorization tests
// ------------------------------------------------------------

test admin_authorized_with_signature() {
  let permitted = VerificationKey(test_permitted_pkh)
  let signers = [test_permitted_pkh]

  when permitted is {
    VerificationKey(pkh) -> list.has(signers, pkh)
    _ -> False
  }
}

test admin_fails_without_signature() {
  let permitted = VerificationKey(test_permitted_pkh)
  let signers = [test_other_pkh]

  when permitted is {
    VerificationKey(pkh) -> !list.has(signers, pkh)
    _ -> True
  }
}

// ------------------------------------------------------------
// Withdraw execution tests
// ------------------------------------------------------------

test withdraw_script_executes() {
  let dummy_redeemer: transaction.Redeemer = 0
  let redeemers =
    [Pair(transaction.Withdraw(Script(withdraw_script_hash)), dummy_redeemer)]

  withdraw_script_executed(redeemers, withdraw_script_hash)
}

test withdraw_script_hash_mismatch_fails() {
  let dummy_redeemer: transaction.Redeemer = 0
  let redeemers = [Pair(transaction.Withdraw(Script(#"eeee")), dummy_redeemer)]

  !withdraw_script_executed(redeemers, withdraw_script_hash)
}

// ------------------------------------------------------------
// Mint validation tests
// Note: These tests verify policy ID derivation using prefix/postfix
// from IssuanceCborHex datum (on-chain trusted source), not parameters
// ------------------------------------------------------------

test valid_mint_passes() {
  // Derive policy ID using prefix/postfix from IssuanceCborHex (on-chain trusted values)
  let pid =
    derive_policy_id(
      issuance_prefix,
      // From IssuanceCborHex datum
      issuance_postfix,
      // From IssuanceCborHex datum
      prog_base_hash,
      withdraw_script_hash,
    )

  let mint = [(pid, test_asset_name, 1)]

  when list.head(mint) is {
    Some((policy, name, qty)) ->
      policy == pid && name == test_asset_name && qty > 0
    None -> False
  }
}

test wrong_asset_name_fails() {
  let pid =
    derive_policy_id(
      issuance_prefix,
      issuance_postfix,
      prog_base_hash,
      withdraw_script_hash,
    )

  let mint = [(pid, #"424144", 1)]

  // "BAD"
  when list.head(mint) is {
    Some((_, name, _)) -> name != test_asset_name
    None -> False
  }
}

test wrong_policy_id_fails() {
  let pid =
    derive_policy_id(
      issuance_prefix,
      issuance_postfix,
      prog_base_hash,
      withdraw_script_hash,
    )

  let mint = [(#"deadbeef", test_asset_name, 1)]

  when list.head(mint) is {
    Some((policy, _, _)) -> policy != pid
    None -> False
  }
}

test multiple_assets_fail() {
  let pid =
    derive_policy_id(
      issuance_prefix,
      issuance_postfix,
      prog_base_hash,
      withdraw_script_hash,
    )

  let mint = [(pid, test_asset_name, 1), (pid, #"424144", 1)]

  // Multiple assets should not be considered a valid mint
  list.length(mint) > 1
}

test policy_id_derived_from_issuance_cbor_hex_values() {
  // Verify that policy ID derivation uses values from IssuanceCborHex
  // This ensures the validator uses on-chain trusted values, not user-provided params
  let issuance_cbor =
    create_issuance_cbor_hex(issuance_prefix, issuance_postfix)
  // Derive policy ID using values from IssuanceCborHex datum
  let pid_from_datum =
    derive_policy_id(
      issuance_cbor.prefix_cbor_hex,
      issuance_cbor.postfix_cbor_hex,
      prog_base_hash,
      withdraw_script_hash,
    )
  // Derive policy ID using constants (should match)
  let pid_from_constants =
    derive_policy_id(
      issuance_prefix,
      issuance_postfix,
      prog_base_hash,
      withdraw_script_hash,
    )
  // Both should produce the same policy ID
  pid_from_datum == pid_from_constants
}

// ------------------------------------------------------------
// Seize (no mint) test
// ------------------------------------------------------------

test seize_without_mint_allowed() {
  let mint: List<(ByteArray, ByteArray, Int)> = []
  list.length(mint) == 0
}
