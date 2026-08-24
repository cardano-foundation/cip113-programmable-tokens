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
    // redeemer is kinda unwrapped twice, one here for the param index and one below for the withdrawal index (check costs of destructuring once earlier)
    // One `when` over the redeemer, and the params lookup inside each arm.
    //
    // The obvious shape — read `params_idx` up here, then `when` again below to
    // pick the credential — destructures the redeemer TWICE, and this validator
    // runs once per programmable input, so the second decode is multiplied by
    // every input in the transaction. Measured at ~1.0M cpu and ~1.2k mem per
    // spend (see the record in `programmable_logic/benchmarks.ak`).
    //
    // Hence the repetition below, which is deliberate: the three arms differ
    // only in which datum field they read, but hoisting that difference out
    // costs more than it saves. Two shapes were measured and rejected — a
    // shared lookup selected by an integer tag (+53k cpu, the tag comparison
    // outweighing the decode it removed), and carrying the field accessor as a
    // function in a tuple (rejected by the compiler: tuple inhabitants must be
    // serialisable to Data). The cost of this shape is +14 bytes of script.
    let witnessed = fn(wdrl_idx: Int) {
      let Pair(cred, _) = list.expect_at(self.withdrawals, wdrl_idx)
      cred
    }

    // Whichever arm runs, the check is the same: the withdrawal the redeemer
    // points at must carry the delegate credential that arm names, read live
    // from the protocol-params datum. A wrong index or a wrong arm resolves to
    // some other credential and the equality fails, so a dishonest witness can
    // only invalidate its own transaction. The arm is meaningful only while the
    // three delegate credentials are pairwise distinct; that distinctness is
    // NOT enforced on-chain (see `BaseSpendRedeemer`).
    when redeemer is {
      SpendViaTransfer { params_idx, wdrl_idx } -> {
        let fields <- params.with_protocol_params_fields(
          self.reference_inputs,
          params_policy,
          params_idx,
        )
        (witnessed(wdrl_idx) == params.transfer_cred_field(fields))?
      }
      SpendViaThirdParty { params_idx, wdrl_idx } -> {
        let fields <- params.with_protocol_params_fields(
          self.reference_inputs,
          params_policy,
          params_idx,
        )
        (witnessed(wdrl_idx) == params.third_party_cred_field(fields))?
      }
      SpendViaUnfracking { params_idx, wdrl_idx } -> {
        let fields <- params.with_protocol_params_fields(
          self.reference_inputs,
          params_policy,
          params_idx,
        )
        (witnessed(wdrl_idx) == params.unfracking_cred_field(fields))?
      }
    }
  }

  else(_) {
    fail
  }
}
