use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Script, VerificationKey}
// Registry spending validator - allows spending registry node UTxOs
// Migrated from SmartTokens.LinkedList.SpendDirectory (pmkDirectorySpending)
//
// This validator locks all registry node UTxOs. It allows spending them
// only when registry node NFTs are being minted, which ensures that
// the registry structure is being properly maintained.

use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use linked_list.{is_field_updated_registry_node, validate_directory_node_output}
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use registry_node.{RegistryNode}
use utils.{expect_inline_datum, has_currency_symbol}

validator registry_spend(protocol_params_cs: PolicyId) {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _own_ref: Data,
    self: Transaction,
  ) {
    trace @"Starting registry_spend validation"

    // Find the protocol params UTxO in reference inputs
    // This contains the registry_node_cs we need to validate against
    expect Some(params_ref_input) = list.find(
      self.reference_inputs,
      fn(input) { has_currency_symbol(input.output.value, protocol_params_cs) },
    )

    // Extract the protocol params datum
    let params_datum = expect_inline_datum(params_ref_input.output)
    expect params: ProgrammableLogicGlobalParams = params_datum

    let registry_node_cs = params.registry_node_cs

    when
      assets.to_dict(self.mint)
        |> dict.get(registry_node_cs)
    is {
      // Check that registry node NFTs are being minted or burned in this transaction
      // This ensures we're modifying the registry structure (inserting) and the minting validator is called
      Some(minted_assets) -> {
        expect [Pair(_, amount)] = dict.to_pairs(minted_assets)
        amount > 0
      }
      // No registry node NFTs being minted or burned means we are updating a node
      None -> {
        let own_input = list.expect_find(
          self.inputs,
          fn(i) { has_currency_symbol(i.output.value, registry_node_cs) },
        )
        expect old_node: RegistryNode = expect_inline_datum(own_input.output)
        expect [cont] = list.filter(
          self.outputs,
          fn(o) { has_currency_symbol(o.value, registry_node_cs) },
        )
        let new_node = validate_directory_node_output(
          cont,
          registry_node_cs,
          own_input.output.address,
        )
        expect is_field_updated_registry_node(new_node, old_node)
        when old_node.minting_logic_script is {
          Script(_) ->
            pairs.has_key(self.withdrawals, old_node.minting_logic_script)
          VerificationKey(pkh) -> list.has(self.extra_signatories, pkh)
        }
      }
    }
  }

  else(_) {
    fail
  }
}
