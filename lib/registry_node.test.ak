use aiken/builtin
use aiken/collection/list
use aiken/fuzz
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id} as value
use cardano/fuzz as cardano
use cardano/transaction.{InlineDatum, Input, Output}
use registry_node.{
  RegistryNode, new_registry_node_getter, sentinel_next_key,
  with_key_and_minting_logic, with_key_and_next_key,
  with_key_and_third_party_logic, with_key_and_transfer_logic,
  with_key_and_unfracking_logic,
}
use utils.{bytearray_lt}

// ---------------------------------------------------- new_registry_node_getter

const registry_policy: PolicyId = "registry"

fn any_registry_node_reference_input() -> Fuzzer<Input> {
  let output_reference <- fuzz.and_then(cardano.output_reference())
  let address <- fuzz.and_then(cardano.address())
  let registry_node <- fuzz.and_then(any_registry_node())
  let min_ada_value = value.zero
    |> value.add(ada_policy_id, ada_asset_name, 1000000)
  fuzz.constant(
    Input {
      output_reference,
      output: Output {
        address,
        value: min_ada_value
          |> value.add(registry_policy, "", 1),
        datum: InlineDatum(as_data(registry_node)),
        reference_script: None,
      },
    },
  )
}

fn any_registry(min_nodes: Int, max_nodes: Int) -> Fuzzer<(Int, List<Input>)> {
  let before <- fuzz.and_then(fuzz.list_between(cardano.input(), 0, 2))
  let between <- fuzz.and_then(
    fuzz.list_between(any_registry_node_reference_input(), min_nodes, max_nodes),
  )
  let after <- fuzz.and_then(fuzz.list_between(cardano.input(), 0, 2))

  let len_before = list.length(before)

  let len_between = list.length(between)

  let ix <- fuzz.and_then(
    fuzz.int_between(len_before, len_before + len_between - 1),
  )

  fuzz.constant(
    (
      ix,
      before
        |> list.concat(between)
        |> list.concat(after),
    ),
  )
}

test prop_registry_lookup((ix, registry) via any_registry(1, 2)) {
  let get_registry_node = new_registry_node_getter(
    registry_policy,
    0,
    registry,
    fn(_) { fail },
  )
  expect _: RegistryNode = get_registry_node(ix)
}

test prop_registry_lookup_fail_no_node(
  (ix, registry) via any_registry(0, 0),
) fail {
  let get_registry_node = new_registry_node_getter(
    registry_policy,
    0,
    registry,
    fn(_) { fail },
  )
  get_registry_node(ix) != as_data(Void)
}

test prop_registry_lookup_fail_wrong_policy(
  (ix, registry) via any_registry(1, 1),
) fail {
  let get_registry_node = new_registry_node_getter(
    "foo",
    0,
    registry,
    fn(_) { fail },
  )
  get_registry_node(ix) != as_data(Void)
}

// -------------------------------------------------------------- with_key_and_*

fn any_registry_node() -> Fuzzer<RegistryNode> {
  let key <- fuzz.and_then(fuzz.bytearray_between(0, 32))
  let next <- fuzz.and_then(fuzz.bytearray_between(0, 32))
  let transfer_logic_script <- fuzz.and_then(cardano.credential())
  let third_party_logic_script <- fuzz.and_then(cardano.credential())
  let minting_logic_script <- fuzz.and_then(cardano.credential())
  let global_state_cs <- fuzz.and_then(cardano.policy_id())
  let unfracking_logic_script <- fuzz.and_then(cardano.credential())
  fuzz.constant(
    RegistryNode {
      key,
      next,
      minting_logic_script,
      transfer_logic_script,
      third_party_logic_script,
      unfracking_logic_script,
      global_state_cs,
    },
  )
}

test prop_with_key_and_transfer_logic_roundtrip(node via any_registry_node()) {
  let key, transfer_logic_script <- with_key_and_transfer_logic(node)
  and {
    (key == node.key)?,
    (transfer_logic_script == node.transfer_logic_script)?,
  }
}

test prop_with_key_and_next_key_roundtrip(node via any_registry_node()) {
  let key, next <- with_key_and_next_key(node)
  and {
    (key == node.key)?,
    (next == node.next)?,
  }
}

test prop_with_key_and_third_party_roundtrip(node via any_registry_node()) {
  let key, third_party_logic_script <- with_key_and_third_party_logic(node)
  and {
    (key == node.key)?,
    (third_party_logic_script == node.third_party_logic_script)?,
  }
}

test prop_with_key_and_minting_logic_roundtrip(node via any_registry_node()) {
  let key, minting_logic_script <- with_key_and_minting_logic(node)
  and {
    (key == node.key)?,
    (minting_logic_script == node.minting_logic_script)?,
  }
}

test prop_with_key_and_unfracking_logic_roundtrip(node via any_registry_node()) {
  let key, unfracking_logic_script <- with_key_and_unfracking_logic(node)
  and {
    (key == node.key)?,
    (unfracking_logic_script == node.unfracking_logic_script)?,
  }
}

