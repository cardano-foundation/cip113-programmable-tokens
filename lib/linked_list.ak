use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, VerificationKey}
// Linked list validation logic for the token registry
// Migrated from SmartTokens.LinkedList.Common

use cardano/assets.{PolicyId, Value, tokens}
use cardano/transaction.{Input, Output, Transaction}
use registry_node.{
  RegistryNode, empty_vkey, origin_node_key, origin_node_tn, sentinel_next_key,
}
use utils.{
  bytearray_lt, count_unique_tokens, expect_inline_datum, has_currency_symbol,
}

/// Validate that a registry node output has the correct structure.
///
/// Enforces, in order:
///  1. CIP-113 §Registration point 7 — address has only a payment credential
///     (stake_credential MUST be None).
///  2. CIP-113 §Registration point 6 — no reference script.
///  3. Value carries exactly 2 policies: Ada and `node_cs`, with exactly one
///     NFT under `node_cs` at quantity 1.
///  4. Datum parses as a `RegistryNode`.
///  5. `node.key` length: 28 bytes (a policy id) OR the origin key (#"").
///  6. `node.next` length: 28 bytes OR the sentinel `sentinel_next_key`.
///  7. `node.key < node.next` in Plutus byte order.
///  8. `transfer_logic_script` and `third_party_transfer_logic_script` are
///     well-formed (0- or 28-byte hashes).
///  9. `global_state_cs` length is 0 or 28.
/// 10. NFT asset name strictly equals `node.key`. (Origin case still passes
///     because both sides are #"".) Replaces the prior loose disjunct
///     `tn == node.key || tn == origin_node_tn` which would have accepted a
///     non-origin node bearing the origin asset name.
pub fn validate_directory_node_output(
  output: Output,
  node_cs: PolicyId,
) -> RegistryNode {
  let value = output.value
  let datum = expect_inline_datum(output)

  // Address must have only a payment credential (CIP-113 §Registration point 7)
  expect output.address.stake_credential == None
  // No reference script (CIP-113 §Registration point 6)
  expect output.reference_script == None

  // Value must carry exactly two policies — Ada and `node_cs` — with exactly
  // one NFT under `node_cs` at quantity 1. Drops the Ada head (always first by
  // policy-id ordering, since the Ada policy is the empty bytestring), then
  // requires the tail to be a single (policy, asset-name -> 1) pair.
  expect [Pair(actual_node_cs, node_nft)] =
    assets.to_dict(value) |> dict.expect_tail() |> dict.to_pairs()
  expect actual_node_cs == node_cs
  expect [Pair(tn, 1)] = dict.to_pairs(node_nft)
  // Parse datum as RegistryNode
  expect node: RegistryNode = datum

  // Key length: 28 bytes (policy id) OR origin key (#"")
  expect bytearray.length(node.key) == 28 || node.key == origin_node_key
  // Next length: 28 bytes OR the sentinel for the last node
  expect bytearray.length(node.next) == 28 || node.next == sentinel_next_key

  // Node must be ordered: key < next
  expect bytearray_lt(node.key, node.next)

  // Credential shapes (length 0 or 28)
  expect is_valid_credential(node.transfer_logic_script)
  expect is_valid_credential(node.third_party_transfer_logic_script)
  // global_state_cs length 0 (absent) or 28 (policy id) per spec
  expect
    bytearray.length(node.global_state_cs) == 0 || bytearray.length(
      node.global_state_cs,
    ) == 28

  // Token name strictly matches the key (origin passes via #"" == #"")
  expect tn == node.key

  node
}

/// Get all inputs and outputs at the node validator address
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

/// Validate registry Init: no inputs, one empty origin node output, mint origin token
pub fn validate_directory_init(
  node_inputs: List<Input>,
  node_outputs: List<Output>,
  mint: Value,
  node_cs: PolicyId,
  registry_spend_cred: Credential,
) -> Bool {
  // Exactly one node output
  expect [node_output] = node_outputs
  // Origin node must be locked under registry_spend
  expect node_output.address.payment_credential == registry_spend_cred
  let node = validate_directory_node_output(node_output, node_cs)

  and {
    // No node inputs should be spent
    list.is_empty(node_inputs)?,
    // Node must be empty (origin node)
    (node.key == origin_node_key)?,
    (node.next == sentinel_next_key)?,
    (node.transfer_logic_script == empty_vkey)?,
    (node.third_party_transfer_logic_script == empty_vkey)?,
    (node.global_state_cs == #"")?,
    // Must mint exactly one origin token and no other tokens from this policy
    assets.has_nft(mint, node_cs, origin_node_tn)?,
  }
}

/// Check if a registry node represents an insertion at a specific position
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

/// Validate that a credential is properly formed
/// Allows empty credentials (for origin node) or valid 28-byte hashes
pub fn is_valid_credential(cred: Credential) -> Bool {
  when cred is {
    VerificationKey(hash) -> is_valid_credential_length(hash)
    Script(hash) -> is_valid_credential_length(hash)
  }
}

fn is_valid_credential_length(hash: ByteArray) -> Bool {
  let length = bytearray.length(hash)
  length == 28 || length == 0
}

/// Check if a registry node represents the covering node after insertion.
/// Validates ALL datum fields are preserved (not just key/next).
/// This prevents an attacker from swapping transfer_logic_script,
/// third_party_transfer_logic_script, or global_state_cs during a
/// RegistryInsert operation.
/// Fix for NEW-1 — matches Plutarch's pisInsertedOnNode strict equality.
pub fn is_updated_directory_node(
  node: RegistryNode,
  original: RegistryNode,
  insert_key: ByteArray,
) -> Bool {
  and {
    (node.key == original.key)?,
    (node.next == insert_key)?,
    (node.transfer_logic_script == original.transfer_logic_script)?,
    (node.third_party_transfer_logic_script == original.third_party_transfer_logic_script)?,
    (node.global_state_cs == original.global_state_cs)?,
  }
}
