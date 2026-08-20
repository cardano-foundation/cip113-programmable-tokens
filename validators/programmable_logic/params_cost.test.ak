//// Cost record: protocol-params extraction strategies (Finding 17;
//// extended for in-place upgradability).
////
//// These tests document WHY `with_protocol_params_fields` hands back
//// raw datum fields with per-field accessors instead of deserialising
//// the whole `ProgrammableLogicGlobalParams` record:
////
////   (a) legacy — manual builtins over the old 2-field datum (what
////       production ran before Finding 17 added `unfracking_cred`);
////   (b) full deserialisation — `expect _: <params type>`, which
////       validates EVERY field on every run;
////   (c) split (current production) — extract only the fields the
////       redeemer branch needs via the `*_field` accessors.
////
//// Datum generations: 2-field (pre-Finding-17), 3-field (Finding 17
//// added `unfracking_cred`), then upgradability appended
//// `prog_logic_global_cred` (field 3, read by PLB on every spend),
//// `upgrade_logic_cred` (field 4, read only by `coordination_spend` on an
//// upgrade transaction), and the PLG split appended `third_party_cred`
//// (field 5, read by PLB only on a SpendViaThirdParty dispatch) — for a
//// 6-field production datum. Fields 4-5 are off the transfer hot path, so
//// they get no per-field cost row of their own below. The 2- and 3-field
//// shapes are kept as local types so their measurements stay reproducible
//// after the production type moved on.
////
//// Representative run (aiken v1.1.22; ABSOLUTE mem/cpu per test — compare
//// rows, they share one reference-input layout. Since the #103 index change
//// the split path locates the params UTxO by index while the baseline scans,
//// so subtracting the baseline no longer isolates pure extraction cost; read
//// the rows against each other instead):
////
////   locate + unwrap baseline (6-field) ...... 459.8k mem / 147.2M cpu
////   (b) 6-field full expect ................. 530.0k mem / 169.3M cpu
////   (c) 6-field split, fields 0-1 (PLG) ..... 486.3k mem / 153.1M cpu
////   (c) 6-field split, field 2 (unfracking) . 483.2k mem / 152.4M cpu
////   (c) 6-field split, field 3 (PLB) ........ 483.4k mem / 152.5M cpu
////   (c) 6-field split, all four fields ...... 509.9k mem / 162.4M cpu
////
//// (Legacy 2-/3-field full-expect rows, kept for reproducibility: 488.5k/
//// 154.9M and 503.0k/160.4M — validating more fields costs strictly more.)
////
//// i.e. the PLG hot path (fields 0-1) pays ~+5.9M cpu / +26.6k mem over the
//// bare locate+unwrap, versus ~+22.0M cpu / +70.2k mem to `expect` the whole
//// 6-field record — the split saves the hot path from validating four fields
//// it never reads. Skipping whole-record validation is safe because
//// protocol_params_mint fully deserialises the datum at mint time (see
//// `with_protocol_params_fields` docs).
////
//// Every test shares the same reference-input layout (params NFT input
//// first, one registry node behind it — same order as the tx fixtures)
//// so the search cost is identical; differences between tests isolate
//// the extraction strategy. The baselines measure the shared search +
//// InlineDatum unwrap alone — subtract them from any variant to get
//// the pure extraction cost.

use aiken/builtin.{head_list, tail_list, unconstr_fields}
use assets
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{InlineDatum, Input, Output}
use programmable_logic/fixture
use programmable_logic/params.{
  ProgrammableLogicGlobalParams, prog_logic_cred_field,
  prog_logic_global_cred_field, registry_node_cs_field, unfracking_cred_field,
  with_protocol_params_fields,
}

// --------------------------------------------------------------------- types

/// The protocol-params datum shape BEFORE Finding 17 appended
/// `unfracking_cred`.
type LegacyTwoFieldParams {
  registry_node_cs: PolicyId,
  prog_logic_cred: Credential,
}

/// The protocol-params datum shape AFTER Finding 17 but BEFORE the
/// upgradability refactor appended `prog_logic_global_cred`.
type LegacyThreeFieldParams {
  registry_node_cs: PolicyId,
  prog_logic_cred: Credential,
  unfracking_cred: Credential,
}

