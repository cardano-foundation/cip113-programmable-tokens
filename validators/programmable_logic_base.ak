//// Programmable Logic Base Validator
//// This validator locks all programmable token UTxOs. It forwards
//// validation to ONE of three withdraw-0 stake validators — `transfer`,
//// `third_party`, `unfracking` — chosen by its redeemer.
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase
////
//// Upgradability in place: PLB is parameterized by the protocol-params
//// NFT policy — the protocol's only permanent anchor — instead of a
//// compile-time credential. On every spend it reads the CURRENT
//// delegate credential from the protocol-params reference input's datum
//// (extracted with builtins — no whole-datum deserialisation) and requires
//// that credential's withdraw-0. Swapping any delegate is therefore a
//// datum rewrite on the coordination UTxO; PLB's hash — and with it every
//// programmable token address — never changes.
////
//// Dispatch: the redeemer picks which delegate authorises this spend — the
//// `transfer` validator (ordinary transfers), the `third_party` validator
//// (seize / clawback / freeze enforcement) or the `unfracking` validator
//// (holder-driven same-owner restructuring) — and witnesses the exact index
//// of that delegate's entry in the ledger-ordered withdrawal map. No
//// delegate is reached through another: each transaction kind loads exactly
//// one of the three reference scripts. Because PLB runs once per
//// programmable input, resolving the withdrawal by index (no per-entry
//// credential comparison) instead of scanning the map saves cost on every
//// input. The witness is self-validating: a wrong index or arm resolves to
//// a credential that fails the equality, so a dishonest witness only
//// invalidates its own transaction.

use aiken/collection/list
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use programmable_logic/params
use types.{
  BaseSpendRedeemer, SpendViaThirdParty, SpendViaTransfer, SpendViaUnfracking,
  base_params_idx,
}

validator programmable_logic_base(params_policy: PolicyId) {
  spend(
    _datum: Option<Data>,
    redeemer: BaseSpendRedeemer,
    _own_ref: Data,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_base validation"

    // Locate the protocol-params NFT among the reference inputs (addressed by
    // the redeemer's `params_idx`) and pull the live delegate credentials out
    // of its datum. The params UTxO is already a mandatory reference input on
    // every programmable-token transaction, so this adds no availability
    // requirement.
    let fields <- params.with_protocol_params_fields(
      self.reference_inputs,
      params_policy,
      base_params_idx(redeemer),
    )

    // Select the delegate credential this spend claims to forward to, and the
    // withdrawal index that must carry it.
    let (claimed, wdrl_idx) = when redeemer is {
      SpendViaTransfer { wdrl_idx, .. } ->
        (params.transfer_cred_field(fields), wdrl_idx)
      SpendViaThirdParty { wdrl_idx, .. } ->
        (params.third_party_cred_field(fields), wdrl_idx)
      SpendViaUnfracking { wdrl_idx, .. } ->
        (params.unfracking_cred_field(fields), wdrl_idx)
    }

    // Go directly to the witnessed withdrawal entry and require it to carry
    // the claimed delegate credential — the withdraw-zero trampoline.
    // `list.expect_at` drops `wdrl_idx` cells to get there: O(wdrl_idx), not
    // O(1), but with no credential comparison on the way, where the former
    // `has_key_or_fail` scan compared at every entry up to the delegate's
    // position (cost record: programmable_logic/wdrl_idx_cost.test.ak).
    // The arm is meaningful only while the three delegate credentials in the
    // params datum are pairwise distinct; that distinctness is NOT enforced
    // on-chain (see `BaseSpendRedeemer`).
    let Pair(witnessed_cred, _) = list.expect_at(self.withdrawals, wdrl_idx)
    (witnessed_cred == claimed)?
  }

  else(_) {
    fail
  }
}
