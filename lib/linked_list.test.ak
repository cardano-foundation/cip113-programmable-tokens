// Unit tests for linked list validation logic
use aiken/collection/list
use aiken/fuzz
use aiken/primitive/bytearray
use cardano/address.{Script, VerificationKey}
use linked_list.{
  is_field_updated_registry_node, is_inserted_registry_node,
  is_updated_registry_node,
}
use registry_node.{RegistryNode, empty_vkey}
use utils.{bytearray_lt}

// Helper to create a test address
// fn test_address() -> Address {
//   Address { payment_credential: Script(#"aabbccdd"), stake_credential: None }
// }

// ========================================================================
// is_updated_directory_node — positive tests
// ========================================================================

// Test is_updated_directory_node: all fields match original, next updated to insert_key
test is_updated_directory_node_works() {
  let original_key = #"aa"
  let insert_key = #"bb"

  let original = RegistryNode {
    key: original_key,
    next: #"cc",
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  let updated_node = RegistryNode {
    key: original_key,
    next: insert_key,
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  is_updated_registry_node(updated_node, original, insert_key)
}

// Test is_updated_directory_node negative — wrong next key
test is_updated_directory_node_negative() {
  let original_key = #"aa"
  let insert_key = #"bb"
  let wrong_key = #"dd"

  let original = RegistryNode {
    key: original_key,
    next: #"cc",
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  let node = RegistryNode {
    key: original_key,
    next: wrong_key,
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  !is_updated_registry_node(node, original, insert_key)
}

// Test is_inserted_directory_node
test is_inserted_directory_node_works() {
  // Strict 28-byte policy-id key/next per CIP-113. Previous fixture used
  // 1-byte placeholders, which the tightened helper now correctly rejects.
  let insert_key = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let next_key = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let transfer_logic = Script(
    #"11111111111111111111111111111111111111111111111111111111",
  )
  let third_party_transfer_logic = Script(
    #"22222222222222222222222222222222222222222222222222222222",
  )
  let minting_logic = Script(
    #"44444444444444444444444444444444444444444444444444444444",
  )
  let global_state = #"33333333333333333333333333333333333333333333333333333333"

  let node = RegistryNode {
    key: insert_key,
    next: next_key,
    transfer_logic_script: transfer_logic,
    third_party_logic_script: third_party_transfer_logic,
    minting_logic_script: minting_logic,
    unfracking_logic_script: empty_vkey,
    global_state_cs: global_state,
  }

  is_inserted_registry_node(node, insert_key, next_key, minting_logic)
}

// Test directory node ordering
test bytearray_lt_orders_three_28_byte_keys() {
  let key1 = #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
  let key2 = #"1112131415161718191a1b1c0d0e0f0102030405060708090a0b0c0d"
  let key3 = #"2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c"

  // CS ordering
  bytearray_lt(key1, key2) && bytearray_lt(key2, key3)
}

// Test empty origin node keys
test origin_node_empty_keys() {
  let empty = #""

  // Origin node has empty key and next
  let origin_node = RegistryNode {
    key: empty,
    next: empty,
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  origin_node.key == #"" && origin_node.next == #""
}

// ========================================================================
// NEW-1 FIX: is_updated_directory_node now REJECTS tampered datum fields
//
// Previously these tests PASSED (demonstrating the vulnerability).
// After the fix, is_updated_directory_node compares ALL five fields of the
// RegistryNode against the original, matching Plutarch's pisInsertedOnNode.
// Tampered nodes are now correctly rejected.
// ========================================================================

/// transfer_logic_script swap is now REJECTED.
/// Attacker cannot replace the original transfer logic with their own script.
test is_updated_directory_node_rejects_transfer_logic_swap() fail {
  let original = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  let tampered_node = RegistryNode {
    key: #"aa",
    next: #"bb",
    transfer_logic_script: Script(#"deadbeef"),
    // ^^^ ATTACKER'S SCRIPT — original was Script(#"11")
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  is_updated_registry_node(tampered_node, original, #"bb")
}

/// third_party_transfer_logic_script swap is now REJECTED.
/// Attacker cannot replace the seize/freeze logic with their own script.
test is_updated_directory_node_rejects_third_party_logic_swap() fail {
  let original = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  let tampered_node = RegistryNode {
    key: #"aa",
    next: #"bb",
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"deadbeef"),
    // ^^^ ATTACKER'S SCRIPT — original was Script(#"22")
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  is_updated_registry_node(tampered_node, original, #"bb")
}

/// global_state_cs tampering is now REJECTED.
/// Attacker cannot swap the global state currency symbol during insert.
test is_updated_directory_node_rejects_global_state_swap() fail {
  let original = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  let tampered_node = RegistryNode {
    key: #"aa",
    next: #"bb",
    transfer_logic_script: Script(#"11"),
    third_party_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead",
  }

  // ^^^ TAMPERED — original was #""
  is_updated_registry_node(tampered_node, original, #"bb")
}

test is_field_updated_registry_node_rejects_registry_nodes_differ() fail {
  let original = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    minting_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }
  let new = RegistryNode {
    key: #"ab",
    // changing an immutable field
    next: #"cc",
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    minting_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  is_field_updated_registry_node(new, original)
}

test is_field_updated_registry_node_update_true() {
  let original = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_logic_script: Script(
      #"22222222222222222222222222222222222222222222222222222222",
    ),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }
  let new = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ),
    third_party_logic_script: Script(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  }

  is_field_updated_registry_node(new, original)
}

// ------------------------------------------------- unfracking hook field (v2)
//
// `unfracking_logic_script` is either UNSET (empty_vkey — unfracking
// forbidden, the default every other test in this file uses) or a
// strict 28-byte credential. Enforced at Insert and Update; the field
// itself is freely mutable through the update path.

/// The valid inserted-node shape from `is_inserted_directory_node_works`,
/// lifted so the hook tests below can spread it with one delta.
fn valid_inserted_node() -> RegistryNode {
  RegistryNode {
    key: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    next: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_logic_script: Script(
      #"22222222222222222222222222222222222222222222222222222222",
    ),
    minting_logic_script: Script(
      #"44444444444444444444444444444444444444444444444444444444",
    ),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"33333333333333333333333333333333333333333333333333333333",
  }
}

// Insert accepts a SET hook (28-byte script credential). The unset
// (empty_vkey) acceptance is covered by `is_inserted_directory_node_works`.
test is_inserted_directory_node_accepts_set_unfracking_hook() {
  let node = RegistryNode {
    ..valid_inserted_node(),
    unfracking_logic_script: Script(
      #"55555555555555555555555555555555555555555555555555555555",
    ),
  }
  is_inserted_registry_node(
    node,
    node.key,
    node.next,
    node.minting_logic_script,
  )
}

// Insert rejects a malformed hook: non-empty but not 28 bytes.
test is_inserted_directory_node_rejects_malformed_unfracking_hook() fail {
  let node = RegistryNode {
    ..valid_inserted_node(),
    unfracking_logic_script: Script(#"5555"),
  }
  is_inserted_registry_node(
    node,
    node.key,
    node.next,
    node.minting_logic_script,
  )
}

/// A valid updatable node (the `is_field_updated_registry_node_update_true`
/// original), lifted for the hook update tests.
fn updatable_node() -> RegistryNode {
  RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_logic_script: Script(
      #"22222222222222222222222222222222222222222222222222222222",
    ),
    minting_logic_script: Script(#"33"),
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }
}

// Update may SET the hook (opt a policy into unfracking).
test is_field_updated_registry_node_allows_setting_unfracking_hook() {
  let original = updatable_node()
  let new = RegistryNode {
    ..original,
    unfracking_logic_script: Script(
      #"66666666666666666666666666666666666666666666666666666666",
    ),
  }
  is_field_updated_registry_node(new, original)
}

// Update may UNSET the hook back to empty_vkey — the field is plainly
// mutable (no ratchet): revoking it forbids future unfracking, which is
// the same authority the update path already holds over transfer logic.
test is_field_updated_registry_node_allows_unsetting_unfracking_hook() {
  let original = RegistryNode {
    ..updatable_node(),
    unfracking_logic_script: Script(
      #"66666666666666666666666666666666666666666666666666666666",
    ),
  }
  let new = RegistryNode { ..original, unfracking_logic_script: empty_vkey }
  is_field_updated_registry_node(new, original)
}

// Update rejects a malformed hook: non-empty but not 28 bytes.
test is_field_updated_registry_node_rejects_malformed_unfracking_hook() fail {
  let original = updatable_node()
  let new = RegistryNode {
    ..original,
    unfracking_logic_script: Script(#"6666"),
  }
  is_field_updated_registry_node(new, original)
}

// ==========================================================================
// #128: every RegistryNode field is size-bounded by HAND, not by the cast.
//
// `expect node: RegistryNode = datum` checks the constructor tag and the field
// count only — `Hash` is an alias for `ByteArray`, so a credential carrying a
// kilobyte of junk is a well-typed node (demonstrated in
// `lib/registry_node.test.ak`). The rails below are the only thing standing
// between that and a node datum large enough to price every reader out of
// spending or referencing it.
//
// These are stated as BICONDITIONALS over an arbitrary hash length: the rail
// accepts EXACTLY the valid lengths and rejects every other one. That pins the
// negative direction (no oversized field gets through) and the positive
// direction (the deliberate optionals still work) in a single property, so a
// future "cap everything at 28" edit cannot quietly ban a legal shape.
// ==========================================================================

/// Hash lengths from empty to well past a policy id, so the properties below
/// cover the undersized, exact, and oversized cases in one generator.
fn any_hash_length() -> Fuzzer<ByteArray> {
  fuzz.bytearray_between(0, 64)
}

// `transfer_logic_script` has NO optional form: exactly 28 bytes, nothing else.
test prop_insert_bounds_transfer_credential(hash via any_hash_length()) {
  let node = RegistryNode {
    ..valid_inserted_node(),
    transfer_logic_script: Script(hash),
  }
  let accepted = is_inserted_registry_node(
    node,
    node.key,
    node.next,
    node.minting_logic_script,
  )
  accepted == ( bytearray.length(hash) == 28 )
}

test prop_insert_bounds_third_party_credential(hash via any_hash_length()) {
  let node = RegistryNode {
    ..valid_inserted_node(),
    third_party_logic_script: Script(hash),
  }
  let accepted = is_inserted_registry_node(
    node,
    node.key,
    node.next,
    node.minting_logic_script,
  )
  accepted == ( bytearray.length(hash) == 28 )
}

// `unfracking_logic_script` IS optional, but its unset form is `empty_vkey` —
// a VerificationKey with an empty hash. A `Script` credential therefore has no
// legal empty form: 28 bytes or nothing.
test prop_insert_bounds_unfracking_hook_script_form(hash via any_hash_length()) {
  let node = RegistryNode {
    ..valid_inserted_node(),
    unfracking_logic_script: Script(hash),
  }
  let accepted = is_inserted_registry_node(
    node,
    node.key,
    node.next,
    node.minting_logic_script,
  )
  accepted == ( bytearray.length(hash) == 28 )
}

// The VerificationKey form of the hook: 28 bytes (signature-gated unfracking)
// or empty (`empty_vkey` — unfracking forbidden, the default). Both legal.
test prop_insert_bounds_unfracking_hook_vkey_form(hash via any_hash_length()) {
  let node = RegistryNode {
    ..valid_inserted_node(),
    unfracking_logic_script: VerificationKey(hash),
  }
  let accepted = is_inserted_registry_node(
    node,
    node.key,
    node.next,
    node.minting_logic_script,
  )
  let len = bytearray.length(hash)
  accepted == ( len == 28 || len == 0 )
}

// `global_state_cs` is the CIP-113 normative MAY: 0 (absent) or 28 (a policy id).
test prop_insert_bounds_global_state_cs(cs via any_hash_length()) {
  let node = RegistryNode { ..valid_inserted_node(), global_state_cs: cs }
  let accepted = is_inserted_registry_node(
    node,
    node.key,
    node.next,
    node.minting_logic_script,
  )
  let len = bytearray.length(cs)
  accepted == ( len == 28 || len == 0 )
}

// The same four fields on the OTHER writer. The update path is the one an
// issuer can drive at will after registration, so it carries the same bounds.

test prop_update_bounds_transfer_credential(hash via any_hash_length()) {
  let original = updatable_node()
  let new = RegistryNode { ..original, transfer_logic_script: Script(hash) }
  is_field_updated_registry_node(new, original) == (
    bytearray.length(hash) == 28
  )
}

test prop_update_bounds_third_party_credential(hash via any_hash_length()) {
  let original = updatable_node()
  let new = RegistryNode { ..original, third_party_logic_script: Script(hash) }
  is_field_updated_registry_node(new, original) == (
    bytearray.length(hash) == 28
  )
}

test prop_update_bounds_unfracking_hook_script_form(hash via any_hash_length()) {
  let original = updatable_node()
  let new = RegistryNode { ..original, unfracking_logic_script: Script(hash) }
  is_field_updated_registry_node(new, original) == (
    bytearray.length(hash) == 28
  )
}

test prop_update_bounds_unfracking_hook_vkey_form(hash via any_hash_length()) {
  let original = updatable_node()
  let new = RegistryNode {
    ..original,
    unfracking_logic_script: VerificationKey(hash),
  }
  let len = bytearray.length(hash)
  is_field_updated_registry_node(new, original) == ( len == 28 || len == 0 )
}

test prop_update_bounds_global_state_cs(cs via any_hash_length()) {
  let original = updatable_node()
  let new = RegistryNode { ..original, global_state_cs: cs }
  let len = bytearray.length(cs)
  is_field_updated_registry_node(new, original) == ( len == 28 || len == 0 )
}

// The properties above are biconditionals, so their ACCEPT half only bites on
// a run where the fuzzer happens to draw exactly 28 bytes. These pin the
// boundary deterministically — one length either side of the bound, plus the
// two legal optional forms — so neither half can pass vacuously.

/// A hash of exactly `n` bytes.
fn hash_of_length(n: Int) -> ByteArray {
  bytearray.take(
    list.foldr(
      list.range(1, 5),
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

test hash_of_length_builds_the_stated_size() {
  // Sanity on the helper, so the boundary tests below cannot pass because it
  // silently returned something shorter than asked for.
  and {
    (bytearray.length(hash_of_length(0)) == 0)?,
    (bytearray.length(hash_of_length(27)) == 27)?,
    (bytearray.length(hash_of_length(28)) == 28)?,
    (bytearray.length(hash_of_length(29)) == 29)?,
    (bytearray.length(hash_of_length(64)) == 64)?,
  }
}

fn insert_accepts_transfer_hash(n: Int) -> Bool {
  let node = RegistryNode {
    ..valid_inserted_node(),
    transfer_logic_script: Script(hash_of_length(n)),
  }
  is_inserted_registry_node(
    node,
    node.key,
    node.next,
    node.minting_logic_script,
  )
}

test insert_transfer_credential_accepts_exactly_28_bytes() {
  and {
    !insert_accepts_transfer_hash(0)?,
    !insert_accepts_transfer_hash(27)?,
    insert_accepts_transfer_hash(28)?,
    !insert_accepts_transfer_hash(29)?,
    !insert_accepts_transfer_hash(64)?,
  }
}

fn update_accepts_unfracking_vkey(n: Int) -> Bool {
  let original = updatable_node()
  let new = RegistryNode {
    ..original,
    unfracking_logic_script: VerificationKey(hash_of_length(n)),
  }
  is_field_updated_registry_node(new, original)
}

// The optional hook: BOTH legal forms accepted, everything between rejected.
// This is the test a "cap everything at 28" change would break, which is why
// it is here.
test update_unfracking_hook_accepts_both_legal_forms() {
  and {
    update_accepts_unfracking_vkey(0)?,
    !update_accepts_unfracking_vkey(27)?,
    update_accepts_unfracking_vkey(28)?,
    !update_accepts_unfracking_vkey(29)?,
    !update_accepts_unfracking_vkey(64)?,
  }
}
