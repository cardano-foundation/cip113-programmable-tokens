//// Programmable Logic Base Validator
//// This validator locks all programmable token UTxOs. It forwards validation
//// to the `programmable_logic_global` dispatcher, named by the protocol-params
//// datum.
//// Migrated from SmartTokens.Contracts.ProgrammableLogicBase
////
//// Upgradability in place: PLB is parameterized by the protocol-params NFT
//// policy — the protocol's only permanent anchor — instead of a compile-time
//// credential. On every spend it reads the CURRENT dispatcher credential from
//// the protocol-params reference input's datum (extracted with builtins — no
//// whole-datum deserialisation) and requires that credential's withdraw-0.
//// Swapping the entire dispatch layer is therefore a datum rewrite on the
//// protocol-params UTxO; PLB's hash — and with it every programmable token
//// address — never changes.
////
//// **This validator is deliberately the smallest thing in the protocol**, and
//// it is the one script that can never be replaced, because its hash anchors
//// every token address. It runs once per programmable INPUT, so every
//// instruction here is multiplied by the number of tokens a transaction moves.
//// It therefore does exactly three things: locate the params datum, read ONE
//// credential out of it — `plg_cred`, FIELD 0, so the read costs a single
//// `head_list` and no `tail_list` walk at all — and require that credential's
//// withdraw-0 at the witnessed index. Which ACTION is being performed —
//// transfer, third-party, unfracking — is none of its business;
//// `programmable_logic_global` decides that, and the delegate enforces it.
////
//// The trust chain, in one line:
////
////   PLB --reads--> params[plg_cred] --requires--> PLG --requires--> delegate
////
//// The witness is self-validating: a wrong `wdrl_idx` resolves to some other
//// credential, the equality fails, and a dishonest witness only invalidates its
//// own transaction. `list.expect_at` drops `wdrl_idx` cells to reach the
//// witnessed entry: O(`wdrl_idx`), not O(1), but with no credential comparison
//// on the way, where a scan would compare at every entry up to the dispatcher's
//// position (cost record: `programmable_logic/wdrl_idx_cost.test.ak`).
////
//// Lineage: PLB used to dispatch to one of three delegate credentials itself,
//// choosing between them on a three-constructor redeemer. That was only sound
//// while the three credentials were pairwise distinct — an assumption nothing
//// on-chain enforced. With a single credential on this path there is nothing
//// left to collide, so the assumption is gone rather than documented.

use aiken/collection/list
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use programmable_logic/params
use types.{BaseSpendRedeemer}

validator programmable_logic_base(params_policy: PolicyId) {
  spend(
    _datum: Option<Data>,
    redeemer: BaseSpendRedeemer,
    _own_ref: Data,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_base validation"

    let BaseSpendRedeemer { params_idx, wdrl_idx } = redeemer

    // Locate the protocol-params NFT among the reference inputs (addressed by
    // the redeemer's `params_idx`) and pull the live dispatcher credential out
    // of its datum. The params UTxO is already a mandatory reference input on
    // every programmable-token transaction, so this adds no availability
    // requirement.
    let fields <- params.with_protocol_params_fields(
      self.reference_inputs,
      params_policy,
      params_idx,
    )

    let Pair(witnessed, _) = list.expect_at(self.withdrawals, wdrl_idx)

    (witnessed == params.plg_cred_field(fields))?
  }

  else(_) {
    fail
  }
}
