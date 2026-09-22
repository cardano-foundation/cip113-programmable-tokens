//// Cost record: protocol-params extraction strategies (Finding 17;
//// extended for in-place upgradability).
////
//// These tests document WHY `with_protocol_params_fields` hands back
//// raw datum fields with per-field accessors instead of deserialising
//// the whole `ProtocolParams` record:
////
////   (a) legacy — manual builtins over the old 2-field datum (what
////       production ran before Finding 17 added `unfracking_cred`);
////   (b) full deserialisation — `expect _: <params type>`, which
////       validates EVERY field on every run;
////   (c) split (current production) — extract only the fields the
////       redeemer branch needs via the `*_field` accessors.
////
//// Datum generations are named here by their FIELD SET, never by arity: two
//// of them hold six fields, so "six-field" on its own does not identify a
//// layout.
////
////   * registry set (2 fields) — `registry_node_cs` (0),
////     `programmable_logic_base_cred` (1).
////   * registry + unfracking set (3 fields) — the same pair, then
////     `unfracking_cred` (2).
////   * registry-first delegate set (6 fields) — `registry_node_cs` (0),
////     `programmable_logic_base_cred` (1),
////     `programmable_logic_global_cred` (2), `transfer_cred` (3),
////     `third_party_cred` (4), `upgrade_cred` (5).
////   * four-credential set (4 fields) — `programmable_logic_global_cred` (0),
////     `transfer_cred` (1), `third_party_cred` (2), `upgrade_cred` (3). The
////     representative run recorded below was measured on THIS set.
////   * PRODUCTION set (6 fields), ordered by read frequency —
////     `programmable_logic_global_cred` (0, read by `programmable_logic_base`
////     once per programmable INPUT), `issuance_logic_cred` (1, read by
////     `issuance_mint` once per EXECUTION, i.e. once per programmable policy
////     minted or burned), `transfer_cred` (2) and `third_party_cred` (3)
////     (read by `issuance_logic`, which locates a delegate's redeemer on a
////     delegating mint), `upgrade_cred` (4) and `pending_upgrade_cred` (5)
////     (read only by `protocol_params`, which deserialises the whole record).
////
//// `registry_node_cs` and `programmable_logic_base_cred` have no on-chain
//// reader in the production set — both are compile-time parameters of the
//// delegates — which is what puts `programmable_logic_global_cred` at depth
//// ZERO. The 2- and 3-field shapes live on as local types in this module so
//// their measurements stay reproducible against the production type.
////
//// Representative run (aiken v1.1.23+8949565, 2026-09-02) on the
//// FOUR-CREDENTIAL set; ABSOLUTE mem/cpu per test — compare rows, they share
//// one reference-input layout. The split path locates the params UTxO by
//// index while the baseline scans, so subtracting the baseline does not
//// isolate pure extraction cost; read the rows against each other instead.
//// Rows name accessors rather than depths, because the depths below are the
//// ones that set gave each field — plg_cred 0, transfer_cred 1,
//// third_party_cred 2:
////
////   locate + unwrap baseline ................... 459.8k mem / 146.7M cpu
////   (b) full expect ............................ 515.7k mem / 166.3M cpu
////   (c) split, plg_cred + transfer_cred ........ 494.8k mem / 156.7M cpu
////   (c) split, transfer_cred only .............. 482.9k mem / 152.3M cpu
////   (c) split, plg_cred only (PLB HOT PATH) .... 482.7k mem / 152.2M cpu
////   (c) split, three accessors ................. 506.1k mem / 161.2M cpu
////
//// (Full-expect rows for the 2- and 3-field sets, kept for reproducibility:
//// 488.5k/154.9M and 503.0k/160.4M — validating more fields costs strictly
//// more.)
////
//// **What the four-credential set bought PLB, against the registry-first
//// set.** `programmable_logic_global_cred` sits at depth 0 in the
//// four-credential set and in the production set alike — two `tail_list`
//// steps shallower than the registry-first set placed it.
//// `cost_six_field_params_split_programmable_logic_global_only` — the entire
//// datum-read cost PLB pays, once per programmable input — measured
//// **483,167 -> 482,703 mem (-464) and 152,393,931 -> 152,166,605 cpu
//// (-227,326, -0.149%)** across that pair.
////
//// That delta is depth ALONE, not the smaller fixture. Control: a throwaway
//// probe reading ONE credential at depth 2 (`third_party_cred_field`) off the
//// four-credential fixture measured 483,167 / 152,393,931 — reproducing the
//// registry-first depth-2 figure bit for bit. A read that never walks past its
//// own field is indifferent to how many fields follow it, so the fixture
//// shrink contributes nothing here and the whole delta is the two `tail_list`
//// steps. Cross-check: `cost_six_field_params_split_transfer_only` sat two
//// steps shallower too (depth 3 -> depth 1) and fell by exactly the same
//// -464 / -227,326. One
//// `tail_list` step over this datum therefore costs ~232 mem / ~113,663 cpu.
////
//// **The confound, stated rather than left implicit.** The fixture DID get
//// cheaper, and by more than the headline saving:
//// `cost_baseline_locate_and_unwrap_six_field_params` reads no field at all and therefore
//// measures the shrink alone — it moved 147,230,593 -> 146,685,013 cpu
//// (-545,580; mem unchanged at 459,783), i.e. 2.4x the -227,326 claimed for
//// the depth change. That is exactly why the depth-2 control above is the
//// evidence and a raw before/after is not: the two effects are separable only
//// because a depth-0 read is indifferent to what follows it. Anyone
//// re-auditing this record should reproduce the control, not the difference.
//// Likewise `cost_six_field_params_split_all_four` fell 509,873 -> 506,079 mem (-3,794) and
//// 162,363,784 -> 161,240,024 cpu (-1,123,760). That one is PARTLY depth: its
//// three accessors each sat two slots shallower (depths {2,3,4} in the
//// registry-first set -> {0,1,2} in the four-credential set), and six steps at
//// the rate above is ~681,978 cpu / ~1,392 mem, so
//// at least 60% of the cpu movement is depth before the dropped fourth
//// accessor call contributes anything. Both movements are
//// innocent; both are disclosed here so the argument can be checked rather
//// than trusted.
////
//// The rows that ROSE did so for an honest reason, not a regression:
//// `cost_six_field_params_split_first_two` (+8.5k mem / +3.6M cpu against the
//// registry-first run) reads two `Credential`s where the registry-first set
//// put a `ByteArray` and a `Credential` — decoding a constr costs more than
//// decoding bytes. It is a
//// bookkeeping row, not a production path: no caller reads exactly that pair.
//// `cost_six_field_params_full_expect` FELL (530.0k/169.3M -> 515.7k/166.3M)
//// because the four-credential set gives it two fewer fields to validate.
////
//// i.e. the hot path pays ~+5.5M cpu / ~+22.9k mem over the bare
//// locate+unwrap to extract its one credential, versus ~+19.6M cpu / ~+55.9k
//// mem to `expect` the whole record — the split saves the hot path from
//// validating every field it never reads. Skipping whole-record validation is
//// safe because the protocol_params mint handler fully deserialises the datum at mint time
//// (see `with_protocol_params_fields` docs).
////
//// Every test shares the same reference-input layout (params NFT input
//// first, one registry node behind it — same order as the tx fixtures)
//// so the search cost is identical; differences between tests isolate
//// the extraction strategy. The baselines measure the shared search +
//// InlineDatum unwrap alone — subtract them from any variant to get
//// the pure extraction cost.

