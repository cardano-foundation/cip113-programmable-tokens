use aiken/builtin
use aiken/collection/list
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{flatten}
use cardano/transaction.{Transaction, Withdraw}
use types.{IssuanceCborHex, issuance_cbor_hex_token_name}
use utils.{apply_hashed_parameter, expect_inline_datum}

// ------------------------------------------------------------
// Utilities
// ------------------------------------------------------------

fn concat_bytes(a: ByteArray, b: ByteArray) -> ByteArray {
  builtin.append_bytearray(a, b)
}

fn credential_authorized(
  permitted_cred: Credential,
  tx: Transaction,
) -> Bool {
  when permitted_cred is {
    VerificationKey(pkh) ->
      list.has(tx.extra_signatories, pkh)

    Script(script_hash) -> {
      let script_cred = Script(script_hash)

      list.any(
        tx.withdrawals,
        fn(wdrl) {
          let Pair(cred, _) = wdrl
          cred == script_cred
        },
      )
    }
  }
}

fn withdraw_script_executed(
  redeemers: Pairs<transaction.ScriptPurpose, transaction.Redeemer>,
  expected_hash: ByteArray,
) -> Bool {
  list.any(
    redeemers,
    fn(pair) {
      let Pair(purpose, _) = pair
      when purpose is {
        Withdraw(Script(hash)) -> hash == expected_hash
        _ -> False
      }
    },
  )
}

fn find_issuance_cbor_hex_params(tx: Transaction) -> IssuanceCborHex {
  // Find the reference input that holds the IssuanceCborHex NFT
  // We search by the well-known token name "IssuanceCborHex"
  expect Some(ref_input) =
    list.find(
      tx.reference_inputs,
      fn(input) {
        let tokens = flatten(input.output.value)
        list.any(
          tokens,
          fn(token) {
            let (_, tn, _qty) = token
            tn == issuance_cbor_hex_token_name
          },
        )
      },
    )

  // Extract and decode the IssuanceCborHex datum from that reference input
  let datum = expect_inline_datum(ref_input.output)
  expect issuance_cbor: IssuanceCborHex = datum
  issuance_cbor
}

// ------------------------------------------------------------
// Issuer Admin Validator
// ------------------------------------------------------------

validator issuer_admin_contract(
  permitted_cred: Credential,
  asset_name: ByteArray,
  issuance_prefix: ByteArray,
  issuance_postfix: ByteArray,
  programmable_base_hash: ByteArray,
) {
  withdraw(
    withdraw_script_hash: ByteArray,
    _account: Credential,
    self: Transaction,
  ) {
    let authorized =
      credential_authorized(permitted_cred, self)

    let withdraw_ok =
      withdraw_script_executed(self.redeemers, withdraw_script_hash)

    // Load the canonical issuance prefix/postfix from the on-chain
    // IssuanceCborHex reference UTxO to avoid relying on arbitrary
    // parameters.
    let issuance_cbor = find_issuance_cbor_hex_params(self)
    let onchain_prefix = issuance_cbor.prefix_cbor_hex
    let onchain_postfix = issuance_cbor.postfix_cbor_hex

    // Sanity-check that the passed parameters match the on-chain values
    let prefix_matches = onchain_prefix == issuance_prefix
    let postfix_matches = onchain_postfix == issuance_postfix

    // Derive the expected issuance policy ID using the same
    // prefix / hashed_param / postfix structure as the protocol.
    // For this substandard, the hashed_param is the concatenation of:
    //   programmable_base_hash || withdraw_script_hash
    let hashed_param =
      concat_bytes(programmable_base_hash, withdraw_script_hash)

    let derived_policy_id =
      apply_hashed_parameter(
        onchain_prefix,
        onchain_postfix,
        hashed_param,
      )

    let mint = flatten(self.mint)

    let mint_valid =
      if list.length(mint) == 0 {
        // Seize (no mint) allowed
        True
      } else {
        // When minting, enforce that there is exactly one asset entry
        // and that it matches the derived policy ID and bound asset name.
        when list.head(mint) is {
          Some((policy_id, token_name, qty)) ->
            list.length(mint) == 1
              && policy_id == derived_policy_id
              && token_name == asset_name
              && qty > 0
          None -> False
        }
      }

    and {
      authorized,
      withdraw_ok,
      prefix_matches,
      postfix_matches,
      mint_valid,
    }
  }

  else(_) {
    fail
  }
}
