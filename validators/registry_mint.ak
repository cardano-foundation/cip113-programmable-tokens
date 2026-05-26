use aiken/collection/dict
use aiken/collection/list
// Registry minting policy - manages the linked list of registered programmable token policies
// Migrated from SmartTokens.LinkedList.MintDirectory
//
// This validator maintains a registry of programmable token policies.
// Each entry must be a valid programmable token that passes registration checks.

use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use linked_list.{
  is_inserted_directory_node, is_updated_directory_node, validate_directory_init,
  validate_directory_node_output, validate_mint,
}
use registry_node.{RegistryNode}
use types.{
  IssuanceCborHex, RegisterAndMint, RegisterOnly, RegistryInit, RegistryInsert,
  RegistryRedeemer,
}
use utils.{
  expect_inline_datum, has_currency_symbol, is_programmable_token_id_valid,
  mint_has_policy,
}

validator registry_mint(
  utxo_ref: OutputReference,
  issuance_cbor_hex_cs: PolicyId,
  registry_spend_cred: Credential,
) {
  mint(redeemer: RegistryRedeemer, policy_id: PolicyId, self: Transaction) {
    trace @"Starting registry_mint validation"
    when redeemer is {
      RegistryInit -> {
        // Ensure this is a one-shot minting policy by checking that utxo_ref is spent
        let is_utxo_consumed =
          list.any(
            self.inputs,
            fn(input) { input.output_reference == utxo_ref },
          )

        // Initialize the registry with an empty origin node
        and {
          is_utxo_consumed?,
          validate_directory_init(
            self.outputs,
            self.mint,
            policy_id,
            registry_spend_cred,
          )?,
        }
      }
      RegistryInsert { key, minting_logic_script, mode } -> {
        // Find the issuance CBOR hex reference input
        expect Some(issuance_ref_input) =
          //should this be a find.any instead of find.some?
          list.find(
            self.reference_inputs,
            fn(input) {
              let tokens =
                assets.tokens(input.output.value, issuance_cbor_hex_cs)
              !dict.is_empty(tokens)
            },
          )

        // Extract the IssuanceCborHex datum
        let issuance_datum = expect_inline_datum(issuance_ref_input.output)
        expect issuance_cbor: IssuanceCborHex = issuance_datum

        // Cryptographic binding (mode-independent): the key being inserted
        // must be the policy id derived from the issuance template
        // parameterised with `minting_logic_script`. The `hashed_param`
        // for the derivation is the inner 28-byte hash of the credential,
        // extracted inside the helper.
        expect
          is_programmable_token_id_valid(
            key,
            issuance_cbor.prefix_cbor_hex,
            issuance_cbor.postfix_cbor_hex,
            minting_logic_script,
          )

        // Substandard authorises this registration regardless of mode.
        // The substandard's withdraw-0 logic must appear in tx.withdrawals.
        // This is the "proof of instance" check — replacing the old indirect
        // proof of "tokens are being minted" which transitively required
        // issuance_mint (and hence minting_logic_script) to run. Required
        // explicitly here because in `RegisterOnly` mode no programmable
        // tokens are minted and issuance_mint is never invoked.
        expect
          list.any(
            self.withdrawals,
            fn(w) {
              let Pair(cred, _amount) = w
              cred == minting_logic_script
            },
          )

        // Mode-specific mint shape:
        //   RegisterOnly      ⇒ no entries under `key` in tx.mint
        //   RegisterAndMint   ⇒ tx.mint contains an entry under `key`
        // The mode field in the redeemer is asserted here against the
        // actual `tx.mint` content (defense-in-depth #1: mode ↔ mint
        // consistency, both directions).
        //
        // Burn-only of a brand-new policy is ledger-impossible (no prior
        // tokens to burn), so `mint_has_policy` not distinguishing
        // sign of the entry is fine here. See `lib/utils.ak` for the
        // benchmark rationale behind the unified primitive.
        expect
          when mode is {
            RegisterOnly -> !mint_has_policy(self.mint, key)
            RegisterAndMint -> mint_has_policy(self.mint, key)
          }

        // Must mint exactly one node token with the new key
        expect validate_mint(self.mint, policy_id) == key

        // There must be exactly one node input (the covering node).
        // No explicit address check needed: any registry-NFT-bearing UTxO is
        // at the registry_spend address by induction (Init binds the origin's
        // address, every Insert binds its new outputs' addresses, and
        // registry_spend is the sole script that can spend those UTxOs).
        expect [covering_input] =
          list.filter(
            self.inputs,
            fn(input) { has_currency_symbol(input.output.value, policy_id) },
          )

        let covering_datum = expect_inline_datum(covering_input.output)
        expect covering_node: RegistryNode = covering_datum

        // Filter the two registry-node outputs and classify them. The destructure
        // enforces exactly two such outputs. The strict ordering invariant
        // (covering_node.key < key, asserted below) means no single output can satisfy
        // both the inserted and the updated-covering shape, so identifying which is
        // which by a single `is_inserted_directory_node` check is unambiguous.
        expect [out1,
          out2] =
          list.filter(
            self.outputs,
            fn(o) { has_currency_symbol(o.value, policy_id) },
          )

        let node1 =
          validate_directory_node_output(
            out1,
            policy_id,
            covering_input.output.address,
          )
        let node2 =
          validate_directory_node_output(
            out2,
            policy_id,
            covering_input.output.address,
          )

        let updated =
          if is_inserted_directory_node(
            node1,
            key,
            covering_node.next,
            minting_logic_script,
          ) {
            node2
          } else {
            expect
              is_inserted_directory_node(
                node2,
                key,
                covering_node.next,
                minting_logic_script,
              )
            node1
          }
        // node2 inserted ⇒ node1 is the updated covering
        is_updated_directory_node(updated, covering_node, key)
      }
    }
  }

  else(_) {
    fail
  }
}
