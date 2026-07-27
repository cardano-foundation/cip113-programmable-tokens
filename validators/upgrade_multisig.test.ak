//// Tests for the reference M-of-N upgrade-authority validator.
//// It authorises iff at least `threshold` of the configured `signers` appear
//// in `extra_signatories`. Nothing else — structural rails live in
//// coordination_spend.

use cardano/transaction.{Transaction}
use upgrade_multisig

const alice: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const bob: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

const carol: ByteArray =
  #"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3"

const mallory: ByteArray =
  #"dededededededededededededededededededededededededededede"

fn call(signatories: List<ByteArray>) -> Bool {
  upgrade_multisig.upgrade_multisig.withdraw(
    [alice, bob, carol],
    2,
    Void,
    Void,
    Transaction { ..transaction.placeholder, extra_signatories: signatories },
  )
}

// Exactly the threshold (2 of 3) passes.
test multisig_passes_at_threshold() {
  call([alice, bob])
}

// Above threshold (3 of 3) passes.
test multisig_passes_above_threshold() {
  call([alice, bob, carol])
}

// Below threshold (1 of 3) fails.
test multisig_fails_below_threshold() fail {
  call([alice])
}

// No signers fails.
test multisig_fails_with_no_signers() fail {
  call([])
}

// Non-signers do not count toward the threshold: one real signer + an outsider
// is still only one approval.
test multisig_ignores_non_signers() fail {
  call([alice, mallory])
}

// Duplicate presence of one signer does not inflate the count (each configured
// signer is counted once via membership).
test multisig_no_double_count_from_duplicates() fail {
  call([alice, alice])
}