use aiken/builtin.{head_list, tail_list, unconstr_fields}
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{InlineDatum, Input, Output}
use prog_assets
use programmable_logic/fixture
use programmable_logic/params.{
  ProtocolParams, programmable_logic_global_cred_field, third_party_cred_field,
  transfer_cred_field, with_protocol_params_fields,
}

// --------------------------------------------------------------------- types

/// The protocol-params datum shape BEFORE Finding 17 appended
/// `unfracking_cred`.
type TwoFieldParams {
  registry_node_cs: PolicyId,
  programmable_logic_base_cred: Credential,
}

/// The protocol-params datum shape AFTER Finding 17 but BEFORE the
/// upgradability refactor appended `transfer_cred`.
type ThreeFieldParams {
  registry_node_cs: PolicyId,
  programmable_logic_base_cred: Credential,
  unfracking_cred: Credential,
}

// ----------------------------------------------------------------- fixtures

const two_field_params: TwoFieldParams =
  TwoFieldParams {
    registry_node_cs: fixture.policy_tokens_registry,
    programmable_logic_base_cred: fixture.credential_validator_logic_base,
  }

const three_field_params: ThreeFieldParams =
  ThreeFieldParams {
    registry_node_cs: fixture.policy_tokens_registry,
    programmable_logic_base_cred: fixture.credential_validator_logic_base,
    unfracking_cred: fixture.credential_validator_unfracking,
  }

