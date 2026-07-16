//// Programmable Logic Global Stake Validator
//// This is the core CIP-113 validator that coordinates all programmable token transfers
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use pairs
use programmable_logic/params.{
  prog_logic_cred_field, registry_node_cs_field, unfracking_cred_field,
  with_protocol_params_fields,
}
use programmable_logic/third_party.{validate_3rd_party}
use programmable_logic/transfer.{validate_transfer}
use registry_node.{new_registry_node_getter}
use types.{
  ProgrammableLogicGlobalRedeemer, ThirdPartyAct, TransferAct, UnfrackingAct,
}

validator programmable_logic_global(params_policy: PolicyId) {
  withdraw(
    redeemer: ProgrammableLogicGlobalRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_global validation"

    // Locate the protocol-params datum once; each redeemer branch then
    // extracts only the fields it needs (cheaper than deserialising the
    // whole record, which validates every field on every run).
    let fields <- with_protocol_params_fields(
      self.reference_inputs,
      params_policy,
    )

    // Pre-construct a getter for registry nodes in reference inputs, to avoid
    // repeatedly doing it in loops. Built BEFORE the redeemer match: the
    // construction is shared by Transfer/ThirdParty, and hoisting it keeps
    // the script ~30 bytes smaller than duplicating the call per branch —
    // the Unfracking branch pays a few unused closure allocations instead,
    // which is the cheaper trade for the hot path.
    let get_registry_node = new_registry_node_getter(
      registry_node_cs_field(fields),
      0,
      self.reference_inputs,
      fn(_) { fail },
    )

    when redeemer is {
      TransferAct { proofs } ->
        validate_transfer(
          self,
          prog_logic_cred_field(fields),
          get_registry_node,
          proofs,
        )

      ThirdPartyAct { registry_node_idx, outputs_start_idx } ->
        validate_3rd_party(
          self,
          prog_logic_cred_field(fields),
          get_registry_node(registry_node_idx),
          outputs_start_idx,
        )

      // Finding 17: holder-driven UTxO redistribution. No registry node,
      // no proofs, no substandard logic — purely a value-preserving
      // reshape of the holder's own PLB UTxOs. The invariants are
      // enforced by the standalone unfracking withdraw-0
      // validator, whose credential lives in the protocol-params datum
      // (field 2 — read only by this branch); PLG only gates on its
      // presence so the hot-path reference script stays small.
      UnfrackingAct ->
        pairs.has_key_or_fail(self.withdrawals, unfracking_cred_field(fields))
    }
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
