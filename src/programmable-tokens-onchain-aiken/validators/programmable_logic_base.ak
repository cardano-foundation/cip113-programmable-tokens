// =============================================================================
// Programmable Logic Base Spend Validator
// =============================================================================
//
// This validator locks all programmable token UTxOs in the CIP-0113 protocol.
// It implements the forwarding pattern, delegating actual validation to the
// global programmable logic stake validator.
//
// ## Architecture
//
// All programmable tokens are locked at addresses using this script as the
// payment credential. The stake credential varies per user/account, enabling:
// - Per-user authorization (the stake credential owner can spend)
// - Global transfer logic enforcement (this validator checks for global script)
//
// ## Address Format
//
// Programmable addresses have the form:
// ```
// payment_credential = Script(programmable_logic_base_hash)
// stake_credential   = Inline(user_key_or_script)
// ```
//
// ## Validation Logic
//
// This validator simply checks that the global programmable logic stake script
// is invoked in the transaction via the withdraw-zero pattern. The actual
// transfer logic and registry checks happen in that global validator.
//
// ## Why This Design?
//
// 1. **Gas efficiency**: Complex logic is in the stake script (paid once)
// 2. **Composability**: Multiple UTxOs can be validated together
// 3. **Extensibility**: Transfer logic can be upgraded in the registry
//
// ## Migration Notes
//
// Migrated from SmartTokens.Contracts.ProgrammableLogicBase
//
// =============================================================================

use aiken/collection/list
use cardano/address.{Credential}
use cardano/transaction.{Transaction}

/// The programmable logic base spend validator.
///
/// This validator locks all programmable token UTxOs. It forwards all
/// validation to the global programmable logic stake validator by checking
/// that the stake credential is invoked in the transaction.
///
/// ## Parameters
///
/// - `stake_cred`: The credential of the global programmable logic stake
///   validator. This script contains all the transfer logic and registry
///   validation.
///
/// ## Spending Conditions
///
/// A UTxO can only be spent if the global stake validator is invoked via
/// a zero-value withdrawal (withdraw-zero pattern).
///
/// ## Example Transaction
///
/// ```
/// inputs:
///   - UTxO at programmable_logic_base address with tokens
/// outputs:
///   - UTxO at programmable_logic_base address with tokens (transfer)
/// withdrawals:
///   - 0 ADA from global_programmable_logic_stake (invoke validator)
/// ```
validator programmable_logic_base(stake_cred: Credential) {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _own_ref: Data,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_base validation"

    // The programmable logic base validator simply checks that the
    // global programmable logic stake script is invoked in the transaction
    // via the withdraw-zero pattern.
    //
    // All actual validation (registry lookup, transfer logic, authorization)
    // happens in the global stake validator.
    //
    // Optimization: We use list.any which short-circuits on first match.
    list.any(
      self.withdrawals,
      fn(wdrl) {
        let Pair(cred, _amount) = wdrl
        cred == stake_cred
      },
    )
  }

  /// Fallback handler for non-spend purposes (e.g., minting, certifying).
  /// Always fails as this validator only supports spend.
  else(_) {
    fail
  }
}
