use aiken/builtin
use aiken/collection/list
// Example Transfer Logic - Simple permissioned transfer
// Migrated from SmartTokens.Contracts.ExampleTransferLogic

use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, flatten, quantity_of}
use cardano/transaction.{Input, Transaction, Withdraw}
use types.{BlacklistProof, NonmembershipProof}
use utils



// // Simple example: only allow transfers signed by a specific credential
// validator issuer_admin_contract(permitted_cred: Credential) {
//   withdraw(_redeemer: Data, _account: Credential, self: Transaction) {
//     // This example transfer logic simply checks that a specific credential
//     // has authorized the transfer

//     when permitted_cred is {
//       VerificationKey(pkh) ->
//         // Check that the transaction is signed by this public key
//         list.has(self.extra_signatories, pkh)
//       Script(script_hash) -> {
//         // For script credentials, check that the script is invoked via withdrawals
//         let script_cred = Script(script_hash)
//         list.any(
//           self.withdrawals,
//           fn(wdrl) {
//             let Pair(cred, _amount) = wdrl
//             cred == script_cred
//           },
//         )
//       }
//     }
//   }

/// Issuer admin contract that allows transfers signed by a permitted credential
/// AND enforces asset name consistency to prevent policy ID collisions
///
/// This validator solves the problem where multiple tokens from the same admin
/// would have the same policy ID. By including the asset_name as a parameter,
/// each token gets a unique script hash, resulting in unique policy IDs.
///
/// **Mainnet Production Notes:**
/// - This validator is parameterized with both admin credential AND asset name
/// - The asset name parameter ensures each token has a unique policy ID
/// - Validation checks that minted tokens match the expected asset name
/// - Seize operations (no minting) bypass asset name validation
///
/// @param permitted_cred - The credential authorized to control this token (admin)
/// @param asset_name - The token name this contract is bound to (prevents reuse)
validator issuer_admin_contract(
  permitted_cred: Credential,
  asset_name: ByteArray,
) {
  withdraw(_redeemer: Data, _account: Credential, self: Transaction) {
    // ============================================================
    // AUTHORIZATION CHECK
    // ============================================================
    // Verify that the transaction is authorized by the permitted credential
    // This ensures only the admin can mint/burn/seize tokens
    let authorized =
      when permitted_cred is {
        VerificationKey(pkh) ->
          // For public key credentials: verify signature in extra_signatories
          list.has(self.extra_signatories, pkh)
        Script(script_hash) -> {
          // For script credentials: verify script was invoked via withdrawals
          let script_cred = Script(script_hash)
          list.any(
            self.withdrawals,
            fn(wdrl) {
              let Pair(cred, _amount) = wdrl
              cred == script_cred
            },
          )
        }
      }
    // ============================================================
    // ASSET NAME VALIDATION (prevents policy ID collision)
    // ============================================================
    // This check ensures that if minting is happening, the asset name matches
    // the parameter. This binds the contract to a specific token and prevents
    // the same contract from being reused for different tokens.
    //
    // Why this works:
    // - self.mint contains all tokens being minted in this transaction
    // - flatten() converts Value type to list of (PolicyId, AssetName, Quantity)
    // - We check that at least one minted token has token_name == asset_name
    // - If no minting happens (e.g., seize operations), validation passes
    let mint_validation =
      if list.length(flatten(self.mint)) > 0 {
        // Minting is happening → validate asset name matches
        list.any(
          flatten(self.mint),
          fn(token) {
            let (_policy_id, token_name, _quantity) = token
            token_name == asset_name
          },
        )
      } else {
        // No minting (e.g., seize operations) → validation passes
        // This allows seize operations to work without requiring minting
        True
      }
    // Both checks must pass
    and {
      authorized?,
      mint_validation?,
    }
  }

  // Reject all other redeemer types
  else(_) {
    fail
  }
}

/// Extract credential hashes from inputs with the programmable logic base credential
/// This builds the list of "witnesses" that need to be validated against the blacklist
fn extract_required_witnesses(
  inputs: List<Input>,
  prog_base_cred: Credential,
) -> List<ByteArray> {
  list.foldr(
    inputs,
    [],
    fn(input, acc) {
      if input.output.address.payment_credential == prog_base_cred {
        // Extract the staking credential hash
        when input.output.address.stake_credential is {
          Some(Inline(cred)) ->
            when cred is {
              VerificationKey(pkh) -> [pkh, ..acc]
              Script(script_hash) -> [script_hash, ..acc]
            }
          _ -> acc
        }
      } else {
        acc
      }
    },
  )
}

/// Validate that none of the witnesses are in the blacklist
/// For each witness, we check the corresponding proof which points to a covering node
/// in the blacklist. The proof is valid if: nodeKey < witnessKey < nodeNext
fn validate_witnesses(
  blacklist_node_cs: PolicyId,
  proofs: List<BlacklistProof>,
  reference_inputs: List<Input>,
  witnesses: List<ByteArray>,
) -> Bool {
  // Convert reference inputs to an indexed lookup (using list index)
  let validate_pair =
    fn(witness: ByteArray, proof: BlacklistProof) -> Bool {
      let NonmembershipProof { node_idx } = proof
      // Get the reference input at the specified index
      expect Some(ref_input) = list.at(reference_inputs, node_idx)

      // Extract and validate the blacklist node
      let node_output = ref_input.output

      // Verify the node has the blacklist currency symbol (authenticity check)
      expect
        quantity_of(node_output.value, blacklist_node_cs, "") > 0 || // Check for any token from this policy (some implementations use token names)
        list.any(
          flatten(node_output.value),
          fn(asset) {
            let (cs, _tn, _qty) = asset
            cs == blacklist_node_cs
          },
        )

      // Extract the datum which should be a BlacklistNode
      let datum_data = utils.expect_inline_datum(node_output)
      expect node: types.BlacklistNode = datum_data

      // Verify non-membership: nodeKey < witnessKey < nodeNext
      // This proves the witness is NOT in the blacklist
      builtin.less_than_bytearray(node.key, witness) && builtin.less_than_bytearray(
        witness,
        node.next,
      )
    }

  // Zip witnesses with proofs and validate each pair
  list.map2(witnesses, proofs, validate_pair) |> list.all(fn(x) { x })
}

/// Check if this is a rewarding script (withdraw-zero trick)
fn is_rewarding_script(
  redeemers: Pairs<transaction.ScriptPurpose, transaction.Redeemer>,
  account: Credential,
) -> Bool {
  list.any(
    redeemers,
    fn(pair) {
      let Pair(purpose, _redeemer) = pair
      when purpose is {
        Withdraw(cred) -> cred == account
        _ -> False
      }
    },
  )
}

// Freeze-and-seize transfer logic validator
// This validates transfers against a blacklist
validator transfer(
  programmable_logic_base_cred: Credential,
  blacklist_node_cs: PolicyId,
) {
  withdraw(proofs: List<BlacklistProof>, account: Credential, self: Transaction) {
    // 2. Extract all credential hashes from programmable logic base inputs
    let witnesses =
      extract_required_witnesses(self.inputs, programmable_logic_base_cred)

    and {
      // 1. Verify this is invoked as a rewarding script (withdraw-zero trick)
      is_rewarding_script(self.redeemers, account),
      // 3. Validate that all witnesses are NOT in the blacklist
      validate_witnesses(
        blacklist_node_cs,
        proofs,
        self.reference_inputs,
        witnesses,
      ),
    }
  }

  else(_) {
    fail
  }
}
