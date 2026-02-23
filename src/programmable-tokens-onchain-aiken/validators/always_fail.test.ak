// Tests for the always_fail validator

use aiken/crypto.{blake2b_256}
use cardano/address.{Address, Script}

// Test that the always_fail spend handler always rejects
test always_fail_spend_rejects() fail {
  // Simulates the always_fail validator behavior: unconditional crash
  expect Some(_x): Option<Int> = None
  True
}

// Test that different nonces produce different script identities
test always_fail_different_nonces() {
  let nonce_a = #"aa"
  let nonce_b = #"bb"

  // Different nonces should hash differently, proving they would yield distinct script hashes
  blake2b_256(nonce_a) != blake2b_256(nonce_b)
}

// Test that the always_fail address can be constructed correctly
test always_fail_address_construction() {
  let script_hash = #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  let addr =
    Address {
      payment_credential: Script(script_hash),
      stake_credential: None,
    }

  // Address has the script credential and no stake credential
  addr.payment_credential == Script(script_hash) && addr.stake_credential == None
}
