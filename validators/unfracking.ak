//// Unfracking Stake Validator (v2 — registry-gated)
////
//// Standalone withdraw-0 validator carrying the Unfracking invariants
//// (see `programmable_logic/unfracking` for the invariants themselves
//// and the rationale behind each one).
////
//// Why a separate script instead of inlining the logic in
//// programmable_logic_global (PLG)?
////
//// PLG is the hot path: EVERY programmable-token transaction references
//// it, so every byte of PLG is a reference-script fee paid by every
//// user on every transfer, forever. Delegating the unfracking logic to
//// this script keeps PLG's UnfrackingAct arm to a single withdrawal
//// check and moves the remaining cost onto the only transactions that
//// use it — unfracking ones, which additionally reference this script
//// and carry one extra withdrawal.
////
//// Composition of an unfracking transaction (four withdraw-0s at most):
////
////   * programmable_logic_base.spend   — one run per PLB input; only
////     requires PLG's withdraw-0 to be present (unchanged).
////   * programmable_logic_global.withdraw, redeemer UnfrackingAct —
////     requires THIS validator's withdraw-0 to be present. PLG reads
////     this script's credential from the `unfracking_cred` field of
////     the protocol-params datum (written at deployment time).
////   * unfracking.withdraw (this validator) — enforces all the
////     Unfracking invariants, INCLUDING that the acted-on policy's
////     issuer-declared `unfracking_logic_script` withdraw-0 (registry
////     node field 5) is present. Least permission by default: an unset
////     hook forbids unfracking for that policy outright.
////   * the owner's stake-script withdraw-0 (or a vkey signature) —
////     holder authorisation, same pattern as TransferAct.
////
//// Security shape: this delegation is purely RESTRICTIVE. This script
//// alone cannot unlock PLB UTxOs — programmable_logic_base demands
//// PLG's withdrawal specifically. Conversely, bolting this script's
//// withdrawal onto some other transaction (e.g. a TransferAct) only
//// ADDS constraints — both scripts must still pass — so no new
//// authority is created in either direction.
////
//// The protocol parameters are read from the same protocol-params NFT
//// reference input PLG uses; this script never needs PLG's hash, so
//// there is no circular dependency: compile this validator, then write
//// its credential into the protocol-params datum at deployment.

use aiken/collection/list as aiken_list
use assets
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{InlineDatum, Input, Transaction}
use programmable_logic/params.{
  prog_logic_cred_field, registry_node_cs_field, with_protocol_params_fields,
}
use programmable_logic/unfracking as invariants
use types.{UnfrackingRedeemer}

validator unfracking(params_policy: PolicyId) {
  withdraw(
    redeemer: UnfrackingRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting unfracking validation"

    let UnfrackingRedeemer { params_idx, registry_node_idx, outputs_start_idx }
      = redeemer

    // Extract protocol parameters from reference inputs: the registry
    // NFT policy (field 0) to authenticate the acted-on policy's node,
    // and the PLB payment credential (field 1) — the same first-two-
    // fields span the PLG hot path reads.
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

    invariants.validate_unfracking(
      self,
      prog_logic_cred_field(fields),
      registry_node,
      outputs_start_idx,
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
  expect Some(node_ref) = aiken_list.at(reference_inputs, registry_node_idx)
  // Load-bearing assumption (same as `registry_node.new_registry_node_getter`
  // and the reasoning in params.ak): checking the POLICY ID alone suffices
  // because registry NFTs are mint-gated by `registry_mint`, which binds the
  // NFT asset name to the node's `key` and shape-checks the datum at Insert —
  // so any UTxO carrying this policy is a genuine node whose datum fields
  // (key, unfracking_logic_script) cannot lie.
  expect assets.peek_first(node_ref.output) == registry_node_cs
  expect InlineDatum(data) = node_ref.output.datum
  data
}
