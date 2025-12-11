// =============================================================================
// CIP-0113 Utility Functions
// =============================================================================
//
// This module provides common utility functions used across the CIP-0113
// validator suite. Functions are organized into the following categories:
//
// - Value Operations: Comparing and checking token values
// - Datum Helpers: Extracting inline datums
// - Input/Output Filtering: Finding specific UTxOs by credential
// - Script Invocation: Checking if scripts are invoked via withdrawal
// - ByteArray Operations: Lexicographic comparison for sorted lists
// - Policy ID Computation: Reconstructing and hashing parametrized scripts
//
// ## Migration Notes
//
// These utilities were migrated from various Plutarch modules and adapted
// for Aiken's type system and optimization patterns.
//
// =============================================================================

use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{PolicyId, Value, flatten, quantity_of}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}

// =============================================================================
// Value Operations
// =============================================================================

/// Check if a value contains at least the required amount of each asset.
///
/// This function iterates through all assets in `required` and verifies that
/// `value` contains at least that amount of each asset.
///
/// ## Arguments
///
/// - `value`: The Value to check (typically from an output)
/// - `required`: The minimum required Value
///
/// ## Returns
///
/// `True` if value contains all required assets in sufficient quantities.
///
/// ## Example
///
/// ```aiken
/// let output_value = some_output.value
/// let required_tokens = assets.from_asset(policy_id, token_name, 100)
/// expect value_contains(output_value, required_tokens)
/// ```
///
/// ## Optimization Note
///
/// Uses early-exit pattern via if-check to short-circuit on first failure.
pub fn value_contains(value: Value, required: Value) -> Bool {
  assets.reduce(
    required,
    True,
    fn(policy, name, req_qty, acc) {
      // Short-circuit if already failed
      if !acc {
        False
      } else {
        quantity_of(value, policy, name) >= req_qty
      }
    },
  )
}

/// Optimized version of value_contains using `expect` for fail-fast behavior.
///
/// This version is more efficient when we expect the condition to pass
/// (the common case in validators). Uses Aiken's `expect` which fails
/// immediately if the condition is false, avoiding unnecessary iterations.
///
/// ## Usage
///
/// ```aiken
/// // Fails immediately if output doesn't contain required tokens
/// expect_value_contains_v3(output.value, required_tokens)
/// ```
pub fn expect_value_contains_v3(value: Value, required: Value) -> Void {
  assets.reduce(
    required,
    Void,
    fn(policy, name, req_qty, _acc) {
      expect quantity_of(value, policy, name) >= req_qty
    },
  )
}

// =============================================================================
// Datum Helpers
// =============================================================================

/// Extract the inline datum from an output.
///
/// CIP-0113 exclusively uses inline datums for registry nodes, blacklist nodes,
/// and protocol parameters. This function extracts the raw Data from an output
/// with an inline datum.
///
/// ## Panics
///
/// Fails if the output does not have an inline datum (DatumHash or NoDatum).
///
/// ## Example
///
/// ```aiken
/// let datum_data = expect_inline_datum(registry_utxo)
/// expect node: RegistryNode = datum_data
/// ```
pub fn expect_inline_datum(output: Output) -> Data {
  expect InlineDatum(d) = output.datum
  d
}

// =============================================================================
// Input/Output Filtering
// =============================================================================

/// Find an input matching a predicate.
///
/// ## Arguments
///
/// - `inputs`: List of transaction inputs to search
/// - `predicate`: Function that returns true for the desired input
///
/// ## Returns
///
/// `Some(input)` if found, `None` otherwise.
pub fn find_input(
  inputs: List<Input>,
  predicate: fn(Input) -> Bool,
) -> Option<Input> {
  list.find(inputs, predicate)
}

/// Find an input matching a predicate, failing if not found.
///
/// Use this when the input MUST exist (e.g., the protocol params reference).
///
/// ## Panics
///
/// Fails with "Required input not found" if no input matches.
pub fn must_find_input(
  inputs: List<Input>,
  predicate: fn(Input) -> Bool,
) -> Input {
  when find_input(inputs, predicate) is {
    Some(input) -> input
    None -> fail @"Required input not found"
  }
}

