use aiken/builtin
use aiken/collection/list
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{flatten}
use cardano/transaction.{Transaction, Withdraw}
use utils.{apply_hashed_parameter}

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

    // Derive the expected issuance policy ID using the same
    // prefix / hashed_param / postfix structure as the protocol.
    // For this substandard, the hashed_param is the concatenation of:
    //   programmable_base_hash || withdraw_script_hash
    let hashed_param =
      concat_bytes(programmable_base_hash, withdraw_script_hash)

    let derived_policy_id =
      apply_hashed_parameter(
        issuance_prefix,
        issuance_postfix,
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
      mint_valid,
    }
  }

  else(_) {
    fail
  }
}
