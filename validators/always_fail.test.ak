//// Tests for the always_fail validator.
//// Invokes the validator's spend handler directly to confirm it always rejects.

use always_fail
use cardano/transaction

// Test that the always_fail spend handler rejects with a valid transaction
test always_fail_spend_rejects() fail {
  always_fail.always_fail.spend(
    #"aa",
    None,
    Void,
    #"0000000000000000000000000000000000000000000000000000000000000000",
    transaction.placeholder,
  )
}

// Test that the always_fail spend handler rejects regardless of nonce
test always_fail_spend_rejects_with_different_nonce() fail {
  always_fail.always_fail.spend(
    #"bb",
    None,
    Void,
    #"0000000000000000000000000000000000000000000000000000000000000000",
    transaction.placeholder,
  )
}

// Test that the always_fail else handler also rejects
test always_fail_else_rejects() fail {
  always_fail.always_fail.else(#"aa", Void)
}
