use aiken/builtin.{unconstr_fields}
use assets
use cardano/address.{Credential, VerificationKey}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{InlineDatum, Input}
use list

/// Constants for token names
pub const origin_node_tn = #""

/// Origin node datum key — empty bytestring, lexicographically the smallest
/// possible value, sorts before any 28-byte policy id.
pub const origin_node_key = #""

/// Sentinel value for the *last* node's `next` field. Plutus compares
/// bytestrings byte-by-byte, treating the longer string as greater when all
/// shared prefix bytes are equal — so a 30-byte all-`ff` is strictly greater
/// than any 28-byte policy id. The 30-byte length is intentional and
/// load-bearing for the linked-list ordering invariant: do NOT "normalise" it
/// to 28 bytes (that would collide with a hypothetical real 28-byte all-`ff`
/// policy id).
pub const sentinel_next_key =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

/// Empty Verification Key
pub const empty_vkey = VerificationKey(#"")

/// The canonical origin registry node. Used as a single equality target by
/// `is_origin_directory_node`, so any future field added to `RegistryNode` is
/// automatically enforced for the origin without touching the role helper.
pub const origin_node: RegistryNode =
  RegistryNode {
    key: origin_node_key,
    next: sentinel_next_key,
    minting_logic_script: empty_vkey,
    transfer_logic_script: empty_vkey,
    third_party_transfer_logic_script: empty_vkey,
    global_state_cs: #"",
  }

/// Registry node in the linked list of registered programmable token policies
/// This represents an entry in the CIP-113 registry.
///
/// Field order is load-bearing: it determines the CBOR layout consumed by both
/// on-chain and off-chain code. The three script-credential fields are ordered
/// by the natural lifecycle of a programmable token — `minting_logic_script`
/// (mint), `transfer_logic_script` (transfer), `third_party_transfer_logic_script`
/// (admin) — with `minting_logic_script` first because registration is the
/// earliest event in a token's lifetime.
pub type RegistryNode {
  /// The key (currency symbol) of the programmable token policy
  key: ByteArray,
  /// The next key in lexicographical order (for linked list traversal)
  next: ByteArray,
  /// The minting logic script credential. The substandard's withdraw-0 minting
  /// logic finds its own registry node by equality on this field — that gives
  /// it the `key` (the policy id) without recomputing the issuance hash.
  /// `registry_mint` also cryptographically binds this field to the policy id
  /// via `is_programmable_token_id_valid`, so the field cannot lie.
  minting_logic_script: Credential,
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
  // RegistryNode field index 3: key=0, next=1, minting_logic=2, transfer_logic=3
  expect transfer_logic_script: Credential =
    list.head(list.tail(list.tail(list.tail(fields))))
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
  // RegistryNode field index 4:
  // key=0, next=1, minting_logic=2, transfer_logic=3, third_party=4
  expect third_party_transfer_logic_script: Credential =
    list.head(list.tail(list.tail(list.tail(list.tail(fields)))))
  return(key, third_party_transfer_logic_script)
}

/// Extract `key` and `minting_logic_script` from a `RegistryNode` datum.
/// Useful for substandard withdraw-0 scripts that need to find their own
/// node (via credential equality on `minting_logic_script`) and read the
/// policy id (`key`) without recomputing the issuance hash.
pub fn with_key_and_minting_logic(
  data: Data,
  return: fn(ByteArray, Credential) -> result,
) -> result {
  let fields = unconstr_fields(data)
  expect key: ByteArray = list.head(fields)
  // RegistryNode field index 2: key=0, next=1, minting_logic=2
  expect minting_logic_script: Credential =
    list.head(list.tail(list.tail(fields)))
  return(key, minting_logic_script)
}
