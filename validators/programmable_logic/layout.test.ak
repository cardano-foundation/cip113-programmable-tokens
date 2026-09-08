//// Golden raw-`Data` layout tests.
////
//// Off-chain builders, positional parsers and the formal-verification
//// artefacts depend on the exact on-the-wire encoding of the protocol-params
//// datum and of every redeemer this repo defines: constructor indices and
//// field order. These tests pin them as raw `Data`, independently of the Aiken
//// type declarations, in BOTH directions — encode a typed value and inspect
//// the constructor/fields; build the constructor by hand and decode it — so a
//// reordered field or a shifted constructor index shows up here before it
//// shows up as an SDK incident.
////
//// **These tests are the WHOLE defence of the off-chain wire contract — do not
//// trim them.** Verified by mutation (2026-09-02): a SELF-CONSISTENT reorder of
//// `ProgrammableLogicGlobalParams` — the type declaration and its accessors
//// moved together — is invisible to 483 of the suite's 485 tests, because every
//// on-chain reader goes through the accessors and so agrees with itself. Only
//// `layout_params_datum_five_fields_in_order` and
//// `layout_params_datum_decodes_from_raw_constructor` assert against raw
//// positions, and they are what stands between a silent reorder and every
//// off-chain builder in the ecosystem.

use aiken/builtin
use aiken/collection/list
use cardano/address.{Credential}
use multisig
use programmable_logic/fixture
use programmable_logic/params.{
  ProgrammableLogicGlobalParams, plg_cred_field, third_party_cred_field,
  transfer_cred_field,
}
use types.{
  BaseSpendRedeemer, MintingRegistryProof, NominateAuthority, OutputIndex,
  ProgrammableLogicGlobalRedeemer, PromoteAuthority, ProtocolParamsRedeemer,
  ProtocolUpgrade, RefInput, ThirdPartyAct, ThirdPartyRedeemer,
  TokenDoesNotExist, TokenExists, TransferAct, TransferRedeemer, UnfrackingAct,
  UnfrackingRedeemer,
}

fn constr(d: Data) -> (Int, List<Data>) {
  let Pair(tag, fields) = builtin.un_constr_data(d)
  (tag, fields)
}

fn field(fields: List<Data>, i: Int) -> Data {
  list.expect_at(fields, i)
}

fn int_fields(ints: List<Int>) -> List<Data> {
  list.map(ints, builtin.i_data)
}

// ------------------------------------------------------ protocol-params datum

// `ProgrammableLogicGlobalParams`: constructor 0, FOUR fields, in this order:
//   0 plg_cred, 1 transfer_cred, 2 third_party_cred, 3 upgrade_cred.
//
// Field order is load-bearing on two counts. Every accessor is a `tail_list`
// walk, so position IS cost — `plg_cred` sits at 0 because PLB reads it once
// per programmable INPUT, the only per-input read in the protocol, and at
// index 0 that read walks nothing. And the params NFT policy (hence PLB's
// hash, hence every token address) is a function of `protocol_params`,
// which deserialises this exact shape.
//
// Every field here has a named on-chain reader: `plg_cred` <-
// programmable_logic_base, `transfer_cred` / `third_party_cred` <-
// issuance_mint, `upgrade_cred` <- protocol_params (spend handler).
//
// This shape REPLACED a six-field one — `{ registry_node_cs(0),
// prog_logic_cred(1), plg_cred(2), transfer_cred(3), third_party_cred(4),
// upgrade_cred(5) }`. `registry_node_cs` and `prog_logic_cred` were removed
// because nothing reads them any more: both are compile-time parameters of the
// delegates now.
//
// **SILENT-MISREAD HAZARD for off-chain builders** — the same family as the
// `BaseSpendRedeemer` warning below, and sharper. Only the FIRST field's
// removal is loud:
//
//   old 0 registry_node_cs (ByteArray) -> plg_cred (Credential) .. LOUD (type)
//   old 1 prog_logic_cred              -> transfer_cred ........... SILENT
//   old 2 plg_cred                     -> third_party_cred ........ SILENT  <-- worst
//   old 3 transfer_cred                -> upgrade_cred ............ SILENT
//   old 4, 5                           -> absent .................. LOUD
//
// The third row is the dangerous one: a builder computing PLB's dispatch
// target from index 2 silently reads `third_party_cred`. On-chain this is
// safe — every reader in this repo moved in the same change set — so the whole
// hazard is off-chain, and it is why `layout_params_retired_six_field_shape_
// does_not_decode` below pins the decode direction too.
//
// Issue #125 added `pending_upgrade_cred`, and it is the CONTRASTING case
// worth keeping beside that table: appending a field produces NO silent
// misread in either direction. A stale four-field reader looking at a
// five-field datum still finds every field it knows at the index it expects
// and simply never looks at 4; a five-field reader handed a four-field datum
// aborts on arity, loudly. That asymmetry is the entire argument for the
// append-only rule stated on the type, and it is why this change needed one
// new golden rather than a re-audit of every position.
/// The at-rest nomination, bound with a type so it can be encoded as `Data`
/// (Aiken takes no inline annotation in expression position).
const no_pending: Option<Credential> = None

