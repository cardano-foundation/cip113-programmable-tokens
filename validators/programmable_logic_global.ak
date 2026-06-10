//// Programmable Logic Global Stake Validator
//// This is the core CIP-113 validator that coordinates all programmable token transfers
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)

use aiken/crypto.{ScriptHash}
use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId} as value
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use pairs
use programmable_logic/params.{with_programmable_logic_params}
use programmable_logic/third_party.{validate_3rd_party}
use programmable_logic/transfer.{validate_transfer}
use registry_node.{new_registry_node_getter}
use types.{
  ProgrammableLogicGlobalRedeemer, ThirdPartyAct, TransferAct, UnfrackingAct,
}

validator programmable_logic_global(
  params_policy: PolicyId,
  /// Script hash of the standalone `unfracking_global` withdraw-0
  /// validator (Finding 17). Baked in at deployment time: compile
  /// unfracking_global first, then apply its hash here. The Unfracking
  /// invariants live entirely in that script — see its module docs for
  /// why the logic is delegated rather than inlined.
  unfracking_script: ScriptHash,
) {
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
      // reshape of the holder's own PLB UTxOs. The invariants are
      // enforced by the standalone unfracking_global withdraw-0
      // validator; PLG only gates on its presence so the hot-path
      // reference script stays small.
      UnfrackingAct ->
        pairs.has_key_or_fail(self.withdrawals, Script(unfracking_script))
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
