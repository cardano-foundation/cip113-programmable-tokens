// Unit tests for linked list validation logic
use cardano/address.{Script}
use linked_list.{is_inserted_directory_node, is_updated_directory_node}
use types.{RegistryNode}
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

  let original =
    RegistryNode {
      key: original_key,
      next: #"cc",
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  let updated_node =
    RegistryNode {
      key: original_key,
      next: insert_key,
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  is_updated_directory_node(updated_node, original, insert_key)
}

// Test is_updated_directory_node negative — wrong next key
test is_updated_directory_node_negative() {
  let original_key = #"aa"
  let insert_key = #"bb"
  let wrong_key = #"dd"

  let original =
    RegistryNode {
      key: original_key,
      next: #"cc",
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  let node =
    RegistryNode {
      key: original_key,
      next: wrong_key,
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  !is_updated_directory_node(node, original, insert_key)
}

// Test is_inserted_directory_node
test is_inserted_directory_node_works() {
  let insert_key = #"bb"
  let next_key = #"cc"
  let transfer_logic =
    Script(#"11111111111111111111111111111111111111111111111111111111")
  let third_party_transfer_logic =
    Script(#"22222222222222222222222222222222222222222222222222222222")
  let global_state = #"33333333333333333333333333333333333333333333333333333333"

  let node =
    RegistryNode {
      key: insert_key,
      next: next_key,
      transfer_logic_script: transfer_logic,
      third_party_transfer_logic_script: third_party_transfer_logic,
      global_state_cs: global_state,
    }

  is_inserted_directory_node(node, insert_key, next_key)
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
  let origin_node =
    RegistryNode {
      key: empty,
      next: empty,
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
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
  let original =
    RegistryNode {
      key: #"aa",
      next: #"cc",
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  let tampered_node =
    RegistryNode {
      key: #"aa",
      next: #"bb",
      transfer_logic_script: Script(#"deadbeef"),
      // ^^^ ATTACKER'S SCRIPT — original was Script(#"11")
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  is_updated_directory_node(tampered_node, original, #"bb")
}

/// third_party_transfer_logic_script swap is now REJECTED.
/// Attacker cannot replace the seize/freeze logic with their own script.
test is_updated_directory_node_rejects_third_party_logic_swap() fail {
  let original =
    RegistryNode {
      key: #"aa",
      next: #"cc",
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  let tampered_node =
    RegistryNode {
      key: #"aa",
      next: #"bb",
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"deadbeef"),
      // ^^^ ATTACKER'S SCRIPT — original was Script(#"22")
      global_state_cs: #"",
    }

  is_updated_directory_node(tampered_node, original, #"bb")
}

/// global_state_cs tampering is now REJECTED.
/// Attacker cannot swap the global state currency symbol during insert.
test is_updated_directory_node_rejects_global_state_swap() fail {
  let original =
    RegistryNode {
      key: #"aa",
      next: #"cc",
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  let tampered_node =
    RegistryNode {
      key: #"aa",
      next: #"bb",
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead",
      // ^^^ TAMPERED — original was #""
    }

  is_updated_directory_node(tampered_node, original, #"bb")
}
