use aiken/collection/dict
use aiken/collection/list
// Programmable Token Issuance Minting Policy
// This policy handles minting and burning of registered programmable tokens
// Migrated from SmartTokens.Contracts.Issuance

use cardano/address.{Credential, Inline}
use cardano/assets.{PolicyId}
use cardano/transaction.{Mint, Output, ScriptPurpose, Transaction}
use registry_node.{RegistryNode}
use tokens
use types.{OutputIndex, RefInput, SmartTokenMintingAction}
use utils.{expect_inline_datum}

validator issuance_mint(
  // Programmable Token Script Hash
  programmable_logic_base: Credential,
  // Registry Node Currency Symbol - used to verify registry proofs for token minting
  registry_node_cs: PolicyId,
  // <- the hash of the contract of the logic for minting.
  minting_logic_cred: Credential,
  // PLGlobal stake credential. Used as a direct delegation signal: when PLGlobal
  // is invoked (withdraw-zero), issuance_mint may delegate mint-output custody.
  plg_stake_cred: Credential,
) {
  mint(
    redeemer: SmartTokenMintingAction,
    own_policy: PolicyId,
    self: Transaction,
  ) {
    // Direct withdrawal scan: detect minting_logic_cred and plg_stake_cred in a
    // single pass over self.withdrawals (no intermediate list allocation).
    let
      minting_logic_invoked,
      plg_invoked,
    <-
      list.foldl2(
        self.withdrawals,
        False,
        False,
        fn(wdrl, m, p, return) {
          let Pair(cred, _amount) = wdrl
          return(m || cred == minting_logic_cred, p || cred == plg_stake_cred)
        },
      )

    // Registry proof determines WHO validates outputs:
    //
    //   OutputIndex → First mint. PLGlobal doesn't know or see the registry entry for this token.
    //                 issuance_mint MUST validate outputs. Qty always > 0.
    //
    //   RefInput + PLGlobal invoked → PLGlobal is mint-aware and will validate
    //                                 everything (mint AND burn). Delegate.
    //
    //   RefInput + PLGlobal not invoked → Pure subsequent mint. issuance_mint validates.
    //                                     (Burn is impossible here: tokens to burn must
    //                                      be in inputs, prog tokens live at PLB,
    //                                      spending PLB → PLGlobal invoked → delegate path.)
    let valid_minting =
      when redeemer.minting_registry_proof is {
        OutputIndex { index } -> {
          // FIRST MINT — registry node being (re-)created in this tx
          let output_opt = list.at(self.outputs, index)
          expect Some(output) = output_opt
          expect verify_registry_node(output, registry_node_cs, own_policy)
          // First mint ⇒ all minted tokens must go to PLB
          let minted = self.mint |> assets.tokens(own_policy)
          validate_mint_outputs(
            self.outputs,
            programmable_logic_base,
            own_policy,
            minted,
          )?
        }

        RefInput { index } -> {
          // ALREADY REGISTERED — verify registry node
          let ref_input_opt = list.at(self.reference_inputs, index)
          expect Some(ref_input) = ref_input_opt
          expect
            verify_registry_node(ref_input.output, registry_node_cs, own_policy)

          or {
            // Direct delegation signal: PLGlobal is being invoked.
            // PLGlobal is mint-aware (TransferAct path) and will validate
            // mint AND burn accounting.
            //
            // NOTE: PLGlobal's ThirdPartyAct path does NOT enforce custody for
            // policies other than its registry_node_idx. This delegation is
            // therefore only sound when PLGlobal runs TransferAct. The escape
            // is tracked in audit Finding 04.
            plg_invoked,
            // No PLGlobal invocation → can only be pure minting
            // (burn requires spending PLB UTxOs → PLGlobal invoked → delegate path)
            validate_mint_outputs(
              self.outputs,
              programmable_logic_base,
              own_policy,
              self.mint |> assets.tokens(own_policy),
            )?,
          }
        }
      }

    and {
      // Validate that the redeemer matches the minting logic credential
      (redeemer.minting_logic_cred == minting_logic_cred)?,
      // substandard minting invoked?
      minting_logic_invoked?,
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

/// Validate that ALL minted tokens end up at PLB outputs with stake credentials.
/// Collects tokens for `own_policy` across all PLB outputs and checks exact match.
/// Reuses `tokens.union` and `value.tokens` (battle-tested in PLGlobal).
fn validate_mint_outputs(
  outputs: List<Output>,
  programmable_logic_base: Credential,
  own_policy: PolicyId,
  expected: tokens.Tokens,
) -> Bool {
  let total_at_plb =
    list.foldl(
      outputs,
      dict.empty,
      fn(output, acc) {
        if output.address.payment_credential == programmable_logic_base {
          expect Some(Inline(_stake_cred)) = output.address.stake_credential
          tokens.union(acc, assets.tokens(output.value, own_policy))
        } else {
          acc
        }
      },
    )
  (total_at_plb == expected)?
}

fn verify_registry_node(
  output: Output,
  registry_node_cs: PolicyId,
  own_policy: PolicyId,
) -> Bool {
  // Strict: registry NFT's asset name MUST equal own_policy. This binds the
  // NFT identity to the datum key and removes implicit trust on the linked-list
  // invariant (asset_name == datum.key) enforced elsewhere.
  expect assets.has_nft(output.value, registry_node_cs, own_policy)?
  let registry_datum = expect_inline_datum(output)
  expect registry: RegistryNode = registry_datum
  registry.key == own_policy
}