// ----------------------------------------------------------------- fixtures

const legacy_params: LegacyTwoFieldParams =
  LegacyTwoFieldParams {
    registry_node_cs: fixture.policy_tokens_registry,
    prog_logic_cred: fixture.credential_validator_logic_base,
  }

const legacy3_params: LegacyThreeFieldParams =
  LegacyThreeFieldParams {
    registry_node_cs: fixture.policy_tokens_registry,
    prog_logic_cred: fixture.credential_validator_logic_base,
    unfracking_cred: fixture.credential_validator_unfracking,
  }

/// Reference inputs as they appear in the tx fixtures, with an
/// arbitrary datum in place of the current 5-field one.
fn ref_inputs_with_datum(datum: Data) -> List<Input> {
  let modern = fixture.some_reference_input_protocol_params(
    fixture.protocol_params,
    "protocol params",
  )
  [
    Input {
      ..modern,
      output: Output { ..modern.output, datum: InlineDatum(datum) },
    },
    fixture.some_reference_input_tokens_registry_node(
      "",
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      "node",
    ),
  ]
}

/// Reference inputs with the legacy 2-field params datum.
fn v2_ref_inputs() -> List<Input> {
  ref_inputs_with_datum(as_data(legacy_params))
}

/// Reference inputs with the legacy 3-field params datum.
fn v3_ref_inputs() -> List<Input> {
  ref_inputs_with_datum(as_data(legacy3_params))
}

/// Same layout with the current (5-field) params datum.
fn v5_ref_inputs() -> List<Input> {
  [
    fixture.some_reference_input_protocol_params(
      fixture.protocol_params,
      "protocol params",
    ),
    fixture.some_reference_input_tokens_registry_node(
      "",
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      "node",
    ),
  ]
}

/// Local copy of params.ak's private `get_protocol_params_ref` so the
/// search cost is identical across all variants measured here.
fn locate_params_ref(ref_inputs: List<Input>, policy: PolicyId) -> Input {
  let head = builtin.head_list(ref_inputs)
  if assets.peek_first(head.output) == policy {
    head
  } else {
    locate_params_ref(builtin.tail_list(ref_inputs), policy)
  }
}

/// (a) The pre-Finding-17 production extraction, verbatim: builtins
/// over the 2-field datum, both fields unconditionally.
fn legacy_with_programmable_logic_params(
  reference_inputs: List<Input>,
  protocol_params_cs: PolicyId,
  return: fn(PolicyId, Credential) -> result,
) -> result {
  let protocol_params_ref = locate_params_ref(
    reference_inputs,
    protocol_params_cs,
  )

  expect InlineDatum(inline_datum) = protocol_params_ref.output.datum
  let fields = unconstr_fields(inline_datum)
  expect registry_node_cs: PolicyId = head_list(fields)
  let fields = tail_list(fields)
  expect prog_logic_cred: Credential = head_list(fields)

  return(registry_node_cs, prog_logic_cred)
}

// --------------------------------------------------------------- baselines

/// Shared cost floor over the legacy inputs: locate the params ref
/// input and unwrap the InlineDatum, extracting nothing.
test cost_baseline_locate_and_unwrap_v2() {
  let input = locate_params_ref(v2_ref_inputs(), fixture.policy_protocol_params)
  expect InlineDatum(datum) = input.output.datum
  datum == as_data(legacy_params)
}

/// Same cost floor over the legacy 3-field inputs.
test cost_baseline_locate_and_unwrap_v3() {
  let input = locate_params_ref(v3_ref_inputs(), fixture.policy_protocol_params)
  expect InlineDatum(datum) = input.output.datum
  datum == as_data(legacy3_params)
}

/// Same cost floor over the current 5-field inputs (their construction
/// cost differs slightly, so each family gets its own baseline).
test cost_baseline_locate_and_unwrap_v5() {
  let input = locate_params_ref(v5_ref_inputs(), fixture.policy_protocol_params)
  expect InlineDatum(datum) = input.output.datum
  datum == as_data(fixture.protocol_params)
}

