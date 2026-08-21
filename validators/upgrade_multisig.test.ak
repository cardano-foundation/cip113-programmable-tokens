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

// ---------------------------------------------------------------------------
// Parameter characterization (Finding 054 — deployment-trust, not enforced)
// ---------------------------------------------------------------------------
//
// `signers` and `threshold` are compile-time parameters; the validator does not
// bounds-check them. This is a deliberate deployment-trust boundary (the script
// hash is deterministic from its parameters, so a misconfiguration is publicly
// verifiable before use, and `upgrade_multisig` is a reference authority). The
// existing `call` fixes them at ([alice, bob, carol], 2); the harness below
// varies them so the unguarded behaviour is documented rather than silent. If a
// future change decides to enforce bounds, these characterizations flip.

fn call_with(
  signers: List<ByteArray>,
  threshold: Int,
  signatories: List<ByteArray>,
) -> Bool {
  upgrade_multisig.upgrade_multisig.withdraw(
    signers,
    threshold,
    Void,
    Void,
    Transaction { ..transaction.placeholder, extra_signatories: signatories },
  )
}

// A non-positive threshold authorises with ZERO approvals — i.e. a
// permissionless authority. Recorded as current (unguarded) behaviour.
test multisig_nonpositive_threshold_authorises_with_no_signers() {
  call_with([alice, bob, carol], 0, [])
}

// A duplicated signer in the PARAMETER inflates the count, because `approvals`
// iterates `signers` (not the ledger-deduplicated `extra_signatories`): here
// alice's single signature is counted twice, so a nominal 2-of-3 is satisfied
// by ONE signer. Recorded as current (unguarded) behaviour.
test multisig_duplicate_signer_in_parameter_inflates_count() {
  call_with([alice, alice, bob], 2, [alice])
}

// A threshold greater than the number of signers can never be reached — the
// authority (and every future upgrade) is permanently unsatisfiable. Recorded
// as current (unguarded) behaviour.
test multisig_threshold_above_signer_count_never_authorises() {
  !call_with([alice, bob], 3, [alice, bob])
}
