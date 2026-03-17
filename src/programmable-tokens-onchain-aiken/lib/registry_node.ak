use aiken/builtin.{unconstr_fields}
use assets
use cardano/address.{Credential, VerificationKey}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{InlineDatum, Input}
use list

/// Constants for token names
pub const origin_node_tn = #""

/// Empty Verification Key
pub const empty_vkey = VerificationKey(#"")

/// Registry node in the linked list of registered programmable token policies
/// This represents an entry in the CIP-0143 registry
pub type RegistryNode {
  /// The key (currency symbol) of the programmable token policy
  key: ByteArray,
  /// The next key in lexicographical order (for linked list traversal)
  next: ByteArray,
  /// The transfer logic script credential that validates token transfers
  transfer_logic_script: Credential,
  /// The third party transfer logic script credential that handles admin actions (seizure, etc.)
  third_party_transfer_logic_script: Credential,
  /// Optional global state NFT currency symbol for this policy
  global_state_cs: ByteArray,
}

pub fn new_registry_node_getter(
  registry_node_cs: PolicyId,
  ref_idx: Int,
  reference_inputs: List<Input>,
  get_registry_node: fn(Int) -> Data,
) -> fn(Int) -> Data {
  when reference_inputs is {
    [] -> get_registry_node
    [head, ..tail] ->
      new_registry_node_getter(
        registry_node_cs,
        ref_idx + 1,
        tail,
        fn(proof_idx) {
          if ref_idx == proof_idx {
            expect assets.peek_first(head.output) == registry_node_cs
            expect InlineDatum(data) = head.output.datum
            data
          } else {
            get_registry_node(proof_idx)
          }
        },
      )
  }
}

/// Extract useful information from an inlined 'RegistryNode' datum. Note that
/// we need not to 'validate' the full shape of the datum here, because we do not
/// produce it. We're only consuming it, and its well-formedness is guaranteed by the
/// linked list contract when producing the datum.
///
/// This even makes the contract more 'interoperable', as the linked-list datum
/// can change in addititive manner without invalidating this contract.
pub fn with_key_and_transfer_logic(
  data: Data,
  return: fn(ByteArray, Credential) -> result,
) -> result {
  let fields = unconstr_fields(data)
  expect key: ByteArray = list.head(fields)
  expect transfer_logic_script: Credential = list.head(
    list.tail(list.tail(fields)),
  )
  return(key, transfer_logic_script)
}

pub fn with_key_and_next_key(
  data: Data,
  return: fn(ByteArray, ByteArray) -> result,
) -> result {
  let fields = unconstr_fields(data)
  expect key: ByteArray = list.head(fields)
  let fields = list.tail(fields)
  expect next: ByteArray = list.head(fields)
  return(key, next)
}

pub fn with_key_and_3rd_party_logic(
  data: Data,
  return: fn(ByteArray, Credential) -> result,
) -> result {
  let fields = unconstr_fields(data)
  expect key: ByteArray = list.head(fields)
  expect third_party_transfer_logic_script: Credential = list.head(
    list.tail(list.tail(list.tail(fields))),
  )
  return(key, third_party_transfer_logic_script)
}
