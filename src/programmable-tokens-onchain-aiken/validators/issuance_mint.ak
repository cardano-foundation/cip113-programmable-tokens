use aiken/collection/dict
use aiken/collection/list
// Programmable Token Issuance Minting Policy
// This policy handles minting and burning of registered programmable tokens
// Migrated from SmartTokens.Contracts.Issuance

use cardano/address.{Credential, Inline}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Mint, Output, ScriptPurpose, Transaction}
use registry_node.{RegistryNode}
use types.{OutputIndex, RefInput, SmartTokenMintingAction}
use utils.{expect_inline_datum}

validator issuance_mint(
  // Programmable Token Script Hash
  programmable_logic_base: Credential,
  // Registry Node Currency Symbol - used to verify registry proofs for token minting
  registry_node_cs: PolicyId,
  // <- the hash of the contract of the logic for minting.
  minting_logic_cred: Credential,
) {
  mint(
    redeemer: SmartTokenMintingAction,
    own_policy: PolicyId,
    self: Transaction,
  ) {
    // Check that the minting logic script is invoked
    let invoked_scripts =
      list.map(
        self.withdrawals,
        fn(wdrl) {
          let Pair(cred, _amount) = wdrl
          cred
        },
      )
    // Check token was or is being registered in the registry.
    // is_first_mint distinguishes registration-in-this-tx (OutputIndex) from
    // already-registered (RefInput) — this drives output validation below.
    let is_first_mint =
      when redeemer.minting_registry_proof is {
        RefInput { index } -> {
          let ref_input_opt = list.at(self.reference_inputs, index)
          expect Some(ref_input) = ref_input_opt
          expect
            verify_registry_node(ref_input.output, registry_node_cs, own_policy)?
          False
        }
        OutputIndex { index } -> {
          let output_opt = list.at(self.outputs, index)
          expect Some(output) = output_opt
          // just ensure this is a genuine first mint and no sneaky transfer AND registry update at the same time
          expect InlineDatum(datum) = output.datum
          expect current_registry_node: RegistryNode = datum
          expect
            !list.has(
              invoked_scripts,
              current_registry_node.transfer_logic_script,
            )
          expect verify_registry_node(output, registry_node_cs, own_policy)?
          True
        }
      }

    // Get the minted/burned amount for this policy
    expect Some(minted_assets) =
      assets.to_dict(self.mint) |> dict.get(own_policy)
    expect [Pair(token_name, quantity)] = minted_assets |> dict.to_pairs

    let valid_minting =
      if quantity > 0 {
        if is_first_mint {
          // First mint (registration happening in this tx via OutputIndex).
          // PLGlobal is unaware of this token — we must verify ALL minted
          // tokens land at PLB with a stake credential.
          validate_mint_outputs(
            self.outputs,
            programmable_logic_base,
            own_policy,
            token_name,
            quantity,
          )?
        } else {
          // Subsequent mint (token already registered, RefInput proof).
          let is_spend =
            list.any(
              self.inputs,
              fn(input) {
                input.output.address.payment_credential == programmable_logic_base
              },
            )
          if is_spend {
            // PLB is being spent → PLGlobal validates all invariants for
            // this token (value preservation, outputs at PLB, etc.) and
            // accounts for minting in its balance checks.
            True
          } else {
            // Pure subsequent mint, no spend — validate outputs ourselves.
            validate_mint_outputs(
              self.outputs,
              programmable_logic_base,
              own_policy,
              token_name,
              quantity,
            )?
          }
        }
      } else if quantity < 0 {
        // Burning tokens - no additional checks needed beyond the minting logic being invoked
        True
      } else {
        // Zero minting is not allowed
        fail @"Cannot mint zero tokens"
      }

    and {
      // Validate that the redeemer matches the minting logic credential
      (redeemer.minting_logic_cred == minting_logic_cred)?,
      // substandard minting invoked?
      list.has(invoked_scripts, minting_logic_cred)?,
      // Check that exactly one minting redeemer matches the minting logic credential
      // This prevents multiple concurrent mints with the same minting logic in one transaction
      single_mint_with_credential(self.redeemers, redeemer)?,
      valid_minting?,
    }
  }

  else(_) {
    fail
  }
}

/// Check that exactly one minting redeemer with the given action exists in the transaction
/// This prevents multiple concurrent mints with the same minting logic credential
///
/// The logic follows Plutarch's psingleMintWithCredential (lines 145-193):
/// 1. Scan all redeemers
/// 2. Filter for Mint purposes only
/// 3. Count how many match the given redeemer
/// 4. Ensure exactly one match exists
fn single_mint_with_credential(
  redeemers: Pairs<ScriptPurpose, Data>,
  target_redeemer: SmartTokenMintingAction,
) -> Bool {
  let target_redeemer_data: Data = target_redeemer

  let matching_count =
    list.foldl(
      redeemers,
      0,
      fn(pair, count) {
        let Pair(purpose, rdmr) = pair

        when purpose is {
          Mint(_) ->
            if rdmr == target_redeemer_data {
              count + 1
            } else {
              count
            }
          _ -> count
        }
      },
    )

  matching_count == 1
}

/// Validate that exactly `expected_qty` of the minted token ends up at
/// PLB outputs, each with an inline stake credential (owner).
fn validate_mint_outputs(
  outputs: List<Output>,
  programmable_logic_base: Credential,
  own_policy: PolicyId,
  token_name: ByteArray,
  expected_qty: Int,
) -> Bool {
  (list.foldl(
    outputs,
    0,
    fn(output, acc) -> Int {
      if output.address.payment_credential == programmable_logic_base {
        expect Some(Inline(_stake_cred)) = output.address.stake_credential
        acc + quantity_of(output.value, own_policy, token_name)
      } else {
        acc
      }
    },
  ) == expected_qty)?
}

fn verify_registry_node(
  output: Output,
  registry_node_cs: PolicyId,
  own_policy: PolicyId,
) -> Bool {
  expect assets.has_any_nft(output.value, registry_node_cs)?
  let registry_datum = expect_inline_datum(output)
  expect registry: RegistryNode = registry_datum
  expect registry.key == own_policy
  True
}
