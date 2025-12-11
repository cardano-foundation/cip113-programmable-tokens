// =============================================================================
// Sorted Linked List Validation
// =============================================================================
//
// This module implements validation logic for sorted linked lists used by the
// CIP-0113 protocol for the token registry and address blacklist.
//
// ## Design
//
// Both the registry and blacklist use the same sorted linked list pattern:
// - Each node is represented by a UTxO with an NFT and inline datum
// - The NFT's token name equals the node's key (except for origin node)
// - Nodes are ordered lexicographically by key
// - The origin node has key="" and points to the first real entry
// - The implicit end sentinel has key=0xff...ff (54 bytes of 0xff)
//
// ## Operations
//
// - **Init**: Create the origin node (empty list)
// - **Insert**: Add a new entry between two existing nodes
// - **Remove**: Delete an entry and re-link neighbors (blacklist only)
//
// ## Migration Notes
//
// Migrated from Plutarch modules:
// - SmartTokens.LinkedList.Common
// - SmartTokens.LinkedList.BlacklistCommon
//
// =============================================================================

use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{PolicyId, Value, tokens}
use cardano/transaction.{Input, Output, Transaction}
use types.{BlacklistNode, RegistryNode, empty_vkey, origin_node_tn}
use utils.{
  bytearray_lt, count_unique_tokens, expect_inline_datum, has_currency_symbol,
}

// =============================================================================
// Registry Node Validation
// =============================================================================

/// Validate that a registry node output has the correct structure.
///
/// This function performs comprehensive validation of a registry node UTxO,
/// ensuring all invariants are maintained. It returns the parsed RegistryNode
/// datum for further processing.
///
/// ## Validation Checks
///
/// 1. **Token count**: Exactly 2 unique tokens (ADA + node NFT)
/// 2. **Node NFT**: Exactly 1 NFT from the registry policy
/// 3. **Datum parse**: Output datum must be a valid RegistryNode
/// 4. **Ordering**: key < next (sorted list invariant)
/// 5. **Token name**: NFT token name matches key (or is origin token)
///
/// ## Arguments
///
/// - `output`: The output to validate
/// - `node_cs`: The registry node minting policy ID
///
/// ## Returns
///
/// The parsed RegistryNode from the output's inline datum.
///
/// ## Panics
///
/// Fails if any validation check fails.
pub fn validate_directory_node_output(
  output: Output,
  node_cs: PolicyId,
) -> RegistryNode {
  let value = output.value
  let datum = expect_inline_datum(output)

  // Must have exactly 2 unique tokens (Ada + node token)
  expect count_unique_tokens(value) == 2

  // Must have exactly 1 node token from this policy
  let node_tokens = tokens(value, node_cs)
  expect dict.size(node_tokens) == 1

  // Parse datum as RegistryNode
  expect node: RegistryNode = datum

  // Node must be ordered: key < next
  expect bytearray_lt(node.key, node.next)

  // Token name must match the key - convert dict to list for pattern matching
  let token_pairs = dict.to_pairs(node_tokens)
  expect [Pair(tn, qty)] = token_pairs
  expect qty == 1
  expect tn == node.key || tn == origin_node_tn

  node
}

// =============================================================================
// Blacklist Node Validation
// =============================================================================

/// Validate that a blacklist node output has the correct structure.
///
/// Similar to validate_directory_node_output but for BlacklistNode datums.
/// The blacklist uses the same sorted linked list structure but with simpler
/// node data (just key and next, no script credentials).
///
/// ## Arguments
///
/// - `output`: The output to validate
/// - `node_cs`: The blacklist node minting policy ID
///
/// ## Returns
///
/// The parsed BlacklistNode from the output's inline datum.
pub fn validate_blacklist_node_output(
  output: Output,
  node_cs: PolicyId,
) -> BlacklistNode {
  let value = output.value
  let datum = expect_inline_datum(output)

  // Must have exactly 2 unique tokens (Ada + node token)
  expect count_unique_tokens(value) == 2

  // Must have exactly 1 node token from this policy
  let node_tokens = tokens(value, node_cs)
  expect dict.size(node_tokens) == 1

  // Parse datum as BlacklistNode
  expect node: BlacklistNode = datum

  // Node must be ordered: key < next
  expect bytearray_lt(node.key, node.next)

  // Token name must match the key - convert dict to list for pattern matching
  let token_pairs = dict.to_pairs(node_tokens)
  expect [Pair(tn, qty)] = token_pairs
  expect qty == 1
  expect tn == node.key || tn == origin_node_tn

  node
}