/// Check if a currency symbol (policy ID) is present in a value.
///
/// This is an efficient check that uses dictionary key lookup rather than
/// iterating through all tokens.
///
/// ## Example
///
/// ```aiken
/// // Check if UTxO holds any registry node NFTs
/// if has_currency_symbol(utxo.value, registry_node_cs) {
///   // This is a registry node
/// }
/// ```
pub fn has_currency_symbol(value: Value, cs: PolicyId) -> Bool {
  assets.to_dict(value) |> dict.has_key(cs)
}

/// Count unique tokens in a value.
///
/// Returns the number of distinct (policy_id, token_name) pairs in the value.
/// Useful for validating that UTxOs have exactly the expected number of assets.
///
/// ## Example
///
/// ```aiken
/// // Registry nodes must have exactly 2 tokens: ADA + node NFT
/// expect count_unique_tokens(node_output.value) == 2
/// ```
pub fn count_unique_tokens(value: Value) -> Int {
  assets.reduce(value, 0, fn(_policy, _name, _amount, acc) { acc + 1 })
}

/// Get all outputs paying to a specific payment credential.
///
/// ## Arguments
///
/// - `outputs`: List of transaction outputs
/// - `cred`: The payment credential to filter by
///
/// ## Returns
///
/// List of outputs where output.address.payment_credential == cred
pub fn outputs_at_credential(
  outputs: List<Output>,
  cred: Credential,
) -> List<Output> {
  list.filter(outputs, fn(output) { output.address.payment_credential == cred })
}

/// Get all inputs spending from a specific payment credential.
///
/// ## Arguments
///
/// - `inputs`: List of transaction inputs
/// - `cred`: The payment credential to filter by
///
/// ## Returns
///
/// List of inputs where input.output.address.payment_credential == cred
pub fn inputs_from_credential(
  inputs: List<Input>,
  cred: Credential,
) -> List<Input> {
  list.filter(
    inputs,
    fn(input) { input.output.address.payment_credential == cred },
  )
}

/// Count inputs spending from a specific payment credential.
///
/// More efficient than inputs_from_credential when you only need the count.
pub fn count_inputs_from_credential(
  inputs: List<Input>,
  cred: Credential,
) -> Int {
  inputs_from_credential(inputs, cred) |> list.length
}

// =============================================================================
// Script Invocation Checks
// =============================================================================

/// Check if a transaction is signed by a specific public key hash.
///
/// Used for authorization checks when the stake credential is a VerificationKey.
///
/// ## Arguments
///
/// - `tx`: The transaction to check
/// - `pkh`: The public key hash (28 bytes) to look for
///
/// ## Returns
///
/// `True` if pkh is in tx.extra_signatories
pub fn is_signed_by(tx: Transaction, pkh: ByteArray) -> Bool {
  list.any(tx.extra_signatories, fn(sig) { sig == pkh })
}

/// Check if a script credential is invoked via withdrawal.
///
/// CIP-0113 uses the "withdraw-zero" pattern where stake scripts are invoked
/// by including a zero-value withdrawal in the transaction. This function
/// checks if a specific script credential appears in the withdrawals.
///
/// ## Arguments
///
/// - `tx`: The transaction to check
/// - `script_cred`: The script credential to look for
///
/// ## Returns
///
/// `True` if the credential appears in tx.withdrawals
///
/// ## Example
///
/// ```aiken
/// // Check that the transfer logic script was invoked
/// expect is_script_invoked(tx, registry_node.transfer_logic_script)
/// ```
pub fn is_script_invoked(tx: Transaction, script_cred: Credential) -> Bool {
  list.any(
    tx.withdrawals,
    fn(withdrawal) {
      let Pair(cred, _amount) = withdrawal
      cred == script_cred
    },
  )
}

// =============================================================================
// List Operations
// =============================================================================

