use aiken/collection/list
// Protocol Parameters Minting Policy
// One-shot minting policy for the protocol parameters NFT
// Migrated from SmartTokens.Contracts.ProtocolParams
//
// This validator ensures:
// 1. The specified UTXO is consumed (one-shot minting)
// 2. Exactly one token is minted with the correct token name
// 3. The token is sent to an always-fail address with an inline datum containing ProgrammableLogicGlobalParams

use cardano/address
use cardano/assets.{PolicyId, flatten}
use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use types.{ProgrammableLogicGlobalParams, protocol_params_token}

validator protocol_params_mint(
  utxo_ref: OutputReference,
  always_fail_hash: ByteArray,
) {
  mint(_redeemer: Data, own_policy: PolicyId, self: Transaction) {
    trace @"Starting protocol_params_mint validation"
    // Check 1: This is a one-shot minting policy - must spend the specified UTXO
    let consumed =
      list.any(self.inputs, fn(input) { input.output_reference == utxo_ref })

    // Check 2: Get all minted tokens from this policy
    let minted_tokens = flatten(self.mint)
    let own_minted =
      list.filter(
        minted_tokens,
        fn(token) {
          let (cs, _tn, _qty) = token
          cs == own_policy
        },
      )

    // Must mint exactly one token with the correct name and quantity
    expect [(_, tn, qty)] = own_minted

    // The always-fail address where the NFT must be locked
    let expected_address = address.from_script(always_fail_hash)
    // Find the output at the always-fail address
    expect Some(nft_output) =
      list.find(self.outputs, fn(output) { output.address == expected_address })
    expect
      assets.has_nft_strict(nft_output.value, own_policy, protocol_params_token)
    expect InlineDatum(datum) = nft_output.datum
    expect _params: ProgrammableLogicGlobalParams = datum

    and {
      // One-shot: the specified UTxO must be consumed
      consumed?,
      // Token name must be "ProtocolParams"
      (tn == protocol_params_token)?,
      // Exactly 1 token minted
      (qty == 1)?,
      // NFT must be locked at the always-fail address
      (nft_output.address == expected_address)?,
    }
  }

  else(_) {
    fail
  }
}
