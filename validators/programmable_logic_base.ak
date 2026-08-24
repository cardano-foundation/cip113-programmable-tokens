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
    // The redeemer is destructured ONCE, and everything the three arms share
    // is hoisted into one function. This validator runs per programmable input,
    // so anything left inside an arm is paid per input and anything duplicated
    // across arms is paid in reference-script bytes on every transaction.
    //
    // Measured ladder (PLB script size / cpu on `plb_passes_when_datum_transfer_cred_in_withdrawals`,
    // full record in `programmable_logic/benchmarks.ak`):
    //
    //   before, redeemer decoded twice ........... 868 B / 91,319,764
    //   decode once, lookup repeated per arm ..... 882 B / 90,321,632
    //   + partial application of the lookup ...... 850 B / 90,241,632
    //   + share the comparison as well ........... 849 B / 90,289,632
    //   + pass the field accessor in (this) ...... 829 B / 90,097,632
    //
    // Two shapes do not work at all: selecting the credential by an integer tag
    // costs more than the decode it removes (+52,856 cpu), and returning the
    // accessor in a TUPLE is rejected by the compiler — tuple inhabitants must
    // be serialisable to Data. Passing it as an ARGUMENT, as below, is fine.
    // Everything the three arms share, hoisted into one function: locate the
    // params datum, resolve the witnessed withdrawal, compare. The arms then
    // differ only in which datum field they read, which is passed in.
    // (A function may be passed as an ARGUMENT even though it may not live in
    // a tuple — tuple inhabitants must be serialisable to Data, arguments need
    // not be.)
    let check = fn(params_idx: Int, wdrl_idx: Int, cred_of) {
      let fields <- params.with_protocol_params_fields(
        self.reference_inputs,
        params_policy,
        params_idx,
      )
      let Pair(witnessed, _) = list.expect_at(self.withdrawals, wdrl_idx)
      (witnessed == cred_of(fields))?
    }

    when redeemer is {
      SpendViaTransfer { params_idx, wdrl_idx } ->
        check(params_idx, wdrl_idx, params.transfer_cred_field)
      SpendViaThirdParty { params_idx, wdrl_idx } ->
        check(params_idx, wdrl_idx, params.third_party_cred_field)
      SpendViaUnfracking { params_idx, wdrl_idx } ->
        check(params_idx, wdrl_idx, params.unfracking_cred_field)
    }
  }

  else(_) {
    fail
  }
}
