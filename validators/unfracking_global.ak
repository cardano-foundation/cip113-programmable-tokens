//// Unfracking Global Stake Validator (Finding 17)
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
//// user on every transfer, forever. Inlining the unfracking logic grew
//// PLG by ~600 bytes (~+0.009 ADA per transfer at 15 lovelace/byte);
//// delegating to this script shrinks that to ~70 bytes (~+0.001 ADA)
//// and moves the remaining cost onto the only transactions that use it
//// — unfracking ones, which additionally reference this script
//// (~1.3 KB, ~0.02 ADA) and carry one extra withdrawal.
////
//// Composition of an unfracking transaction (three scripts run):
////
////   * programmable_logic_base.spend   — one run per PLB input; only
////     requires PLG's withdraw-0 to be present (unchanged).
////   * programmable_logic_global.withdraw, redeemer UnfrackingAct —
////     requires THIS validator's withdraw-0 to be present. PLG reads
////     this script's credential from the `unfracking_cred` field of
////     the protocol-params datum (written at deployment time).
////   * unfracking_global.withdraw (this validator) — enforces all the
////     Unfracking invariants.
////
//// Security shape: this delegation is purely RESTRICTIVE. This script
//// alone cannot unlock PLB UTxOs — programmable_logic_base demands
//// PLG's withdrawal specifically. Conversely, bolting this script's
//// withdrawal onto some other transaction (e.g. a TransferAct) only
//// ADDS constraints — both scripts must still pass — so no new
//// authority is created in either direction.
////
//// The protocol parameters (notably `prog_logic_cred`, the PLB payment
//// credential) are read from the same protocol-params NFT reference
//// input PLG uses; this script never needs PLG's hash, so there is no
//// circular dependency: compile this validator, then write its
//// credential into the protocol-params datum at deployment.

use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use programmable_logic/params.{
  prog_logic_cred_field, with_protocol_params_fields,
}
use programmable_logic/unfracking.{validate_unfracking}

validator unfracking_global(params_policy: PolicyId) {
  withdraw(_redeemer: Data, _account: Credential, self: Transaction) {
    trace @"Starting unfracking_global validation"

    // Extract protocol parameters from reference inputs; only the PLB
    // payment credential (field 1) is needed — Unfracking never
    // consults the token registry.
    let fields <- with_protocol_params_fields(
      self.reference_inputs,
      params_policy,
    )

    validate_unfracking(self, prog_logic_cred_field(fields))
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