test layout_params_datum_five_fields_in_order() {
  let (tag, fields) = constr(as_data(fixture.protocol_params))
  and {
    tag == 0,
    list.length(fields) == 5,
    field(fields, 0) == as_data(fixture.credential_validator_plg),
    field(fields, 1) == as_data(fixture.credential_validator_transfer),
    field(fields, 2) == as_data(fixture.credential_validator_third_party),
    field(fields, 3) == as_data(fixture.credential_upgrade_authority),
    // Field 4 at rest. `pending_upgrade_cred` was APPENDED, which is why
    // positions 0-3 above are byte-identical to the four-field shape and no
    // accessor moved.
    field(fields, 4) == as_data(no_pending),
  }
}

// The `Option` wire shape itself, pinned in both states, because this is the
// first optional field in the datum and an off-chain builder has to emit it.
// `None` is constructor 1 with no fields; `Some(c)` is constructor 0 wrapping
// the credential. Getting these backwards produces a datum that still decodes
// as SOMETHING, so nothing else in the suite would catch it.
test layout_params_pending_option_wire_shape() {
  let at_rest = as_data(no_pending)
  let in_flight = as_data(Some(fixture.credential_upgrade_authority))
  let (rest_tag, rest_fields) = constr(at_rest)
  let (flight_tag, flight_fields) = constr(in_flight)
  and {
    rest_tag == 1,
    list.length(rest_fields) == 0,
    flight_tag == 0,
    list.length(flight_fields) == 1,
    field(flight_fields, 0) == as_data(fixture.credential_upgrade_authority),
  }
}

// The builtin accessors production reads through (PLB for `plg_cred`,
// `issuance_mint` for the two delegate credentials) land on the positions the
// type declares. `upgrade_cred` has no accessor: `protocol_params`
// deserialises the whole record on its cold path.
test layout_params_accessors_match_raw_positions() {
  let (_, fields) = constr(as_data(fixture.protocol_params))
  and {
    plg_cred_field(fields) == fixture.credential_validator_plg,
    transfer_cred_field(fields) == fixture.credential_validator_transfer,
    third_party_cred_field(fields) == fixture.credential_validator_third_party,
  }
}

// Decode direction: a hand-built constructor 0 with the five fields in that
// order is accepted as the params type with every field where expected
// (what the `protocol_params` mint handler does).
test layout_params_datum_decodes_from_raw_constructor() {
  let raw = builtin.constr_data(
    0,
    [
      as_data(fixture.credential_validator_plg),
      as_data(fixture.credential_validator_transfer),
      as_data(fixture.credential_validator_third_party),
      as_data(fixture.credential_upgrade_authority),
      as_data(no_pending),
    ],
  )
  expect p: ProgrammableLogicGlobalParams = raw
  p == fixture.protocol_params
}