// =============================================================================
// Transaction I/O Collection
// =============================================================================

/// Collect all inputs and outputs at the node validator address.
///
/// This function finds all UTxOs (inputs and outputs) that hold tokens from
/// the specified node policy. It also verifies that all node outputs go to
/// the same address as the node inputs (preventing theft).
///
/// ## Arguments
///
/// - `tx`: The transaction to analyze
/// - `node_cs`: The node minting policy ID
///
/// ## Returns
///
/// A tuple of (node_inputs, node_outputs).
///
/// ## Panics
///
/// Fails if node outputs go to a different address than node inputs.
pub fn collect_node_ios(
  tx: Transaction,
  node_cs: PolicyId,
) -> (List<Input>, List<Output>) {
  // Find inputs that have the node token
  let node_inputs =
    list.filter(
      tx.inputs,
      fn(input) { has_currency_symbol(input.output.value, node_cs) },
    )

  // Find outputs that have the node token
  let node_outputs =
    list.filter(
      tx.outputs,
      fn(output) { has_currency_symbol(output.value, node_cs) },
    )

  // All node outputs must be at the same address as the first node input
  when node_inputs is {
    [first, ..] -> {
      let expected_address = first.output.address
      expect
        list.all(
          node_outputs,
          fn(output) { output.address == expected_address },
        )
      (node_inputs, node_outputs)
    }
    [] -> ([], node_outputs)
  }
}

// =============================================================================
// Registry Initialization
// =============================================================================