/// Reference inputs as they appear in the tx fixtures, with an
/// arbitrary datum in place of the production one.
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
fn two_field_params_ref_inputs() -> List<Input> {
  ref_inputs_with_datum(as_data(two_field_params))
}

/// Reference inputs with the legacy 3-field params datum.
fn three_field_params_ref_inputs() -> List<Input> {
  ref_inputs_with_datum(as_data(three_field_params))
}

/// Same layout with the production params datum.
fn six_field_params_ref_inputs() -> List<Input> {
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
  if prog_assets.expect_first_policy(head.output) == policy {
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
  expect programmable_logic_base_cred: Credential = head_list(fields)

  return(registry_node_cs, programmable_logic_base_cred)
}

// --------------------------------------------------------------- baselines

/// Shared cost floor over the legacy inputs: locate the params ref
/// input and unwrap the InlineDatum, extracting nothing.
test cost_baseline_locate_and_unwrap_two_field_params() {
  let input = locate_params_ref(
    two_field_params_ref_inputs(),
    fixture.policy_protocol_params,
  )
  expect InlineDatum(datum) = input.output.datum
  datum == as_data(two_field_params)
}

/// Same cost floor over the legacy 3-field inputs.
test cost_baseline_locate_and_unwrap_three_field_params() {
  let input = locate_params_ref(
    three_field_params_ref_inputs(),
    fixture.policy_protocol_params,
  )
  expect InlineDatum(datum) = input.output.datum
  datum == as_data(three_field_params)
}

/// Same cost floor over the production inputs (their construction
/// cost differs slightly, so each family gets its own baseline).
test cost_baseline_locate_and_unwrap_six_field_params() {
  let input = locate_params_ref(
    six_field_params_ref_inputs(),
    fixture.policy_protocol_params,
  )
  expect InlineDatum(datum) = input.output.datum
  datum == as_data(fixture.protocol_params)
}

// ---------------------------------------------- v2 datum (legacy, 2 fields)

/// (a) Pre-Finding-17 production path.
test cost_two_field_params_builtins_legacy() {
  let registry_node_cs, programmable_logic_base_cred <- legacy_with_programmable_logic_params(
    two_field_params_ref_inputs(),
    fixture.policy_protocol_params,
  )
  and {
    registry_node_cs == fixture.policy_tokens_registry,
    programmable_logic_base_cred == fixture.credential_validator_logic_base,
  }
}

/// (b) Full `expect` deserialisation of the 2-field datum.
test cost_two_field_params_full_expect() {
  let input = locate_params_ref(
    two_field_params_ref_inputs(),
    fixture.policy_protocol_params,
  )
  expect InlineDatum(datum) = input.output.datum
  expect p: TwoFieldParams = datum
  and {
    p.registry_node_cs == fixture.policy_tokens_registry,
    p.programmable_logic_base_cred == fixture.credential_validator_logic_base,
  }
}

// ---------------------------------------------- v3 datum (legacy, 3 fields)

/// (b) Full `expect` deserialisation of the 3-field datum.
test cost_three_field_params_full_expect() {
  let input = locate_params_ref(
    three_field_params_ref_inputs(),
    fixture.policy_protocol_params,
  )
  expect InlineDatum(datum) = input.output.datum
  expect p: ThreeFieldParams = datum
  and {
    p.registry_node_cs == fixture.policy_tokens_registry,
    p.programmable_logic_base_cred == fixture.credential_validator_logic_base,
    p.unfracking_cred == fixture.credential_validator_unfracking,
  }
}

// -------------------------------------- production datum (6 fields)

/// (b) Full `expect` deserialisation of the current datum — what the
/// simplest implementation would pay on EVERY redeemer branch.
test cost_six_field_params_full_expect() {
  let input = locate_params_ref(
    six_field_params_ref_inputs(),
    fixture.policy_protocol_params,
  )
  expect InlineDatum(datum) = input.output.datum
  expect p: ProtocolParams = datum
  and {
    p.programmable_logic_global_cred == fixture.credential_validator_programmable_logic_global,
    p.transfer_cred == fixture.credential_validator_transfer,
    p.third_party_cred == fixture.credential_validator_third_party,
    p.upgrade_cred == fixture.credential_upgrade_authority,
  }
}

/// (c) `programmable_logic_global_cred` (field 0) and `transfer_cred` (field
/// 2). No production caller reads exactly this pair; the row exists to keep
/// the "shallow split" measurement comparable across datum generations.
test cost_six_field_params_split_first_two() {
  let fields <- with_protocol_params_fields(
    six_field_params_ref_inputs(),
    fixture.policy_protocol_params,
    0,
  )
  and {
    programmable_logic_global_cred_field(fields) == fixture.credential_validator_programmable_logic_global,
    transfer_cred_field(fields) == fixture.credential_validator_transfer,
  }
}

/// (c) `transfer_cred` (field 2) only — one of the two delegate credentials
/// `issuance_logic` pays for on a delegating mint. NOT on the spend path.
test cost_six_field_params_split_transfer_only() {
  let fields <- with_protocol_params_fields(
    six_field_params_ref_inputs(),
    fixture.policy_protocol_params,
    0,
  )
  transfer_cred_field(fields) == fixture.credential_validator_transfer
}

/// (c) PRODUCTION HOT PATH: `programmable_logic_global_cred` (field 0) only — the whole datum-read
/// cost PLB pays, once per programmable input. This is the number that gets
/// multiplied by every token a transaction moves, so it is the one to watch.
/// At field 0 the accessor is a bare `head_list`: no `tail_list` step at all.
test cost_six_field_params_split_programmable_logic_global_only() {
  let fields <- with_protocol_params_fields(
    six_field_params_ref_inputs(),
    fixture.policy_protocol_params,
    0,
  )
  programmable_logic_global_cred_field(fields) == fixture.credential_validator_programmable_logic_global
}

/// (c) Split upper bound for the dispatch + delegation path: the three
/// accessors it touches — `programmable_logic_global_cred` (0),
/// `transfer_cred` (2) and `third_party_cred` (3). The module also exposes
/// `issuance_logic_cred_field` (1), which this row does not call;
/// `upgrade_cred` (4) and `pending_upgrade_cred` (5) have no accessor at all,
/// their only reader deserialising the whole record on a cold path. The name
/// is historical, kept so the row stays comparable against earlier cost
/// records.
test cost_six_field_params_split_all_four() {
  let fields <- with_protocol_params_fields(
    six_field_params_ref_inputs(),
    fixture.policy_protocol_params,
    0,
  )
  and {
    programmable_logic_global_cred_field(fields) == fixture.credential_validator_programmable_logic_global,
    transfer_cred_field(fields) == fixture.credential_validator_transfer,
    third_party_cred_field(fields) == fixture.credential_validator_third_party,
  }
}
