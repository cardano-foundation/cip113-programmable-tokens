//// Negative coverage for the holder-authorisation kernel (Finding 001).
////
//// `owner.authorised_stake_cred` is the single definition of "the PLB UTxO's
//// owner consented." The end-to-end transfer/unfracking fixtures stake PLB
//// inputs to the same credential they register as `transfer_logic_script`, so
//// the mandatory transfer-logic withdrawal doubles as the owner's consent —
//// which means removing the consent check would NOT fail any of those tests.
//// These unit tests exercise the kernel directly, pinning that it aborts when
//// consent is absent: a vkey owner that did not sign, a script owner whose
//// withdraw-0 is missing, and a non-inline (or absent) stake credential.

use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use programmable_logic/owner.{authorised_stake_cred}

const owner_pkh: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const owner_script: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

/// Payment credential is irrelevant to consent — the owner is the stake cred.
const pay: Credential =
  Script(#"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3")

fn addr(stake: Option<address.Referenced<Credential>>) -> Address {
  Address { payment_credential: pay, stake_credential: stake }
}

fn vkey_addr() -> Address {
  addr(Some(Inline(VerificationKey(owner_pkh))))
}

fn script_addr() -> Address {
  addr(Some(Inline(Script(owner_script))))
}

// A vkey owner who signed consents; the kernel returns their credential.
test owner_consent_accepts_signed_vkey() {
  authorised_stake_cred(vkey_addr(), fn(k) { k == owner_pkh }, fn(_) { False }) == VerificationKey(
    owner_pkh,
  )
}

// A vkey owner who did NOT sign is rejected (the kernel aborts).
test owner_consent_rejects_unsigned_vkey() fail {
  authorised_stake_cred(vkey_addr(), fn(_) { False }, fn(_) { False }) == VerificationKey(
    owner_pkh,
  )
}

// A script owner whose withdraw-0 is present consents; the kernel returns it.
test owner_consent_accepts_script_with_withdrawal() {
  authorised_stake_cred(
    script_addr(),
    fn(_) { False },
    fn(c) { c == Script(owner_script) },
  ) == Script(owner_script)
}

// A script owner whose withdraw-0 is absent is rejected (the kernel aborts).
test owner_consent_rejects_script_without_withdrawal() fail {
  authorised_stake_cred(script_addr(), fn(_) { False }, fn(_) { False }) == Script(
    owner_script,
  )
}

// A PLB UTxO with no inline stake credential has no owner to authorise — the
// kernel aborts on `expect Some(Inline(stake_cred))`.
test owner_consent_rejects_non_inline_stake() fail {
  authorised_stake_cred(addr(None), fn(_) { True }, fn(_) { True }) == pay
}
