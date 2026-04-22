//// Programmable Logic Global Stake Validator
//// This is the core CIP-0143 validator that coordinates all programmable token transfers
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate}
use cardano/transaction.{Transaction}
use programmable_logic/params.{with_programmable_logic_params}
use programmable_logic/third_party.{validate_3rd_party}
use programmable_logic/transfer.{validate_transfer}
use registry_node.{new_registry_node_getter}
use types.{ProgrammableLogicGlobalRedeemer, ThirdPartyAct, TransferAct}

validator programmable_logic_global(params_policy: PolicyId) {
  withdraw(
    redeemer: ProgrammableLogicGlobalRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_global validation"

    // Extract protocol parameters from reference inputs
    let
      registry_node_policy,
      prog_logic_cred,
    <- with_programmable_logic_params(self.reference_inputs, params_policy)

    // Pre-construct a getter for registry nodes in reference inputs, to avoid
    // repeatedly doing it in loops.
    let get_registry_node =
      new_registry_node_getter(
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
    }
  }

  publish(_r: Data, _c: Certificate, _t: Transaction) {
    True
  }

  else(_) {
    fail
  }
}