// Issue #125: the FOUR-field shape — the one every params UTxO deployed before
// this change carries — must not decode as the new type. Same rail as the
// six-field test below, one generation on.
//
// This is what makes `pending_upgrade_cred` a REDEPLOY, not an in-place
// upgrade: an existing four-field UTxO cannot be spent into the five-field
// shape, because the spend handler deserialises the old datum as the new type
// and aborts. That costs nothing in practice — the validator's bytes changed,
// so its hash and address moved anyway, and the standing rule is that every
// validator-byte change is a full-protocol redeploy — but it must be stated
// rather than discovered.
test layout_params_retired_four_field_shape_does_not_decode() fail {
  let raw = builtin.constr_data(
    0,
    [
      as_data(fixture.credential_validator_plg),
      as_data(fixture.credential_validator_transfer),
      as_data(fixture.credential_validator_third_party),
      as_data(fixture.credential_upgrade_authority),
    ],
  )
  expect _p: ProgrammableLogicGlobalParams = raw
  True
}

// The other decode direction: a hand-built SIX-field constructor — the retired
// shape, exactly as an already-deployed protocol-params UTxO carries it — must
// NOT decode as the new type. The `protocol_params` mint handler runs this same
// whole-record `expect` at mint time, so this is the rail that stops a stale
// off-chain builder from ever minting the old shape.
//
// OBSERVED (aiken v1.1.23+8949565, 2026-09-02) — the rejection is
// OVER-DETERMINED: Aiken's `expect` rejects BOTH the trailing-field surplus
// AND field 0's type, independently. Two throwaway probes settled it:
//
//   * six slots with a `Credential` at index 0 (all four real fields correct,
//     two junk fields appended)  -> ABORTS. So arity alone is fatal.
//   * exactly four slots with a `ByteArray` at index 0                -> ABORTS.
//     So field 0's type alone is fatal.
//
// Which one fires FIRST for the retired shape is visible in the execution
// units: this test aborts at ~0.6 K mem / 1.4 M cpu, matching the
// ByteArray-at-zero probe (~0.55 K / 1.2 M) and nowhere near the arity probe
// (~21 K / 6.0 M, which had to decode four credentials before the field count
// was checked). So the retired six-field datum trips the FIELD-0 TYPE check
// first, and the arity check is a second, independent net behind it.
//
// The practical reading for an off-chain consumer: emitting the retired shape
// fails LOUDLY at the `protocol_params` mint handler, twice over — but that loudness is a
// property of MINTING the datum, not of READING it. The per-field accessors
// PLB and `issuance_mint` use never see either net (that is the whole point of
// the split read), which is exactly why the silent-misread table above is the
// hazard that matters.
test layout_params_retired_six_field_shape_does_not_decode() fail {
  let raw = builtin.constr_data(
    0,
    [
      as_data(fixture.policy_tokens_registry),
      as_data(fixture.credential_validator_logic_base),
      as_data(fixture.credential_validator_plg),
      as_data(fixture.credential_validator_transfer),
      as_data(fixture.credential_validator_third_party),
      as_data(fixture.credential_upgrade_authority),
    ],
  )
  expect _p: ProgrammableLogicGlobalParams = raw
  True
}

// ------------------------------------------------------ PLB spend redeemer

// `BaseSpendRedeemer` is now a RECORD — constructor 0, [params_idx, wdrl_idx].
// It replaced a three-constructor enum (SpendViaTransfer / SpendViaThirdParty /
// SpendViaUnfracking), each carrying the same two ints. PLB no longer chooses a
// delegate at all: it requires `plg_cred`, and the dispatcher picks the arm.
//
// For off-chain builders this is the sharpest break in the change: the OLD
// encoding and the NEW one are both "constructor 0 with two ints", so a stale
// builder emitting `SpendViaTransfer { params_idx, wdrl_idx }` produces bytes
// that still DECODE here — they just mean something different. The failure
// shows up as a withdrawal-index mismatch, not as a decode error.
test layout_base_spend_redeemer_is_a_record_of_two_ints() {
  let (tag, fields) = constr(
    as_data(BaseSpendRedeemer { params_idx: 7, wdrl_idx: 3 }),
  )
  and {
    tag == 0,
    fields == int_fields([7, 3]),
  }
}

test layout_base_spend_redeemer_decodes_from_raw_constructor() {
  expect r: BaseSpendRedeemer = builtin.constr_data(0, int_fields([7, 3]))
  r == BaseSpendRedeemer { params_idx: 7, wdrl_idx: 3 }
}

