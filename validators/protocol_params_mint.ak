use aiken/collection/list
use assets.{has_policy_nft_strictly} as my_assets
// Protocol Parameters Minting Policy
// One-shot minting policy for the protocol parameters NFT
// Migrated from SmartTokens.Contracts.ProtocolParams
//
// This validator ensures:
// 1. The specified UTXO is consumed (one-shot minting)
// 2. Exactly one token is minted with the correct token name
// 3. The token is sent to an always-fail address with an inline datum containing ProgrammableLogicGlobalParams

use cardano/address
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use programmable_logic/params.{
  ProgrammableLogicGlobalParams, protocol_params_token,
}

validator protocol_params_mint(
  utxo_ref: OutputReference,
  always_fail_hash: ByteArray,
) {
  mint(_redeemer: Data, own_policy: PolicyId, self: Transaction) {
    trace @"Starting protocol_params_mint validation"
    // Check 1: This is a one-shot minting policy - must spend the specified UTXO
    expect
      list.any(self.inputs, fn(input) { input.output_reference == utxo_ref })

    // Check 2: Get all minted tokens from this policy
    // Token name must be "ProtocolParams"
    expect has_policy_nft_strictly(self.mint, own_policy, protocol_params_token)

    // The always-fail address where the NFT must be locked
    let expected_address = address.from_script(always_fail_hash)
    // Find the output at the always-fail address
    expect Some(nft_output) =
      list.find(
        self.outputs,
        fn(output) {
          assets.has_nft_strict(output.value, own_policy, protocol_params_token)
        },
      )
    expect InlineDatum(datum) = nft_output.datum
    expect _params: ProgrammableLogicGlobalParams = datum

    // NFT must be locked at the always-fail address
    (nft_output.address == expected_address)?
  }

  else(_) {
    fail
  }
}
