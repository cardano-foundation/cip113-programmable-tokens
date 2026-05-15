use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
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
use types.{IssuanceCborHex, RegistryInit, RegistryInsert, RegistryRedeemer}
use utils.{
  bytearray_lt, expect_inline_datum, has_currency_symbol,
  is_programmable_token_registration,
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
      RegistryInsert { key, hashed_param } -> {
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

        // Validate that the key being inserted is a valid programmable token
        // This checks:
        // 1. The computed policy ID (from prefix + hashed_param + postfix) matches the key
        // 2. Tokens with this policy ID are being minted in this transaction
        let is_token_registered =
          is_programmable_token_registration(
            key,
            issuance_cbor.prefix_cbor_hex,
            issuance_cbor.postfix_cbor_hex,
            hashed_param,
            self.mint,
          )

        // Must mint exactly one node token with the new key
        expect validate_mint(self.mint, policy_id) == key

        // there must be exactly one node input (the covering node)
        // no need to check address as it's checked at RegistryInit and in the outputs of the the Insert
        expect [covering_input] =
          list.filter(
            self.inputs,
            fn(input) { has_currency_symbol(input.output.value, policy_id) },
          )

        // Must have exactly one node input (the covering node)
        let covering_datum = expect_inline_datum(covering_input.output)
        expect covering_node: RegistryNode = covering_datum

        // Single-pass scan of node_outputs: validate each output's common
        // structural shape, then classify it as the updated covering node
        // or the newly inserted node. With list.length(node_outputs) == 2
        // checked below and the registry's strict ordering invariant
        // (covering_node.key < key, hence one node cannot satisfy both
        // shapes), `inserted_found && updated_found` implies exactly one
        // output of each shape.
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
          if is_inserted_directory_node(node1, key, covering_node.next) {
            node2
          } else {
            expect is_inserted_directory_node(node2, key, covering_node.next)
            node1
          }
        expect is_updated_directory_node(updated, covering_node, key)

        and {
          is_token_registered?,
          // Validate key is a valid currency symbol (28 bytes)
          (bytearray.length(key) == 28)?,
          // The covering node must cover the key to insert
          bytearray_lt(covering_node.key, key)?,
          bytearray_lt(key, covering_node.next)?,
        }
      }
    }
  }

  else(_) {
    fail
  }
}