// ------------------------------------------------------ dispatcher redeemer

// `ProgrammableLogicGlobalRedeemer`: three FIELD-LESS constructors —
// TransferAct = 0, ThirdPartyAct = 1, UnfrackingAct = 2. The payload for each
// action travels in that delegate's own redeemer, never here.
test layout_plg_redeemer_constructors_are_field_less() {
  let (t_tag, t_fields) = constr(as_data(TransferAct))
  let (p_tag, p_fields) = constr(as_data(ThirdPartyAct))
  let (u_tag, u_fields) = constr(as_data(UnfrackingAct))
  and {
    t_tag == 0,
    t_fields == [],
    p_tag == 1,
    p_fields == [],
    u_tag == 2,
    u_fields == [],
  }
}

test layout_plg_redeemer_decodes_from_raw_constructors() {
  expect t: ProgrammableLogicGlobalRedeemer = builtin.constr_data(0, [])
  expect p: ProgrammableLogicGlobalRedeemer = builtin.constr_data(1, [])
  expect u: ProgrammableLogicGlobalRedeemer = builtin.constr_data(2, [])
  and {
    t == TransferAct,
    p == ThirdPartyAct,
    u == UnfrackingAct,
  }
}

// ------------------------------------------------------ third_party redeemer

// `ThirdPartyRedeemer`: constructor 0, [params_idx, registry_node_idx,
// outputs_start_idx].
test layout_third_party_redeemer_fields() {
  let (tag, fields) = constr(
    as_data(ThirdPartyRedeemer { registry_node_idx: 0, outputs_start_idx: 2 }),
  )
  and {
    tag == 0,
    fields == int_fields([0, 2]),
  }
}

test layout_third_party_redeemer_decodes_from_raw_constructor() {
  expect r: ThirdPartyRedeemer = builtin.constr_data(0, int_fields([0, 2]))
  r == ThirdPartyRedeemer { registry_node_idx: 0, outputs_start_idx: 2 }
}

// ------------------------------------------------------ transfer redeemer

// `TransferRedeemer`: a single constructor 0 [params_idx, proofs] — the
// former `ProgrammableLogicGlobalRedeemer` lost its ThirdPartyAct and
// UnfrackingAct arms when those paths got their own validators.
// `RegistryProof`: TokenExists = 0, TokenDoesNotExist = 1, each [node_idx].
test layout_transfer_redeemer_constructor_and_fields() {
  let proofs = [TokenExists { node_idx: 2 }, TokenDoesNotExist { node_idx: 3 }]
  let (t_tag, t_fields) = constr(as_data(TransferRedeemer { proofs }))
  let (e_tag, e_fields) = constr(as_data(TokenExists { node_idx: 2 }))
  let (n_tag, n_fields) = constr(as_data(TokenDoesNotExist { node_idx: 3 }))
  and {
    t_tag == 0,
    list.length(t_fields) == 1,
    field(t_fields, 0) == as_data(proofs),
    e_tag == 0,
    e_fields == int_fields([2]),
    n_tag == 1,
    n_fields == int_fields([3]),
  }
}

test layout_transfer_redeemer_decodes_from_raw_constructor() {
  let raw_proofs = builtin.list_data(
    [
      builtin.constr_data(0, int_fields([2])),
      builtin.constr_data(1, int_fields([3])),
    ],
  )
  expect t: TransferRedeemer = builtin.constr_data(0, [raw_proofs])
  t == TransferRedeemer {
    proofs: [TokenExists { node_idx: 2 }, TokenDoesNotExist { node_idx: 3 }],
  }
}

// ------------------------------------------------------ unfracking redeemer

// `UnfrackingRedeemer`: constructor 0, [params_idx, registry_node_idx,
// outputs_start_idx] — same shape as ThirdPartyRedeemer.
test layout_unfracking_redeemer_fields() {
  let (tag, fields) = constr(
    as_data(UnfrackingRedeemer { registry_node_idx: 0, outputs_start_idx: 2 }),
  )
  and {
    tag == 0,
    fields == int_fields([0, 2]),
  }
}

// ------------------------------------------------------ issuance redeemer

