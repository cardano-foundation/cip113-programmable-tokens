//// Tests for the programmable_logic_global dispatcher.
////
//// PLG has one job: given an ACTION, prove that the delegate responsible for
//// that action was invoked in this transaction. It reads no datum and holds no
//// invariants of its own — the three delegate hashes are compile-time
//// PARAMETERS, which is what turns programmable_logic_base's "some dispatcher
//// ran" into "the RIGHT delegate ran".
////
////   programmable_logic_base --reads--> params[plg_cred] --requires--> PLG
////     --requires--> transfer | third_party | unfracking
////
//// What must therefore be pinned here is that each arm is gated by ITS OWN
//// baked hash: an arm must reject when its delegate is missing, and must not
//// be waved through by some other delegate's withdrawal.
////
//// Note on `fail` vs `!call_…`: the withdrawal lookup is
//// `pairs.has_key_or_fail`, which ABORTS when the key is absent, so every
//// withdraw-side rejection is a `test … fail`. `publish` returns a Bool, so its
//// rejection is `!plg_publish(…)`.

use aiken/collection/list
use cardano/address.{Credential, Script, VerificationKey}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/transaction.{Transaction}
use programmable_logic/fixture
use programmable_logic_global
use types.{
  ProgrammableLogicGlobalRedeemer, ThirdPartyAct, TransferAct, UnfrackingAct,
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// PLG parameterised with the three fixture delegate hashes, invoked at the
/// dispatcher's own credential (the value the params datum carries as
/// `plg_cred`, and the account programmable_logic_base witnesses).
fn call_plg(redeemer: ProgrammableLogicGlobalRedeemer, tx: Transaction) -> Bool {
  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.hash_validator_transfer,
    fixture.hash_validator_third_party,
    fixture.hash_validator_unfracking,
    redeemer,
    fixture.credential_validator_plg,
    tx,
  )
}

fn plg_publish(certificate: Certificate) -> Bool {
  programmable_logic_global.programmable_logic_global.publish(
    fixture.hash_validator_transfer,
    fixture.hash_validator_third_party,
    fixture.hash_validator_unfracking,
    Void,
    certificate,
    transaction.placeholder,
  )
}

/// A transaction carrying exactly the given withdrawal set — the only field
/// PLG looks at.
fn plg_tx(withdrawals: Pairs<Credential, Int>) -> Transaction {
  Transaction { ..transaction.placeholder, withdrawals }
}

/// The realistic withdrawal set of each action, minus one credential — used to
/// remove a delegate from an otherwise complete transaction (one delta).
fn without(
  withdrawals: Pairs<Credential, Int>,
  credential: Credential,
) -> Pairs<Credential, Int> {
  list.filter(withdrawals, fn(w) { w.1st != credential })
}

// ---------------------------------------------------------------------------
// Each arm is satisfied by its own delegate
// ---------------------------------------------------------------------------

test plg_transfer_act_passes_when_transfer_delegate_invoked() {
  call_plg(TransferAct, plg_tx(fixture.withdrawals_transfer))
}

test plg_third_party_act_passes_when_third_party_delegate_invoked() {
  call_plg(ThirdPartyAct, plg_tx(fixture.withdrawals_3rd_party))
}

test plg_unfracking_act_passes_when_unfracking_delegate_invoked() {
  call_plg(UnfrackingAct, plg_tx(fixture.withdrawals_unfracking))
}

// ---------------------------------------------------------------------------
// Each arm rejects when its own delegate is absent
// ---------------------------------------------------------------------------

test plg_transfer_act_fails_when_transfer_delegate_absent() fail {
  let tx = plg_tx(
    without(fixture.withdrawals_transfer, fixture.credential_validator_transfer),
  )
  call_plg(TransferAct, tx)
}

test plg_third_party_act_fails_when_third_party_delegate_absent() fail {
  let tx = plg_tx(
    without(
      fixture.withdrawals_3rd_party,
      fixture.credential_validator_third_party,
    ),
  )
  call_plg(ThirdPartyAct, tx)
}

test plg_unfracking_act_fails_when_unfracking_delegate_absent() fail {
  let tx = plg_tx(
    without(
      fixture.withdrawals_unfracking,
      fixture.credential_validator_unfracking,
    ),
  )
  call_plg(UnfrackingAct, tx)
}

test plg_fails_with_empty_withdrawals() fail {
  call_plg(TransferAct, plg_tx([]))
}

// ---------------------------------------------------------------------------
// No arm is satisfied by a DIFFERENT delegate
//
// This is what proves the baked hash actually gates the arm, rather than the
// dispatcher waving through whichever delegate happens to be present. All six
// ordered pairs are covered; each is its own test because the lookup aborts and
// so cannot be composed with `!`.
// ---------------------------------------------------------------------------

test plg_transfer_act_fails_when_only_third_party_delegate_present() fail {
  call_plg(
    TransferAct,
    plg_tx([Pair(fixture.credential_validator_third_party, 0)]),
  )
}

test plg_transfer_act_fails_when_only_unfracking_delegate_present() fail {
  call_plg(
    TransferAct,
    plg_tx([Pair(fixture.credential_validator_unfracking, 0)]),
  )
}

test plg_third_party_act_fails_when_only_transfer_delegate_present() fail {
  call_plg(
    ThirdPartyAct,
    plg_tx([Pair(fixture.credential_validator_transfer, 0)]),
  )
}

test plg_third_party_act_fails_when_only_unfracking_delegate_present() fail {
  call_plg(
    ThirdPartyAct,
    plg_tx([Pair(fixture.credential_validator_unfracking, 0)]),
  )
}

test plg_unfracking_act_fails_when_only_transfer_delegate_present() fail {
  call_plg(
    UnfrackingAct,
    plg_tx([Pair(fixture.credential_validator_transfer, 0)]),
  )
}

test plg_unfracking_act_fails_when_only_third_party_delegate_present() fail {
  call_plg(
    UnfrackingAct,
    plg_tx([Pair(fixture.credential_validator_third_party, 0)]),
  )
}

// ---------------------------------------------------------------------------
// The lookup is against `Script(hash)`, not the bare 28 bytes
// ---------------------------------------------------------------------------

// A verification key carrying the transfer delegate's hash is a different
// credential, and a withdrawal at it does not satisfy the arm — the delegate's
// script must actually run.
test plg_transfer_act_fails_on_vkey_credential_with_the_delegate_hash() fail {
  let impostor: Credential = VerificationKey(fixture.hash_validator_transfer)
  call_plg(TransferAct, plg_tx([Pair(impostor, 0)]))
}

// ---------------------------------------------------------------------------
// publish
// ---------------------------------------------------------------------------

// The dispatcher's credential must be registrable as a stake credential —
// without this, its withdraw-0 could never be invoked at all.
test plg_publish_accepts_register_credential() {
  plg_publish(
    RegisterCredential {
      credential: Script(fixture.hash_validator_plg),
      deposit: Never,
    },
  )
}

// Every other certificate kind is refused: the credential exists to be
// withdrawn from, never to delegate, retire or vote.
test plg_publish_rejects_other_certificates() {
  !plg_publish(
    UnregisterCredential {
      credential: Script(fixture.hash_validator_plg),
      refund: Never,
    },
  )
}
