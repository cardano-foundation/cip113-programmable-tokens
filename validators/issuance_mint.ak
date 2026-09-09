//// The PERMANENT half of issuance (issue #129, audit-3 finding 07).
////
//// This script's applied hash IS a token's policy id, so its bytes can never
//// change for a token that exists. It therefore does the two things that will
//// never change, and nothing else:
////
////   1. the token's own minting logic ran — `minting_logic_cred`'s withdraw-0
////      is present. That credential is a parameter on purpose: it is both the
////      issuer's authority and the per-token entropy that makes every policy
////      id distinct;
////   2. the PROTOCOL's issuance logic ran, and covered this policy — the
////      script named by `issuance_logic_cred` in the protocol-params datum
////      has a withdraw-0 redeemer in this transaction, and this policy id is
////      one of its KEYS.
////
//// Everything that may change with the protocol — registry proofs, custody,
//// PLB output shape, which delegate redeemers prove what — lives in
//// `issuance_logic`, behind that datum field. Upgrading the rules every token
//// obeys is one `protocol_params` update; no policy id moves.
////
//// The frozen interface, stated once: `issuance_logic`'s redeemer decodes as
//// `Pairs<PolicyId, Data>`. The keys are read here; the values never are.
////
//// Migrated from SmartTokens.Contracts.Issuance; split by #129.

use aiken/collection/pairs as std_pairs
use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/transaction.{ScriptPurpose, Transaction, Withdraw}
use pairs
use programmable_logic/params
use types.{IssuanceRedeemer}

validator issuance_mint(
  // <- the hash of the contract of the logic for minting.
  minting_logic_cred: Credential,
  // One-shot protocol-params NFT policy — the protocol's permanent anchor,
  // the same parameter PLB and the delegates take. Locates the protocol-params
  // UTxO at `redeemer.params_idx` and reads `issuance_logic_cred` (field 5).
  params_policy: PolicyId,
) {
  mint(redeemer: IssuanceRedeemer, own_policy: PolicyId, self: Transaction) {
    trace @"Starting issuance_mint validation"

    // 1. The substandard's minting logic must be invoked (proof of instance).
    expect pairs.has_key_or_fail(self.withdrawals, minting_logic_cred)

    // 2. The protocol's issuance logic must be invoked AND must have covered
    //    this policy. Its credential is the LIVE one from the params datum,
    //    so a replaced issuance-logic script retires the old one for every
    //    token at once.
    params.with_protocol_params_fields(
      self.reference_inputs,
      params_policy,
      redeemer.params_idx,
      fn(fields) {
        covered_by(
          self.redeemers,
          params.issuance_logic_cred_field(fields),
          own_policy,
        )?
      },
    )
  }

  else(_) {
    fail
  }
}

/// Find `issuance_logic`'s withdraw redeemer in `tx.redeemers` and check that
/// `own_policy` is one of its keys. A redeemer entry for `Withdraw(cred)`
/// exists iff that withdrawal is in the transaction and the script ran, so
/// this is also the invocation check.
///
/// Decodes the redeemer as `Pairs<PolicyId, Data>` and no further: the keys
/// are the contract, the values are `issuance_logic`'s business. Not invoked,
/// or invoked without naming this policy ⇒ False ⇒ the mint fails.
fn covered_by(
  redeemers: Pairs<ScriptPurpose, Data>,
  issuance_logic_cred: Credential,
  own_policy: PolicyId,
) -> Bool {
  when redeemers is {
    [] -> False
    [Pair(purpose, data), ..tail] ->
      when purpose is {
        Withdraw(c) ->
          if c == issuance_logic_cred {
            expect covered: Pairs<PolicyId, Data> = data
            std_pairs.has_key(covered, own_policy)
          } else {
            covered_by(tail, issuance_logic_cred, own_policy)
          }
        _ -> covered_by(tail, issuance_logic_cred, own_policy)
      }
  }
}
