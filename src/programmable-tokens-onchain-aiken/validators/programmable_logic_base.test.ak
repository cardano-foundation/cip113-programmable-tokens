//// Tests for the programmable_logic_base validator.
//// Invokes the validator's spend handler directly to verify it checks
//// that the parameterized stake credential is present in tx.withdrawals.

use cardano/address.{Credential, Script, VerificationKey}
use cardano/transaction.{Transaction}
use programmable_logic_base

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_stake_cred: Credential =
  Script(#"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd")

const test_other_cred: Credential =
  Script(#"11223344112233441122334411223344112233441122334411223344")

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn call_validator(tx: Transaction) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    test_stake_cred,
    None,
    Void,
    Void,
    tx,
  )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Passes when the parameterized stake credential is in withdrawals
test plb_passes_when_stake_cred_in_withdrawals() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      withdrawals: [Pair(test_stake_cred, 0)],
    }
  call_validator(tx)
}

// Fails when the stake credential is absent from withdrawals
test plb_fails_when_stake_cred_not_in_withdrawals() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      withdrawals: [Pair(test_other_cred, 0)],
    }
  call_validator(tx)
}

// Fails with empty withdrawals list
test plb_fails_with_empty_withdrawals() fail {
  let tx = Transaction { ..transaction.placeholder, withdrawals: [] }
  call_validator(tx)
}

// Passes when stake credential is among multiple withdrawal entries
test plb_passes_with_multiple_withdrawals() {
  let tx =
    Transaction {
      ..transaction.placeholder,
      withdrawals: [
        Pair(test_other_cred, 0),
        Pair(test_stake_cred, 0),
        Pair(
          Script(#"99999999999999999999999999999999999999999999999999999999"),
          0,
        ),
      ],
    }
  call_validator(tx)
}

// Fails when credential type differs (VerificationKey vs Script)
test plb_fails_with_wrong_credential_type() fail {
  let vkey_cred: Credential =
    VerificationKey(#"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd")
  let tx =
    Transaction {
      ..transaction.placeholder,
      withdrawals: [Pair(vkey_cred, 0)],
    }
  call_validator(tx)
}
