//// Programmable Logic Base Validator
//// This validator locks all programmable token UTxOs
//// It forwards validation to the global programmable logic stake validator
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase
////
//// Upgradability in place: PLB is parameterized by the protocol-params
//// NFT policy — the protocol's only permanent anchor — instead of a
//// compile-time PLG credential. On every spend it reads the CURRENT
//// PLG credential from the protocol-params reference input's datum
//// (field 3, extracted with builtins — no whole-datum deserialisation)
//// and requires that credential's withdraw-0. Swapping PLG is therefore
//// a datum rewrite on the coordination UTxO; PLB's hash — and with it
//// every programmable token address — never changes.

use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use pairs
use programmable_logic/params

validator programmable_logic_base(params_policy: PolicyId) {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _own_ref: Data,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_base validation"

    // Locate the protocol-params NFT among the reference inputs and pull
    // the live PLG credential out of its datum. The params UTxO is already
    // a mandatory reference input on every programmable-token transaction
    // (PLG reads it), so this adds no availability requirement.
    let fields <- params.with_protocol_params_fields(
      self.reference_inputs,
      params_policy,
    )
    let plg_cred = params.prog_logic_global_cred_field(fields)

    // The programmable logic base validator simply checks that the global
    // programmable logic stake script is invoked in the transaction via the
    // withdraw-zero pattern Check that the stake credential is invoked
    self.withdrawals |> pairs.has_key_or_fail(plg_cred)
  }

  else(_) {
    fail
  }
}
