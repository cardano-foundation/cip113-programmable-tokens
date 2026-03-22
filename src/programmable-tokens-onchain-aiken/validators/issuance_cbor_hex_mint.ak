use aiken/collection/list
use assets.{has_policy_nft_strictly} as local_assets
// Issuance CBOR Hex Reference NFT Minting Policy
// Simple one-shot minting policy to create a reference NFT that marks the UTxO
// containing the issuance script template bytes (prefix and postfix)
// Migrated from SmartTokens.Contracts.IssuanceCborHex

use cardano/address
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use types.{IssuanceCborHex, issuance_cbor_hex_token_name}

validator issuance_cbor_hex_mint(
  utxo_ref: OutputReference,
  always_fail_hash: ByteArray,
) {
  mint(_redeemer: Data, own_policy: PolicyId, self: Transaction) {
    trace @"Starting issuance_cbor_hex_mint validation"
    // Must consume the one-shot UTxO
    expect
      list.any(self.inputs, fn(input) { input.output_reference == utxo_ref })

    // Exactly one NFT for policy with expected name
    expect
      has_policy_nft_strictly(
        self.mint,
        own_policy,
        issuance_cbor_hex_token_name,
      )

    // The always-fail address where the NFT must be locked
    let expected_address = address.from_script(always_fail_hash)
    // Find the output with address equal to the always-fail address and containing the minted NFT
    expect Some(nft_output) =
      list.find(
        self.outputs,
        fn(output) {
          assets.has_nft_strict(
            output.value,
            own_policy,
            issuance_cbor_hex_token_name,
          )
        },
      )
    expect InlineDatum(datum) = nft_output.datum
    expect _issuance_datum: IssuanceCborHex = datum
    // NFT must be locked at the always-fail address with no stake credential
    (nft_output.address == expected_address)?
  }

  else(_) {
    fail
  }
}
