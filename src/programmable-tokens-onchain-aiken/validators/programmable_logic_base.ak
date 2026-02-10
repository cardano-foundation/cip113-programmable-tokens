//// Programmable Logic Base Validator
//// This validator locks all programmable token UTxOs
//// It forwards validation to the global programmable logic stake validator
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase

use cardano/address.{Credential}
use cardano/transaction.{Transaction}
use utils.{expect_key}

validator programmable_logic_base(stake_cred: Credential) {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _own_ref: Data,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_base validation"

    // The programmable logic base validator simply checks that the global
    // programmable logic stake script is invoked in the transaction via the
    // withdraw-zero pattern Check that the stake credential is invoked
    self.withdrawals |> expect_key(stake_cred)
  }

  else(_) {
    fail
  }
}
