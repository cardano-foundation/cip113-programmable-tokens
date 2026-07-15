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
use cardano/transaction.{OutputReference, Transaction, find_input}
use linked_list.{is_field_updated_registry_node, validate_directory_node_output}
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use registry_node.{RegistryNode}
use utils.{expect_inline_datum, has_currency_symbol, mint_has_policy}

validator registry_spend(protocol_params_cs: PolicyId) {
  spend(
    datum: Option<RegistryNode>,
    _redeemer: Data,
    own_ref: OutputReference,
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

    // Spending a registry node is a lifecycle action, never an issuance: its
    // own programmable token (`key`) must not be minted/burned in the same tx.
    // Hoisted above the `when` so it covers BOTH the update (None) and the
    // insert covering-node spend (Some) — registry_spend is the sole spender
    // of every node, so this is the only place the check is needed.
    expect Some(spent_node) = datum
    expect !mint_has_policy(self.mint, spent_node.key)

    when
      assets.to_dict(self.mint)
        |> dict.get(registry_node_cs)
    is {
      // A registry node NFT is minted → we are the covering-node spend of an
      // insert; `registry_mint` validates the linked-list structure.
      Some(minted_assets) -> {
        expect [Pair(_, amount)] = dict.to_pairs(minted_assets)
        amount > 0
      }
      // No registry node NFT minted → in-place update of this node.
      None -> {
        expect Some(own_input) = find_input(self.inputs, own_ref)
        expect [cont] = list.filter(
          self.outputs,
          fn(o) { has_currency_symbol(o.value, registry_node_cs) },
        )
        let new_node = validate_directory_node_output(
          cont,
          registry_node_cs,
          own_input.output.address,
        )
        and {
          is_field_updated_registry_node(new_node, spent_node),
          when spent_node.minting_logic_script is {
            Script(_) ->
              pairs.has_key(self.withdrawals, spent_node.minting_logic_script)
            VerificationKey(_) -> False
          },
        }
      }
    }
  }

  else(_) {
    fail
  }
}
