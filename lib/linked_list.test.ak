// Unit tests for linked list validation logic
use cardano/address.{Script}
use linked_list.{
  is_field_updated_registry_node, is_inserted_directory_node,
  is_updated_directory_node,
}
use registry_node.{RegistryNode}
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
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  let updated_node = RegistryNode {
    key: original_key,
    next: insert_key,
    transfer_logic_script: Script(#"11"),
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  is_updated_directory_node(updated_node, original, insert_key)
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
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  let node = RegistryNode {
    key: original_key,
    next: wrong_key,
    transfer_logic_script: Script(#"11"),
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  !is_updated_directory_node(node, original, insert_key)
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
    third_party_transfer_logic_script: third_party_transfer_logic,
    minting_logic_script: minting_logic,
    global_state_cs: global_state,
    protected_prefixes: [],
  }

  is_inserted_directory_node(node, insert_key, next_key, minting_logic)
}

// Finding 18: a well-formed `protected_prefixes` (every entry exactly 4 bytes)
// is accepted at Insert. Spread base is the valid inserted node above; the only
// delta is the non-empty 4-byte-prefix list.
test is_inserted_directory_node_accepts_wellformed_protected_prefixes() {
  let insert_key = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let next_key = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let minting_logic = Script(
    #"44444444444444444444444444444444444444444444444444444444",
  )
  let node = RegistryNode {
    key: insert_key,
    next: next_key,
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_transfer_logic_script: Script(
      #"22222222222222222222222222222222222222222222222222222222",
    ),
    minting_logic_script: minting_logic,
    global_state_cs: #"33333333333333333333333333333333333333333333333333333333",
    // Two valid 4-byte CIP-67 label prefixes (label 100 ref NFT, label 500).
    protected_prefixes: [#"000643b0", #"001f4d70"],
  }

  is_inserted_directory_node(node, insert_key, next_key, minting_logic)
}

// Finding 18: a malformed `protected_prefixes` entry (not 4 bytes) is REJECTED
// at Insert. Only delta vs the accepting test above is the 3-byte entry.
test is_inserted_directory_node_rejects_malformed_protected_prefix() fail {
  let insert_key = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let next_key = #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let minting_logic = Script(
    #"44444444444444444444444444444444444444444444444444444444",
  )
  let node = RegistryNode {
    key: insert_key,
    next: next_key,
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_transfer_logic_script: Script(
      #"22222222222222222222222222222222222222222222222222222222",
    ),
    minting_logic_script: minting_logic,
    global_state_cs: #"33333333333333333333333333333333333333333333333333333333",
    // Malformed: 3-byte prefix (must be exactly 4).
    protected_prefixes: [#"000643"],
  }

  expect is_inserted_directory_node(node, insert_key, next_key, minting_logic)
}

// Test directory node ordering
test directory_node_ordering() {
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
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
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
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  let tampered_node = RegistryNode {
    key: #"aa",
    next: #"bb",
    transfer_logic_script: Script(#"deadbeef"),
    // ^^^ ATTACKER'S SCRIPT — original was Script(#"11")
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  is_updated_directory_node(tampered_node, original, #"bb")
}

/// third_party_transfer_logic_script swap is now REJECTED.
/// Attacker cannot replace the seize/freeze logic with their own script.
test is_updated_directory_node_rejects_third_party_logic_swap() fail {
  let original = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(#"11"),
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  let tampered_node = RegistryNode {
    key: #"aa",
    next: #"bb",
    transfer_logic_script: Script(#"11"),
    third_party_transfer_logic_script: Script(#"deadbeef"),
    // ^^^ ATTACKER'S SCRIPT — original was Script(#"22")
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  is_updated_directory_node(tampered_node, original, #"bb")
}

/// global_state_cs tampering is now REJECTED.
/// Attacker cannot swap the global state currency symbol during insert.
test is_updated_directory_node_rejects_global_state_swap() fail {
  let original = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(#"11"),
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }

  let tampered_node = RegistryNode {
    key: #"aa",
    next: #"bb",
    transfer_logic_script: Script(#"11"),
    third_party_transfer_logic_script: Script(#"22"),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead",
    protected_prefixes: [],
  }

  // ^^^ TAMPERED — original was #""
  is_updated_directory_node(tampered_node, original, #"bb")
}

test is_field_updated_registry_node_rejects_registry_nodes_differ() fail {
  let original = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    minting_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    global_state_cs: #"",
    protected_prefixes: [],
  }
  let new = RegistryNode {
    key: #"ab",
    // changing an immutable field
    next: #"cc",
    transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    third_party_transfer_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    minting_logic_script: Script(
      #"11111111111111111111111111111111111111111111111111111111",
    ),
    global_state_cs: #"",
    protected_prefixes: [],
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
    third_party_transfer_logic_script: Script(
      #"22222222222222222222222222222222222222222222222222222222",
    ),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"",
    protected_prefixes: [],
  }
  let new = RegistryNode {
    key: #"aa",
    next: #"cc",
    transfer_logic_script: Script(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ),
    third_party_transfer_logic_script: Script(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ),
    minting_logic_script: Script(#"33"),
    global_state_cs: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    protected_prefixes: [],
  }

  is_field_updated_registry_node(new, original)
}

/// A node whose three mutable fields are well-formed and which already
/// protects one CIP-67 label prefix. Used by the append-only tests below.
fn base_updatable_node() -> RegistryNode {
  RegistryNode {
    key: #"aa",
    next: #"cc",
    minting_logic_script: Script(#"33"),
    transfer_logic_script: Script(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ),
    third_party_transfer_logic_script: Script(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ),
    global_state_cs: #"",
    protected_prefixes: [#"000643b0"],
  }
}

// Finding 18 (append-only): adding a new protected prefix on update is allowed.
test is_field_updated_registry_node_allows_adding_protected_prefix() {
  let original = base_updatable_node()
  let new =
    RegistryNode { ..original, protected_prefixes: [#"000643b0", #"001f4d70"] }
  is_field_updated_registry_node(new, original)
}

// Finding 18 (append-only): dropping a previously-protected prefix must fail —
// protection cannot be revoked to enable a later seizure.
test is_field_updated_registry_node_rejects_dropping_protected_prefix() fail {
  let original = base_updatable_node()
  let new = RegistryNode { ..original, protected_prefixes: [] }
  is_field_updated_registry_node(new, original)
}

// Finding 18: a protected prefix added on update must be a 4-byte CIP-67 label.
test is_field_updated_registry_node_rejects_malformed_protected_prefix() fail {
  let original = base_updatable_node()
  let new =
    RegistryNode { ..original, protected_prefixes: [#"000643b0", #"0006"] }
  is_field_updated_registry_node(new, original)
}

// Finding 18: protected_prefixes must be strictly ascending — an unsorted list
// is rejected (even when it still contains every old prefix).
test is_field_updated_registry_node_rejects_unsorted_protected_prefixes() fail {
  let original = base_updatable_node()
  let new =
    RegistryNode { ..original, protected_prefixes: [#"001f4d70", #"000643b0"] }
  is_field_updated_registry_node(new, original)
}

// Finding 18: duplicate prefixes are rejected (strictly ascending forbids them).
test is_field_updated_registry_node_rejects_duplicate_protected_prefix() fail {
  let original = base_updatable_node()
  let new =
    RegistryNode { ..original, protected_prefixes: [#"000643b0", #"000643b0"] }
  is_field_updated_registry_node(new, original)
}