// `MintingRegistryProof`: RefInput = constructor 0, OutputIndex = constructor
// 1, each [index].
test layout_minting_registry_proof_constructors() {
  let (r_tag, r_fields) = constr(as_data(RefInput(4)))
  let (o_tag, o_fields) = constr(as_data(OutputIndex(4)))
  expect decoded: MintingRegistryProof = builtin.constr_data(1, int_fields([4]))
  and {
    r_tag == 0,
    r_fields == int_fields([4]),
    o_tag == 1,
    o_fields == int_fields([4]),
    decoded == OutputIndex(4),
  }
}

// ------------------------------------------------- protocol-params redeemer

// `ProtocolParamsRedeemer`: three FIELD-LESS constructors — ProtocolUpgrade =
// 0, NominateAuthority = 1, PromoteAuthority = 2. Every value each arm needs
// is already in the continuing datum, so nothing travels here (issue #125).
//
// The spend handler's redeemer was previously ignored `Data`, so an off-chain
// builder could pass anything — `Void`, a unit constructor, whatever the SDK
// happened to emit. It is now a required, meaningful choice, and getting the
// index wrong selects a DIFFERENT rule set rather than failing to decode:
// index 0 refuses to move the authority, index 1 refuses everything but the
// nomination. That is why these indices are pinned here.
test layout_protocol_params_redeemer_constructors_are_field_less() {
  let (u_tag, u_fields) = constr(as_data(ProtocolUpgrade))
  let (n_tag, n_fields) = constr(as_data(NominateAuthority))
  let (p_tag, p_fields) = constr(as_data(PromoteAuthority))
  and {
    u_tag == 0,
    u_fields == [],
    n_tag == 1,
    n_fields == [],
    p_tag == 2,
    p_fields == [],
  }
}

test layout_protocol_params_redeemer_decodes_from_raw_constructors() {
  expect u: ProtocolParamsRedeemer = builtin.constr_data(0, [])
  expect n: ProtocolParamsRedeemer = builtin.constr_data(1, [])
  expect p: ProtocolParamsRedeemer = builtin.constr_data(2, [])
  and {
    u == ProtocolUpgrade,
    n == NominateAuthority,
    p == PromoteAuthority,
  }
}

// ------------------------------------------------- upgrade-authority datum

// `MultisigScript` (lib/multisig.ak, Sundae's native-script ADT) is the datum
// of the upgrade authority's config UTxO — written by the deployer at genesis
// and by the authority itself on every rotation. Constructor indices follow
// declaration order: Signature 0, AllOf 1, AnyOf 2, AtLeast 3, Before 4,
// After 5, Script 6. An off-chain builder emitting the wrong index does not
// get a decode failure; it gets a DIFFERENT authority (an `AnyOf` written as
// `AllOf`, say), so these are pinned here.
const authority_key: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

test layout_multisig_script_constructor_indices() {
  let sig = multisig.Signature { key_hash: authority_key }
  let cases = [
    (as_data(sig), 0, 1),
    (as_data(multisig.AllOf { scripts: [sig] }), 1, 1),
    (as_data(multisig.AnyOf { scripts: [sig] }), 2, 1),
    (as_data(multisig.AtLeast { required: 1, scripts: [sig] }), 3, 2),
    (as_data(multisig.Before { time: 7 }), 4, 1),
    (as_data(multisig.After { time: 7 }), 5, 1),
    (as_data(multisig.Script { script_hash: authority_key }), 6, 1),
  ]
  list.all(
    cases,
    fn(case) {
      let (raw, expected_tag, expected_arity) = case
      let (tag, fields) = constr(raw)
      and {
        tag == expected_tag,
        list.length(fields) == expected_arity,
      }
    },
  )
}

// Decode direction, for the constructor with two fields: `required` comes
// before `scripts`.
test layout_multisig_at_least_decodes_from_raw_constructor() {
  let sig = multisig.Signature { key_hash: authority_key }
  expect t: multisig.MultisigScript = builtin.constr_data(
    3,
    [as_data(2), as_data([sig])],
  )
  t == multisig.AtLeast { required: 2, scripts: [sig] }
}
