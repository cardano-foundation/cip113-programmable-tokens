//// Transfer Stake Validator
////
//// The withdraw-0 validator every ordinary programmable-token TRANSFER is
//// dispatched to: programmable_logic_base (PLB) runs once per spent input and,
//// under a `SpendViaTransfer` redeemer, requires this script's withdraw-0
//// (its credential is the `transfer_cred` field of the protocol-params datum,
//// so it is swappable in place). This script then runs ONCE per transaction
//// and enforces the transfer invariants over the whole transaction: registry
//// proofs, substandard transfer-logic invocation, value containment.
////
//// It is the hot path — every transfer references it, so every byte here is
//// a reference-script fee paid on every transfer, forever. That is why it
//// carries NOTHING else: the third-party (seize) and unfracking paths have
//// their own withdraw-0 validators (`third_party`, `unfracking`), each
//// dispatched to directly by PLB (`SpendViaThirdParty`, `SpendViaUnfracking`),
//// and this validator has no redeemer switch at all.
////
//// Lineage: this is the transfer arm of the former `programmable_logic_global`
//// coordinator (SmartTokens.Contracts.ProgrammableLogicBase,
//// `mkProgrammableLogicGlobal` in the Plutarch reference implementation),
//// which used to dispatch transfer / third-party / unfracking itself.

use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use programmable_logic/params.{
  max_inline_datum_bytes_field, prog_logic_cred_field, registry_node_cs_field,
  with_protocol_params_fields,
}
use programmable_logic/transfer as invariants
use registry_node.{new_registry_node_getter}
use types.{TransferRedeemer}

validator transfer(params_policy: PolicyId) {
  withdraw(redeemer: TransferRedeemer, _account: Credential, self: Transaction) {
    trace @"Starting transfer validation"

    let TransferRedeemer { params_idx, proofs } = redeemer

    // Locate the protocol-params datum by its witnessed reference-input
    // index and extract only the fields the transfer path reads (cheaper
    // than deserialising the whole record, which validates every field on
    // every run). `max_inline_datum_bytes` is read ONCE here and threaded down to
    // the output walk, never re-read per output.
    let fields <- with_protocol_params_fields(
      self.reference_inputs,
      params_policy,
      params_idx,
    )

    // Getter for registry nodes in reference inputs (proof walk).
    let get_registry_node = new_registry_node_getter(
      registry_node_cs_field(fields),
      0,
      self.reference_inputs,
      fn(_) { fail },
    )

    invariants.validate_transfer(
      self,
      prog_logic_cred_field(fields),
      get_registry_node,
      proofs,
      max_inline_datum_bytes_field(fields),
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
