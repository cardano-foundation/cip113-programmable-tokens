//// Programmable Logic Global Stake Validator
//// This is the core CIP-113 validator that coordinates all programmable token transfers
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use programmable_logic/params.{with_programmable_logic_params}
use programmable_logic/third_party.{validate_3rd_party}
use programmable_logic/transfer.{validate_transfer}
use programmable_logic/unfracking.{validate_unfracking}
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

    // Extract protocol parameters from reference inputs
    let registry_node_policy, prog_logic_cred <- with_programmable_logic_params(
      self.reference_inputs,
      params_policy,
    )

    // Pre-construct a getter for registry nodes in reference inputs, to avoid
    // repeatedly doing it in loops.
    let get_registry_node = new_registry_node_getter(
      registry_node_policy,
      0,
      self.reference_inputs,
      fn(_) { fail },
    )

    when redeemer is {
      TransferAct { proofs } ->
        validate_transfer(self, prog_logic_cred, get_registry_node, proofs)

      ThirdPartyAct { registry_node_idx, outputs_start_idx } ->
        validate_3rd_party(
          self,
          prog_logic_cred,
          get_registry_node(registry_node_idx),
          outputs_start_idx,
        )

      // Finding 17: holder-driven UTxO redistribution. No registry node,
      // no proofs, no substandard logic — purely a value-preserving
      // reshape of the holder's own PLB UTxOs.
      UnfrackingAct -> validate_unfracking(self, prog_logic_cred)
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
