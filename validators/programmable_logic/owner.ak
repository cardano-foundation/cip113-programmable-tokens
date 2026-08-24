//// Holder-authorisation kernel — the ONE definition of "the PLB UTxO's
//// owner consented to this spend".
////
//// A PLB UTxO's owner is its inline stake credential. Consent is:
////   * `VerificationKey` owner — the key signed the transaction
////     (`extra_signatories`);
////   * `Script` owner — the script's withdraw-0 is invoked
////     (`withdrawals`), the standard smart-wallet pattern.
////
//// Shared by the two actions that spend PLB UTxOs on the owner's own
//// authority: the transfer input scan (every PLB input) and the
//// unfracking owner pinning (first PLB input; subsequent inputs must
//// then equal the pinned address). ThirdPartyAct deliberately does NOT
//// use it — admin actions are authorised by the policy's third-party
//// logic, not the holder.
////
//// Cost note: each validator embeds its own copy and each has a single
//// call site, so the compiler inlines it — source-level dedup, no
//// execution overhead (verified against the transfer benchmarks).

use cardano/address.{Address, Credential, Inline, Script, VerificationKey}

/// Extract the owner (inline stake credential) of a PLB address and
/// fail unless they consented. The two checkers are caller-provided so
/// each call site keeps its own lookup strategy (loud `*_or_fail`
/// helpers, or a prebuilt closure chain). Returns the credential for
/// callers that pin it.
pub fn authorised_stake_cred(
  address: Address,
  has_signatory: fn(ByteArray) -> Bool,
  has_withdrawal: fn(Credential) -> Bool,
) -> Credential {
  expect Some(Inline(stake_cred)) = address.stake_credential
  expect
    when stake_cred is {
      VerificationKey(pkh) -> has_signatory(pkh)
      Script(_hash) -> has_withdrawal(stake_cred)
    }
  stake_cred
}