// ---------------------------------------------- v2 datum (legacy, 2 fields)

/// (a) Pre-Finding-17 production path.
test cost_v2_builtins_legacy() {
  let registry_node_cs, prog_logic_cred <- legacy_with_programmable_logic_params(
    v2_ref_inputs(),
    fixture.policy_protocol_params,
  )
  and {
    registry_node_cs == fixture.policy_tokens_registry,
    prog_logic_cred == fixture.credential_validator_logic_base,
  }
}

/// (b) Full `expect` deserialisation of the 2-field datum.
test cost_v2_full_expect() {
  let input = locate_params_ref(v2_ref_inputs(), fixture.policy_protocol_params)
  expect InlineDatum(datum) = input.output.datum
  expect p: LegacyTwoFieldParams = datum
  and {
    p.registry_node_cs == fixture.policy_tokens_registry,
    p.prog_logic_cred == fixture.credential_validator_logic_base,
  }
}

// ---------------------------------------------- v3 datum (legacy, 3 fields)

/// (b) Full `expect` deserialisation of the 3-field datum.
test cost_v3_full_expect() {
  let input = locate_params_ref(v3_ref_inputs(), fixture.policy_protocol_params)
  expect InlineDatum(datum) = input.output.datum
  expect p: LegacyThreeFieldParams = datum
  and {
    p.registry_node_cs == fixture.policy_tokens_registry,
    p.prog_logic_cred == fixture.credential_validator_logic_base,
    p.unfracking_cred == fixture.credential_validator_unfracking,
  }
}

// ----------------------------------------- v5 datum (current, 5 fields)

/// (b) Full `expect` deserialisation of the 5-field datum — what the
/// simplest implementation would pay on EVERY redeemer branch.
test cost_v5_full_expect() {
  let input = locate_params_ref(v5_ref_inputs(), fixture.policy_protocol_params)
  expect InlineDatum(datum) = input.output.datum
  expect p: ProgrammableLogicGlobalParams = datum
  and {
    p.registry_node_cs == fixture.policy_tokens_registry,
    p.prog_logic_cred == fixture.credential_validator_logic_base,
    p.unfracking_cred == fixture.credential_validator_unfracking,
    p.prog_logic_global_cred == fixture.credential_validator_logic_global,
  }
}

/// (c) Production, transfer/3rd-party branch: fields 0-1 only —
/// identical work to the legacy 2-field extraction, i.e. the appended
/// fields cost the PLG hot path nothing.
test cost_v5_split_first_two() {
  let fields <- with_protocol_params_fields(
    v5_ref_inputs(),
    fixture.policy_protocol_params,
    0,
  )
  and {
    registry_node_cs_field(fields) == fixture.policy_tokens_registry,
    prog_logic_cred_field(fields) == fixture.credential_validator_logic_base,
  }
}

/// (c) Production, unfracking branch: field 2 only.
test cost_v5_split_third_only() {
  let fields <- with_protocol_params_fields(
    v5_ref_inputs(),
    fixture.policy_protocol_params,
    0,
  )
  unfracking_cred_field(fields) == fixture.credential_validator_unfracking
}

/// (c) Production, PLB spend (upgradability trampoline): field 3 only —
/// the extraction cost added to every programmable-token spend.
test cost_v5_split_fourth_only() {
  let fields <- with_protocol_params_fields(
    v5_ref_inputs(),
    fixture.policy_protocol_params,
    0,
  )
  prog_logic_global_cred_field(fields) == fixture.credential_validator_logic_global
}

/// (c) Split upper bound: all four fields via the accessors.
test cost_v5_split_all_four() {
  let fields <- with_protocol_params_fields(
    v5_ref_inputs(),
    fixture.policy_protocol_params,
    0,
  )
  and {
    registry_node_cs_field(fields) == fixture.policy_tokens_registry,
    prog_logic_cred_field(fields) == fixture.credential_validator_logic_base,
    unfracking_cred_field(fields) == fixture.credential_validator_unfracking,
    prog_logic_global_cred_field(fields) == fixture.credential_validator_logic_global,
  }
}