/// Get element at index from a list.
///
/// This is used to look up reference inputs by index (e.g., registry nodes).
///
/// ## Arguments
///
/// - `lst`: The list to index into
/// - `idx`: Zero-based index
///
/// ## Panics
///
/// Fails with "Index out of bounds" if idx >= list length.
///
/// ## Complexity
///
/// O(n) where n = idx. For small indices this is efficient.
pub fn elem_at(lst: List<a>, idx: Int) -> a {
  when list.drop(lst, idx) is {
    [elem, ..] -> elem
    [] -> fail @"Index out of bounds"
  }
}

// =============================================================================
// ByteArray Operations
// =============================================================================

/// Check if a bytearray is lexicographically less than another.
///
/// Essential for maintaining sorted linked list invariants. The registry and
/// blacklist both use lexicographic ordering of keys.
///
/// ## Arguments
///
/// - `a`: First bytearray
/// - `b`: Second bytearray
///
/// ## Returns
///
/// `True` if a < b in lexicographic (dictionary) order.
///
/// ## Example
///
/// ```aiken
/// // Verify linked list ordering
/// expect bytearray_lt(node.key, node.next)
/// ```
pub fn bytearray_lt(a: ByteArray, b: ByteArray) -> Bool {
  builtin.less_than_bytearray(a, b)
}

// =============================================================================
// Policy ID Computation
// =============================================================================

/// Apply a hashed parameter to script prefix/postfix to compute a policy ID.
///
/// This function reconstructs a parametrized minting policy script from its
/// components and hashes it to get the currency symbol (policy ID).
///
/// ## Script Structure
///
/// Plutus V3 scripts have the following format:
/// ```
/// version_header (1 byte: 0x03) + prefix + serialized_param + postfix
/// ```
///
/// ## Arguments
///
/// - `prefix`: Script bytes before the parameter
/// - `postfix`: Script bytes after the parameter
/// - `hashed_param`: The serialized parameter bytes
///
/// ## Returns
///
/// The 28-byte Blake2b-224 hash of the complete script (the policy ID).
///
/// ## Usage
///
/// This is used during registry insertion to verify that a new policy ID
/// was created using the approved issuance template.
pub fn apply_hashed_parameter(
  prefix: ByteArray,
  postfix: ByteArray,
  hashed_param: ByteArray,
) -> ByteArray {
  // Plutus V3 version header: most significant first encoding of version 3
  let version_header = #"03"

  // Build the script: version + prefix + serialized_param + postfix
  let script_bytes =
    builtin.append_bytearray(
      version_header,
      builtin.append_bytearray(
        prefix,
        builtin.append_bytearray(hashed_param, postfix),
      ),
    )

  // Hash with blake2b_224 to get the policy ID (28 bytes)
  builtin.blake2b_224(script_bytes)
}

/// Check if a currency symbol is a valid programmable token registration.
///
/// This function validates that:
/// 1. Tokens with this policy ID are being minted in the transaction
/// 2. The computed policy ID (from prefix + hashed_param + postfix) matches
///
/// ## Arguments
///
/// - `cs_to_insert`: The currency symbol being registered
/// - `prefix`: Issuance template prefix bytes
/// - `postfix`: Issuance template postfix bytes
/// - `hashed_param`: The parameter used to create this specific policy
/// - `mint_value`: The transaction's mint value
///
/// ## Returns
///
/// `True` if this is a valid programmable token registration.
///
/// ## Security
///
/// This ensures that only policies created from the approved issuance template
/// can be registered in the CIP-0113 registry, preventing malicious policies.
pub fn is_programmable_token_registration(
  cs_to_insert: ByteArray,
  prefix: ByteArray,
  postfix: ByteArray,
  hashed_param: ByteArray,
  mint_value: Value,
) -> Bool {
  // Check 1: The policy must be minting tokens in this transaction
  let has_minting =
    list.any(
      flatten(mint_value),
      fn(asset) {
        let (policy, _tn, amt) = asset
        policy == cs_to_insert && amt > 0
      },
    )

  // Check 2: The computed policy ID must match the currency symbol being inserted
  let computed_cs = apply_hashed_parameter(prefix, postfix, hashed_param)
  let cs_matches = computed_cs == cs_to_insert

  has_minting? && cs_matches?
}
