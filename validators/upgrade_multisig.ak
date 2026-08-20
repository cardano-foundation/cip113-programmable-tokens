//// Reference upgrade-authority validator: M-of-N multisig (trampoline-2 target).
////
//// This is ONE possible authority behind `coordination_spend`'s trampoline —
//// the credential named by `upgrade_cred` in the coordination datum. Its
//// only job is the AUTHORISATION decision: are at least `threshold` of the
//// `signers` present in the transaction? `coordination_spend` enforces every
//// structural rail (NFT continuity, value conservation, frozen fields), so this
//// script deliberately checks nothing else.
////
//// It runs as a withdraw-0 (an upgrade tx carries `Pair(this_credential, 0)` in
//// its withdrawals); `coordination_spend` requires exactly that key.
////
//// Reference status: signer set + threshold are compile-time parameters here
//// for simplicity. A production authority that wants signer ROTATION without a
//// redeploy would instead read the set from its own config UTxO (datum) — the
//// same pattern substandards use for admin lists. Because the authority is
//// itself swappable via `upgrade_cred`, either shape can be adopted later
//// without touching `coordination_spend`.

use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use cardano/transaction.{Transaction}

validator upgrade_multisig(signers: List<VerificationKeyHash>, threshold: Int) {
  withdraw(_redeemer: Data, _account: Data, self: Transaction) {
    trace @"Starting upgrade_multisig authorisation"
    let approvals = list.count(
      signers,
      fn(s) { list.has(self.extra_signatories, s) },
    )
    (approvals >= threshold)?
  }

  else(_) {
    fail
  }
}
