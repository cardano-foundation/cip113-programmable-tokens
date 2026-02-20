use aiken/collection/list
// Issuance CBOR Hex Reference NFT Minting Policy
// Simple one-shot minting policy to create a reference NFT that marks the UTxO
// containing the issuance script template bytes (prefix and postfix)
// Migrated from SmartTokens.Contracts.IssuanceCborHex

use cardano/address
use cardano/assets.{PolicyId, flatten}
use cardano/transaction.{OutputReference, Transaction}
use types.{issuance_cbor_hex_token_name}

validator issuance_cbor_hex_mint(
  utxo_ref: OutputReference,
  always_fail_hash: ByteArray,
) {
  mint(_redeemer: Data, own_policy: PolicyId, self: Transaction) {
    trace @"Starting issuance_cbor_hex_mint validation"
    // Must consume the one-shot UTxO
    let consumed =
      list.any(self.inputs, fn(input) { input.output_reference == utxo_ref })

    // Get all minted tokens from this policy
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
    // Find the output with address equal to the always-fail address and containing the minted NFT
    expect Some(nft_output) =
      list.find(self.outputs, fn(output) { output.address == expected_address })
    expect
      assets.has_nft_strict(
        nft_output.value,
        own_policy,
        issuance_cbor_hex_token_name,
      )
    // 
    and {
      // One-shot: the specified UTxO must be consumed
      consumed?,
      // Token name must be "IssuanceCborHex"
      (tn == issuance_cbor_hex_token_name)?,
      // Exactly 1 token minted
      (qty == 1)?,
      // NFT must be locked at the always-fail address with no stake credential
      (nft_output.address == expected_address)?,
    }
  }

  else(_) {
    fail
  }
}
