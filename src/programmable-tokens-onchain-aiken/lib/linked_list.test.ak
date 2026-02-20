// Unit tests for linked list validation logic
use cardano/address.{Script}
use linked_list.{is_inserted_directory_node, is_updated_directory_node}
use types.{RegistryNode}
use utils.{bytearray_lt}

// Helper to create a test address
// fn test_address() -> Address {
//   Address { payment_credential: Script(#"aabbccdd"), stake_credential: None }
// }

// Test is_updated_directory_node
test is_updated_directory_node_works() {
  let original_key = #"aa"
  let insert_key = #"bb"

  // let next_key = #"cc"
  let node =
    RegistryNode {
      key: original_key,
      next: insert_key,
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  is_updated_directory_node(node, original_key, insert_key)
}

// Test is_updated_directory_node negative
test is_updated_directory_node_negative() {
  let original_key = #"aa"
  let insert_key = #"bb"
  let wrong_key = #"dd"

  let node =
    RegistryNode {
      key: original_key,
      next: wrong_key,
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  !is_updated_directory_node(node, original_key, insert_key)
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
// NEW-1: is_updated_directory_node does NOT preserve datum fields
//
// During a RegistryInsert, the covering node's output is validated by
// is_updated_directory_node, which only checks key and next.
// transfer_logic_script, third_party_transfer_logic_script, and
// global_state_cs can be SILENTLY MODIFIED.
//
// Attack scenario: attacker performs a RegistryInsert to register a new
// (worthless) token. In the covering node output, the attacker changes
// transfer_logic_script to a permissive script they control. All tokens
// of the pre-existing registered policy (under the covering node) can
// then be transferred without proper authorization.
// ========================================================================

/// Demonstrates that transfer_logic_script can be swapped during insert.
/// The attacker replaces the original transfer logic with their own script.
test is_updated_directory_node_allows_transfer_logic_swap() {
  let original_key = #"aa"
  let insert_key = #"bb"

  // The "updated" covering node has a COMPLETELY DIFFERENT transfer_logic_script.
  // is_updated_directory_node PASSES because it only checks key and next.
  let tampered_node =
    RegistryNode {
      key: original_key,
      next: insert_key,
      transfer_logic_script: Script(#"deadbeef"),
      // ^^^ ATTACKER'S SCRIPT — original was Script(#"11")
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"",
    }

  // This SHOULD fail but PASSES — the vulnerability
  is_updated_directory_node(tampered_node, original_key, insert_key)
}

/// Demonstrates that third_party_transfer_logic_script can be swapped.
/// The attacker replaces the seize/freeze logic with their own script.
test is_updated_directory_node_allows_third_party_logic_swap() {
  let original_key = #"aa"
  let insert_key = #"bb"

  let tampered_node =
    RegistryNode {
      key: original_key,
      next: insert_key,
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"deadbeef"),
      // ^^^ ATTACKER'S SCRIPT — original was Script(#"22")
      global_state_cs: #"",
    }

  is_updated_directory_node(tampered_node, original_key, insert_key)
}

/// Demonstrates that global_state_cs can be tampered during insert.
test is_updated_directory_node_allows_global_state_swap() {
  let original_key = #"aa"
  let insert_key = #"bb"

  let tampered_node =
    RegistryNode {
      key: original_key,
      next: insert_key,
      transfer_logic_script: Script(#"11"),
      third_party_transfer_logic_script: Script(#"22"),
      global_state_cs: #"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead",
      // ^^^ TAMPERED — original was #""
    }

  is_updated_directory_node(tampered_node, original_key, insert_key)
}
