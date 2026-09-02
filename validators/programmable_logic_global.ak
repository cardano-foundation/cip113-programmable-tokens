//// Programmable Logic Global — the dispatcher.
////
//// One job: given an ACTION, prove that the delegate responsible for that
//// action was invoked in this transaction. Nothing else. It holds no
//// invariants of its own, reads no datum, and touches no value.
////
//// Position in the trust chain:
////
////   programmable_logic_base --reads--> params[plg_cred] --requires--> THIS
////     --requires--> transfer | third_party | unfracking
////
//// PLB proves *a* dispatcher ran — the one the protocol-params datum currently
//// names. This validator turns that into *the right delegate ran*, because the
//// three delegate hashes are COMPILE-TIME PARAMETERS here. That is what lets it
//// skip the params datum entirely: it does not need to look up who the delegates
//// are, it already is the statement of who they are. Upgrading the dispatch
//// layer means deploying a new instance of this validator and rewriting
//// `plg_cred` — PLB's hash, and therefore every token address, never moves.
////
//// Why the delegates stay separate scripts rather than being inlined here:
//// reference scripts are paid for, as a size-proportional fee, by every
//// transaction that loads them. Keeping `transfer`, `third_party` and
//// `unfracking` separate means an ordinary transfer loads the transfer script
//// and nothing else — it never pays for the seize or unfracking logic it does
//// not run. This validator is the small, fixed price of that separation.
////
//// Security shape: this delegation is purely RESTRICTIVE. Requiring an
//// additional withdraw-0 can only ADD constraints — every script present in a
//// transaction must still pass — so no arm can create authority, and bolting
//// this script onto some unrelated transaction grants nothing.
////
//// **Upgrade coherence (deployment responsibility, not enforceable on-chain).**
//// A script cannot read another script's parameters, so nothing here can check
//// that the hashes baked in agree with the `transfer_cred` / `third_party_cred`
//// that `issuance_mint` reads from the params datum. Replacing a delegate is
//// therefore a TWO-artifact change — new delegate, new instance of this
//// validator — landed together with the datum rewrite. See the upgrade runbook.

use aiken/crypto.{ScriptHash}
use cardano/address.{Credential, Script}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use pairs
use types.{
  ProgrammableLogicGlobalRedeemer, ThirdPartyAct, TransferAct, UnfrackingAct,
}

validator programmable_logic_global(
  transfer_hash: ScriptHash,
  third_party_hash: ScriptHash,
  unfracking_hash: ScriptHash,
) {
  withdraw(
    redeemer: ProgrammableLogicGlobalRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_global dispatch"

    // One lookup, against a hash that is part of this script's identity. A
    // redeemer naming the wrong action resolves to a delegate that is not
    // present, so it can only invalidate its own transaction.
    let required = when redeemer is {
      TransferAct -> transfer_hash
      ThirdPartyAct -> third_party_hash
      UnfrackingAct -> unfracking_hash
    }

    self.withdrawals |> pairs.has_key_or_fail(Script(required))
  }

  publish(_r: Data, c: Certificate, _s: Transaction) {
    when c is {
      RegisterCredential { .. } -> True
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
