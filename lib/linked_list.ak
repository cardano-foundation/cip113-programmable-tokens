use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, VerificationKey}
// Linked list validation logic for the token registry
// Migrated from SmartTokens.LinkedList.Common

use cardano/assets.{PolicyId, Value}
use cardano/transaction.{Input, Output, Transaction}
use registry_node.{RegistryNode, origin_node, origin_node_tn, sentinel_next_key}
use utils.{bytearray_lt, expect_inline_datum, has_currency_symbol}

/// Validate the *common* structural properties of a registry-node output and
/// return the parsed `RegistryNode`. Role-specific shape (origin vs inserted
/// vs updated) is **not** checked here — see the `is_*_directory_node`
/// helpers below. The caller picks which role applies.
///
/// Enforces, in order:
///  1. CIP-113 §Registration point 7 — address has only a payment credential
///     (stake_credential MUST be None).
///  2. CIP-113 §Registration point 6 — no reference script.
///  3. Value carries exactly 2 policies: Ada and `node_cs`, with exactly one
///     NFT under `node_cs` at quantity 1.
///  4. Datum parses as a `RegistryNode`.
///  5. `node.key < node.next` in Plutus byte order.
///  6. NFT asset name strictly equals `node.key`. (Origin case passes because
///     both sides are #"".)
pub fn validate_directory_node_output(
  output: Output,
  node_cs: PolicyId,
) -> RegistryNode {
  // Address must have only a payment credential (CIP-113 §Registration point 7)
  expect output.address.stake_credential == None
  // No reference script (CIP-113 §Registration point 6)
  expect output.reference_script == None

  // Value must carry exactly two policies — Ada and `node_cs` — with exactly
  // one NFT under `node_cs` at quantity 1. Drops the Ada head (always first by
  // policy-id ordering, since the Ada policy is the empty bytestring), then
  // requires the tail to be a single (policy, asset-name -> 1) pair.
  expect [Pair(actual_node_cs, node_nft)] =
    assets.to_dict(output.value) |> dict.expect_tail() |> dict.to_pairs()
  expect actual_node_cs == node_cs
  expect [Pair(tn, 1)] = dict.to_pairs(node_nft)

  // Parse datum as RegistryNode
  expect node: RegistryNode = expect_inline_datum(output)

  // Node must be ordered: key < next
  expect bytearray_lt(node.key, node.next)

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
    // Node must match the canonical origin shape (all fields)
    is_origin_directory_node(node)?,
    // Must mint exactly one origin token and no other tokens from this policy
    assets.has_nft(mint, node_cs, origin_node_tn)?,
  }
}

/// True iff `node` is the canonical origin registry node. Single equality
/// against the `origin_node` constant — future fields added to `RegistryNode`
/// are automatically enforced without touching this helper.
pub fn is_origin_directory_node(node: RegistryNode) -> Bool {
  node == origin_node
}

/// True iff `node` has the shape of a freshly inserted (non-origin) registry
/// entry. Enforces:
///   * key/next match the expected `insert_key` / `next_key` (semantic shape).
///   * key is a 28-byte policy id (CIP-113 §RegistryNode `key`).
///   * next is either a 28-byte policy id OR the `sentinel_next_key` — the
///     latter when the inserted node becomes the new last node and inherits
///     the sentinel from the previous last (this is the only OR left that
///     isn't strictly spec-mandated; it follows from the linked-list design).
///   * credentials are strict 28-byte hashes (no length-0 origin loophole).
///   * `global_state_cs` is 0 or 28 bytes (CIP-113 normative MAY).
pub fn is_inserted_directory_node(
  node: RegistryNode,
  insert_key: ByteArray,
  next_key: ByteArray,
) -> Bool {
  and {
    (node.key == insert_key)?,
    (node.next == next_key)?,
    // CIP-113: key is a 28-byte policy id for non-origin nodes
    (bytearray.length(node.key) == 28)?,
    // next is 28 bytes OR the sentinel (when this node becomes the new last)
    (bytearray.length(node.next) == 28 || node.next == sentinel_next_key)?,
    // CIP-113: credentials MUST be 28-byte hashes (no empty allowed here —
    // empty credentials belong only to the origin node)
    is_28_byte_credential(node.transfer_logic_script)?,
    is_28_byte_credential(node.third_party_transfer_logic_script)?,
    // CIP-113 normative MAY: global_state_cs is 0 (absent) or 28 (a policy id)
    (bytearray.length(node.global_state_cs) == 0 || bytearray.length(
      node.global_state_cs,
    ) == 28)?,
  }
}

/// Strict 28-byte credential check. Used by `is_inserted_directory_node` to
/// reject the length-0 origin shape on a non-origin node.
pub fn is_28_byte_credential(cred: Credential) -> Bool {
  when cred is {
    VerificationKey(hash) -> bytearray.length(hash) == 28
    Script(hash) -> bytearray.length(hash) == 28
  }
}

/// True iff `node` is the covering node after a successful insertion: every
/// field equals the original except `next`, which now points at the freshly
/// inserted key. Implemented as a single record-equality check so any future
/// field added to `RegistryNode` is automatically enforced.
/// Fix for NEW-1 — matches Plutarch's pisInsertedOnNode strict equality.
pub fn is_updated_directory_node(
  node: RegistryNode,
  original: RegistryNode,
  insert_key: ByteArray,
) -> Bool {
  node == RegistryNode { ..original, next: insert_key }
}
