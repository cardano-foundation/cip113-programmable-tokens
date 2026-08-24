//// Third-Party Transfer Stake Validator (seize / clawback / freeze).
////
//// Standalone withdraw-0 validator carrying the third-party-transfer
//// invariants (see `programmable_logic/third_party` for the invariants
//// themselves and the rationale behind each one).
////
//// Why a separate script instead of inlining the logic in the `transfer`
//// validator?
////
//// `transfer` is the hot path: EVERY programmable-token transfer references
//// it, so every byte of it is a reference-script fee paid by every user on
//// every transfer, forever. The third-party (administrative) path — forced
//// transfer, seizure, freeze enforcement, burn — is heavy but rare.
//// Hosting it here keeps those bytes off the transfer reference script and
//// moves their cost onto the only transactions that use them.
////
//// Dispatch: programmable_logic_base dispatches to this validator directly.
//// A `SpendViaThirdParty` base spend requires THIS validator's withdraw-0
//// (its credential is the `third_party_cred` field of the protocol-params
//// datum) — so a third-party transaction never loads the `transfer`
//// reference script at all. `unfracking` is dispatched the same way.
////
//// Security shape: this delegation is purely RESTRICTIVE and self-contained.
//// programmable_logic_base authorises exactly ONE of `transfer`, this
//// validator, or `unfracking` per spend; whichever runs enforces its full
//// invariants over the whole transaction, so authorising any one of them is
//// sound. This script reads the same protocol-params NFT reference input the
//// others use; it never needs their hashes, so there is no circular
//// dependency.

use aiken/collection/list as aiken_list
use assets
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{InlineDatum, Input, Transaction}
use programmable_logic/params.{
  max_inline_datum_bytes_field, prog_logic_cred_field, registry_node_cs_field,
  with_protocol_params_fields,
}
use programmable_logic/third_party as invariants
use types.{ThirdPartyRedeemer}

validator third_party(params_policy: PolicyId) {
  withdraw(
    redeemer: ThirdPartyRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting third-party transfer validation"

    let ThirdPartyRedeemer { params_idx, registry_node_idx, outputs_start_idx }
      = redeemer

    // Extract protocol parameters from reference inputs: the registry NFT
    // policy (field 0) to authenticate the subject policy's node, and the PLB
    // payment credential (field 1) — the same first-two-fields span the
    // transfer hot path reads.
    let fields <- with_protocol_params_fields(
      self.reference_inputs,
      params_policy,
      params_idx,
    )

    let registry_node = locate_registry_node(
      self.reference_inputs,
      registry_node_idx,
      registry_node_cs_field(fields),
    )

    invariants.validate_3rd_party(
      self,
      prog_logic_cred_field(fields),
      registry_node,
      outputs_start_idx,
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

/// Resolve the subject policy's registry node from the reference input at
/// the redeemer-hinted index, authenticated by the registry NFT policy
/// (first non-ada asset must be a registry-node NFT — same authentication
/// as `registry_node.new_registry_node_getter` and `unfracking`).
fn locate_registry_node(
  reference_inputs: List<Input>,
  registry_node_idx: Int,
  registry_node_cs: PolicyId,
) -> Data {
  expect Some(node_ref) = aiken_list.at(reference_inputs, registry_node_idx)
  // Checking the POLICY ID alone suffices because registry NFTs are
  // mint-gated by `registry_mint`, which binds the NFT asset name to the
  // node's `key` and shape-checks the datum at Insert — so any UTxO carrying
  // this policy is a genuine node whose datum fields cannot lie.
  expect assets.peek_first(node_ref.output) == registry_node_cs
  expect InlineDatum(data) = node_ref.output.datum
  data
}