/// Validate registry initialization (creating the empty list).
///
/// The Init operation creates the origin (sentinel) node which serves as the
/// head of the linked list. This must be the first operation on a new registry.
///
/// ## Requirements
///
/// 1. No existing node inputs (can't spend nodes during init)
/// 2. Exactly one node output (the origin node)
/// 3. Origin node has key="" and next=0xff...ff
/// 4. Origin node has empty credentials (no scripts)
/// 5. Exactly one origin token minted
///
/// ## Arguments
///
/// - `node_inputs`: Inputs holding node tokens (must be empty)
/// - `node_outputs`: Outputs with node tokens (exactly one)
/// - `mint`: Transaction mint value
/// - `node_cs`: Registry node minting policy ID
///
/// ## Returns
///
/// `True` if all validation checks pass.
pub fn validate_directory_init(
  node_inputs: List<Input>,
  node_outputs: List<Output>,
  mint: Value,
  node_cs: PolicyId,
) -> Bool {
  // Exactly one node output
  expect [node_output] = node_outputs
  let node = validate_directory_node_output(node_output, node_cs)

  and {
    // No node inputs should be spent
    list.is_empty(node_inputs)?,
    // Node must be empty (origin node)
    (node.key == #"")?,
    (node.next == #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")?,
    (node.transfer_logic_script == empty_vkey)?,
    (node.third_party_transfer_logic_script == empty_vkey)?,
    (node.global_state_cs == #"")?,
    // Must mint exactly one origin token and no other tokens from this policy
    assets.has_nft(mint, node_cs, origin_node_tn)?,
  }
}

// =============================================================================
// Blacklist Initialization
// =============================================================================

/// Validate blacklist initialization (creating the empty list).
///
/// Similar to validate_directory_init but for the blacklist structure.
/// Creates the origin node for the address blacklist.
///
/// ## Arguments
///
/// - `node_inputs`: Inputs holding node tokens (must be empty)
/// - `node_outputs`: Outputs with node tokens (exactly one)
/// - `mint`: Transaction mint value
/// - `node_cs`: Blacklist node minting policy ID
///
/// ## Returns
///
/// `True` if all validation checks pass.
pub fn validate_blacklist_init(
  node_inputs: List<Input>,
  node_outputs: List<Output>,
  mint: Value,
  node_cs: PolicyId,
) -> Bool {
  // Exactly one node output
  expect [node_output] = node_outputs
  let node = validate_blacklist_node_output(node_output, node_cs)

  and {
    // No node inputs should be spent
    list.is_empty(node_inputs),
    // Node must be empty (origin node)
    node.key == #"",
    node.next == #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    // Must mint exactly one origin token and no other tokens from this policy
    assets.has_nft(mint, node_cs, origin_node_tn),
  }
}

// =============================================================================
// Registry Insert Validation
// =============================================================================

/// Check if a registry node represents a newly inserted entry.
///
/// During an insert operation, a new node is created with the inserted key.
/// This function validates that the new node has the correct structure.
///
/// ## Arguments
///
/// - `node`: The node to check
/// - `insert_key`: The key being inserted
/// - `next_key`: The expected next key (from the covering node's next)
///
/// ## Returns
///
/// `True` if this is a valid inserted node.
pub fn is_inserted_directory_node(
  node: RegistryNode,
  insert_key: ByteArray,
  next_key: ByteArray,
) -> Bool {
  and {
    (node.key == insert_key)?,
    (node.next == next_key)?,
    // Validate credentials are properly formed
    is_valid_credential(node.transfer_logic_script)?,
    is_valid_credential(node.third_party_transfer_logic_script)?,
    // Validate global_state_cs is valid (can be empty or 28 bytes)
    (bytearray.length(node.global_state_cs) == 0 || bytearray.length(
      node.global_state_cs,
    ) == 28)?,
  }
}

/// Validate that a credential is properly formed.
///
/// Credentials must have valid hash lengths. Allows empty credentials
/// (for origin node) or valid 28-byte hashes.
///
/// ## Arguments
///
/// - `cred`: The credential to validate
///
/// ## Returns
///
/// `True` if the credential has a valid structure.
pub fn is_valid_credential(cred: Credential) -> Bool {
  when cred is {
    VerificationKey(hash) -> bytearray.length(hash) <= 28
    Script(hash) -> bytearray.length(hash) <= 28
  }
}

/// Check if a registry node represents the updated covering node after insertion.
///
/// When inserting a new entry, the covering node must be updated to point to
/// the new entry instead of its previous next. This function validates the
/// updated covering node.
///
/// ## Arguments
///
/// - `node`: The node to check (should be the updated covering node)
/// - `original_key`: The key of the covering node (unchanged)
/// - `insert_key`: The key being inserted (new next pointer)
///
/// ## Returns
///
/// `True` if this is a valid updated covering node.
pub fn is_updated_directory_node(
  node: RegistryNode,
  original_key: ByteArray,
  insert_key: ByteArray,
) -> Bool {
  node.key == original_key && node.next == insert_key
}

// =============================================================================
// Blacklist Insert Validation
// =============================================================================

/// Check if a blacklist node represents a newly inserted entry.
///
/// Similar to is_inserted_directory_node but for blacklist entries.
///
/// ## Arguments
///
/// - `node`: The node to check
/// - `insert_key`: The credential hash being blacklisted
/// - `next_key`: The expected next key
///
/// ## Returns
///
/// `True` if this is a valid inserted blacklist node.
pub fn is_inserted_blacklist_node(
  node: BlacklistNode,
  insert_key: ByteArray,
  next_key: ByteArray,
) -> Bool {
  node.key == insert_key && node.next == next_key
}

/// Check if a blacklist node represents the updated covering node after insertion.
///
/// ## Arguments
///
/// - `node`: The node to check
/// - `original_key`: The key of the covering node
/// - `insert_key`: The key being inserted
///
/// ## Returns
///
/// `True` if this is a valid updated covering node.
pub fn is_updated_blacklist_node(
  node: BlacklistNode,
  original_key: ByteArray,
  insert_key: ByteArray,
) -> Bool {
  node.key == original_key && node.next == insert_key
}
