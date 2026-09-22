//// Transfer Stake Validator
////
//// The withdraw-0 validator every ordinary programmable-token TRANSFER is
//// dispatched to. PLB runs once per spent input and requires the dispatcher
//// (`programmable_logic_global_cred`) named in the protocol-params datum; the dispatcher, under a
//// `TransferAct` redeemer, requires THIS script's withdraw-0 against the hash
//// baked into it. This script then runs ONCE per transaction and enforces the
//// transfer invariants over the whole transaction: registry proofs,
//// token module transfer-logic invocation, value containment.
////
//// It reads no PROTOCOL-PARAMS datum — `programmable_logic_base_cred`,
//// `registry_node_cs` and the seizure datum bound are compile-time parameters —
//// so an ordinary transfer resolves the protocol-params reference input exactly
//// once, in PLB, per input. It still reads the registry node it proves against
//// and the output datums it bounds.
////
//// It is the hot path — every transfer references it, so every byte here is
//// a reference-script fee paid on every transfer, forever. That is why it
//// carries NOTHING else: the third-party (seize) and unfracking paths have
//// their own withdraw-0 validators (`third_party`, `unfracking`), each
//// dispatched to by `programmable_logic_global` (`ThirdPartyAct`,
//// `UnfrackingAct`), and this validator has no redeemer switch at all.

use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use programmable_logic/transfer as invariants
use registry_node.{new_registry_node_getter}
use types.{TransferRedeemer}

validator transfer(
  programmable_logic_base_cred: Credential,
  registry_node_cs: PolicyId,
  max_inline_datum_bytes: Int,
) {
  withdraw(redeemer: TransferRedeemer, _account: Credential, self: Transaction) {
    trace @"Starting transfer validation"

    let TransferRedeemer { proofs } = redeemer

    // Getter for registry nodes in reference inputs (proof walk).
    let get_registry_node = new_registry_node_getter(
      registry_node_cs,
      0,
      self.reference_inputs,
      fn(_) { fail },
    )

    invariants.validate_transfer(
      self,
      programmable_logic_base_cred,
      get_registry_node,
      proofs,
      max_inline_datum_bytes,
    )
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