// Deterministic off-by-one guard for the field-5 traversal: every field
// gets a DISTINCT, hand-chosen value so the assertions pin the exact
// indices regardless of fuzz luck.
test with_key_and_unfracking_logic_extracts_exact_fields() {
  let node = RegistryNode {
    key: #"a0",
    next: #"a1",
    minting_logic_script: VerificationKey(#"a2"),
    transfer_logic_script: VerificationKey(#"a3"),
    third_party_logic_script: Script(#"a4"),
    unfracking_logic_script: Script(#"a6"),
    global_state_cs: #"a5",
  }
  let key, unfracking_logic_script <- with_key_and_unfracking_logic(node)
  and {
    (key == #"a0")?,
    (unfracking_logic_script == Script(#"a6"))?,
  }
}

// -------------------------------------- sentinel_next_key ordering invariant
//
// `sentinel_next_key` is intentionally LONGER than a CIP-113 policy id (28
// bytes) — its 30-byte all-`ff` content guarantees it sorts strictly above
// any 28-byte value in Plutus byte order. If anyone ever shortens it to 28
// bytes — or to anything that doesn't strictly exceed every plausible policy
// id — the linked-list ordering invariant breaks and the `expect bytearray_lt(
// node.key, node.next)` check in `validate_registry_node_output` can fail
// on legitimate last-node configurations.
//
// These tests pin the property to the actual constant (not a copy of the
// literal), so a future edit to the constant either trips the tests or fails
// to compile.

/// Largest possible 28-byte (policy-id-sized) value. Local test constant; not
/// load-bearing — only used to assert the sentinel sorts above it.
const max_28_byte_value =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

test sentinel_is_longer_than_a_policy_id() {
  bytearray.length(sentinel_next_key) > 28
}

test max_28_byte_value_is_28_bytes() {
  // Sanity: catch a future typo in the local constant before it masks a real
  // regression in the test below.
  bytearray.length(max_28_byte_value) == 28
}

test sentinel_greater_than_28_byte_all_ff() {
  // Plutus byte comparison: when all shared prefix bytes are equal, the
  // longer string is greater. A 30-byte all-`ff` therefore sorts strictly
  // above a 28-byte all-`ff`.
  bytearray_lt(max_28_byte_value, sentinel_next_key)
}

test prop_sentinel_greater_than_any_28_byte_value(
  policy via fuzz.bytearray_between(28, 28),
) {
  // Property: every 28-byte value (regardless of content) sorts strictly
  // below `sentinel_next_key`. This is what makes the sentinel safe as the
  // `next` field of the last registry node.
  bytearray_lt(policy, sentinel_next_key)
}

// ------------------------------- datum-size surface of the RegistryNode cast
//
// #128: `expect node: RegistryNode = datum` checks the constructor tag and the
// FIELD COUNT. It does not check the length of any field. `Hash` and
// `ScriptHash` are aliases for `ByteArray`, so a `Credential` carrying a
// kilobyte of junk is a well-typed `RegistryNode` as far as the cast is
// concerned. Every length bound on a node is therefore hand-written, in
// `linked_list`, at each of the writers — see the rails exercised by
// `registry_insert_fails_oversized_transfer_logic_credential` and
// `registry_spend_fails_update_oversized_unfracking_credential`.
//
// These tests pin both halves: what the cast does NOT enforce (size) and what
// it DOES (arity). They are the reason the manual rails cannot be dropped.

/// A credential hash of `chunks` * 16 bytes. Built rather than written as a
/// literal so the size is visible as a number.
fn oversized_hash(chunks: Int) -> ByteArray {
  list.foldr(
    list.range(1, chunks),
    #"",
    fn(_, acc) { bytearray.concat(acc, #"deadbeefdeadbeefdeadbeefdeadbeef") },
  )
}

/// A `RegistryNode` whose four credential fields each carry a 1 KiB hash.
fn oversized_node() -> RegistryNode {
  let fat = Script(oversized_hash(64))
  RegistryNode {
    key: #"11111111111111111111111111111111111111111111111111111111",
    next: sentinel_next_key,
    minting_logic_script: fat,
    transfer_logic_script: fat,
    third_party_logic_script: fat,
    unfracking_logic_script: fat,
    global_state_cs: #"",
  }
}

/// Seven fields of the right types, plus one. Used to pin the arity check.
type EightFieldNode {
  key: ByteArray,
  next: ByteArray,
  minting_logic_script: Credential,
  transfer_logic_script: Credential,
  third_party_logic_script: Credential,
  unfracking_logic_script: Credential,
  global_state_cs: ByteArray,
  junk: ByteArray,
}

test oversized_hash_builds_the_stated_size() {
  // Sanity on the helper before the tests below lean on its magnitude.
  bytearray.length(oversized_hash(64)) == 1024
}

// The cast does NOT bound field size: a node carrying 4 KiB of credential
// hashes is accepted as a well-formed `RegistryNode`.
test registry_node_cast_accepts_an_unbounded_credential_hash() {
  let datum: Data = as_data(oversized_node())
  expect node: RegistryNode = datum
  node.transfer_logic_script == Script(oversized_hash(64))
}

// And the junk is real bytes on chain, not a decoding artefact: the serialised
// node is orders of magnitude larger than a well-formed one (~200 bytes).
test registry_node_cast_accepts_a_datum_of_arbitrary_size() {
  bytearray.length(builtin.serialise_data(oversized_node())) > 4000
}

// The cast DOES bound arity: an extra field is refused, so junk cannot ride
// along in a field the record does not declare.
test registry_node_cast_rejects_an_extra_field() fail {
  let datum: Data = as_data(
    EightFieldNode {
      key: #"11111111111111111111111111111111111111111111111111111111",
      next: sentinel_next_key,
      minting_logic_script: Script(#"00"),
      transfer_logic_script: Script(#"00"),
      third_party_logic_script: Script(#"00"),
      unfracking_logic_script: Script(#"00"),
      global_state_cs: #"",
      junk: #"deadbeef",
    },
  )
  expect _node: RegistryNode = datum
  True
}
