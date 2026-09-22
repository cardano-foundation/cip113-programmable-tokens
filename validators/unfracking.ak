//// Unfracking Stake Validator
////
//// Standalone withdraw-0 validator carrying the Unfracking invariants
//// (see `programmable_logic/unfracking` for the invariants themselves
//// and the rationale behind each one).
////
//// Why a separate script instead of inlining the logic in the `transfer`
//// validator?
////
//// `transfer` is the hot path: EVERY programmable-token transfer references
//// it, so every byte of it is a reference-script fee paid by every user on
//// every transfer, forever. Hosting the unfracking logic here moves its
//// cost onto the only transactions that use it — unfracking ones, which
//// reference this script INSTEAD of `transfer`, so an unfracking transaction
//// need not load the transfer reference script at all. Nothing enforces
//// that: it is the shape a builder has no reason to depart from.
////
//// Composition of an unfracking transaction (four withdraw-0s at most):
////
////   * programmable_logic_base.spend — one run per PLB input; requires the
////     dispatcher's withdraw-0, read from `programmable_logic_global_cred` in the protocol-params
////     datum. PLB does not know this validator exists.
////   * programmable_logic_global.withdraw, redeemer `UnfrackingAct` —
////     requires THIS validator's withdraw-0, against the hash baked into it
////     at compile time.
////   * unfracking.withdraw (this validator) — enforces all the
////     Unfracking invariants, INCLUDING that the acted-on policy's
////     issuer-declared `unfracking_logic_script` withdraw-0 (registry
////     node field 5) is present. Least permission by default: an unset
////     hook forbids unfracking for that policy outright.
////   * the owner's stake-script withdraw-0 (or a vkey signature) —
////     holder authorisation, same pattern as a transfer.
////
//// Security shape: this delegation is purely RESTRICTIVE. This script is the
//// delegate an `UnfrackingAct` dispatch REQUIRES; its own withdraw handler
//// runs whenever its withdrawal is present, and checks neither the
//// dispatcher nor its redeemer. Bolting its withdrawal
//// onto some other transaction (e.g. a transfer) only ADDS constraints —
//// every script present must still pass — so no new authority is created
//// in either direction.
////
//// This validator reads no PROTOCOL-PARAMS datum. `programmable_logic_base_cred`,
//// `registry_node_cs` and the seizure datum bound are compile-time parameters,
//// and its own hash is baked into `programmable_logic_global` — so there is no
//// circular dependency: compile this validator, then compile the dispatcher
//// against its hash, then name the dispatcher in the protocol-params datum. It
//// still reads the registry node's inline datum and the output datums it
//// bounds.

use aiken/collection/list as aiken_list
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{InlineDatum, Input, Transaction}
use prog_assets
use programmable_logic/unfracking as invariants
use types.{UnfrackingRedeemer}

validator unfracking(
  programmable_logic_base_cred: Credential,
  registry_node_cs: PolicyId,
  max_inline_datum_bytes: Int,
) {
  withdraw(
    redeemer: UnfrackingRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting unfracking validation"

    let UnfrackingRedeemer { registry_node_idx, outputs_start_idx } = redeemer

    let registry_node = locate_registry_node(
      self.reference_inputs,
      registry_node_idx,
      registry_node_cs,
    )

    invariants.validate_unfracking(
      self,
      programmable_logic_base_cred,
      registry_node,
      outputs_start_idx,
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

/// Resolve the acted-on policy's registry node from the reference input
/// at the redeemer-hinted index, authenticated by the registry NFT
/// policy (first non-ada asset must be a registry-node NFT — same
/// authentication as `registry_node.new_registry_node_getter`).
fn locate_registry_node(
  reference_inputs: List<Input>,
  registry_node_idx: Int,
  registry_node_cs: PolicyId,
) -> Data {
  let node_ref = aiken_list.expect_at(reference_inputs, registry_node_idx)
  // Load-bearing assumption (same as `registry_node.new_registry_node_getter`
  // and the reasoning in params.ak): checking the POLICY ID alone suffices
  // because registry NFTs are mint-gated by the `registry` validator's mint
  // handler, which binds the NFT asset name to the node's `key` and
  // shape-checks the datum at Insert — so any UTxO carrying this policy is a
  // genuine node whose datum fields (key, unfracking_logic_script) cannot lie.
  expect prog_assets.expect_first_policy(node_ref.output) == registry_node_cs
  expect InlineDatum(data) = node_ref.output.datum
  data
}
