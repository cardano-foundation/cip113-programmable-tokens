use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction, Withdraw}
use types.{IssuanceCborHex}
use utils.{apply_hashed_parameter, expect_inline_datum}

validator issuer_admin_contract(
  permitted_cred: Credential,
  asset_name: ByteArray,
  issuance_cbor_hex_cs: PolicyId,
  //  Only need the NFT policy
  programmable_base_hash: ByteArray,
) {
  withdraw(
    withdraw_script_hash: ByteArray,
    _account: Credential,
    self: Transaction,
  ) {
    // ============================================================
    // OPTIMIZATION 1: Authorization check with early exit
    // ============================================================
    // Check authorization first - if fails, exit immediately
    let authorized =
      when permitted_cred is {
        VerificationKey(pkh) ->
          // Fast path: direct signature check
          list.has(self.extra_signatories, pkh)
        Script(script_hash) ->
          // Use any() for early exit when match found
          list.any(
            self.withdrawals,
            fn(wdrl) {
              // Direct pattern match in lambda
              when wdrl is {
                Pair(Script(hash), _) -> hash == script_hash
                _ -> False
              }
            },
          )
      }
    // Early exit if not authorized
    expect authorized

    // ============================================================
    // OPTIMIZATION 2: Withdraw script check with early exit
    // ============================================================
    let withdraw_ok =
      list.any(
        self.redeemers,
        fn(pair) {
          when pair is {
            Pair(Withdraw(Script(hash)), _) -> hash == withdraw_script_hash
            _ -> False
          }
        },
      )
    // Early exit if withdraw not executed
    expect withdraw_ok

    // ============================================================
    // OPTIMIZATION 3: Fetch IssuanceCborHex (aligned with registry_mint.ak)
    // ============================================================
    // Find reference input with issuance NFT
    // Following exact pattern from registry_mint.ak line 25
    expect Some(issuance_ref_input) =
      list.find(
        self.reference_inputs,
        fn(input) {
          // Check if this input has the issuance NFT
          let tokens = assets.tokens(input.output.value, issuance_cbor_hex_cs)
          !dict.is_empty(tokens)
        },
      )

    // Extract datum - same pattern as registry_mint.ak
    let issuance_datum = expect_inline_datum(issuance_ref_input.output)
    expect issuance_cbor: IssuanceCborHex = issuance_datum

    //  Now we have TRUSTED prefix/postfix from on-chain
    //  No need for parameter validation - removed issuance_prefix/postfix params
    // ============================================================
    // OPTIMIZATION 4: Inline policy calculation
    // ============================================================
    // Concatenate hashes inline
    let hashed_param =
      builtin.append_bytearray(programmable_base_hash, withdraw_script_hash)

    // Derive expected policy ID with trusted values
    let derived_policy_id =
      apply_hashed_parameter(
        issuance_cbor.prefix_cbor_hex,
        issuance_cbor.postfix_cbor_hex,
        hashed_param,
      )

    // ============================================================
    // OPTIMIZATION 5: Efficient mint validation
    // ============================================================
    // Flatten once and reuse
    let mint = assets.flatten(self.mint)
    let mint_length = list.length(mint)

    // Fast path: no minting (seize operation)
    if mint_length == 0 {
      True
    } else {
      // Minting path: validate single entry
      // OPTIMIZATION: Combine length check with head extraction
      expect mint_length == 1
      // Get the single minted asset
      expect Some((policy_id, token_name, qty)) = list.head(mint)
      // All conditions must match
      and {
        policy_id == derived_policy_id,
        token_name == asset_name,
        qty > 0,
      }
    }
  }

  else(_) {
    fail
  }
}
