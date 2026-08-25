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

use aiken/builtin
use aiken/collection/list
use cardano/address.{Script, VerificationKey}
use programmable_logic/fixture
use programmable_logic/params.{
  ProgrammableLogicGlobalParams, max_inline_datum_bytes_field,
  prog_logic_cred_field, registry_node_cs_field, third_party_cred_field,
  transfer_cred_field, unfracking_cred_field,
}
use registry_node.{RegistryNode}
use types.{
  BaseSpendRedeemer, MintingRegistryProof, OutputIndex, RefInput,
  SpendViaThirdParty, SpendViaTransfer, SpendViaUnfracking, ThirdPartyRedeemer,
  TokenDoesNotExist, TokenExists, TransferRedeemer, UnfrackingRedeemer,
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

// Distinct 28-byte hashes, so a field swap in a layout assertion cannot pass
// by coincidence.
const hash_a: ByteArray =
  #"11111111111111111111111111111111111111111111111111111111"

const hash_b: ByteArray =
  #"22222222222222222222222222222222222222222222222222222222"

const hash_c: ByteArray =
  #"33333333333333333333333333333333333333333333333333333333"

const hash_d: ByteArray =
  #"44444444444444444444444444444444444444444444444444444444"

const node_key: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const node_next: ByteArray =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const node_global_state_cs: ByteArray =
  #"55555555555555555555555555555555555555555555555555555555"

// ------------------------------------------------------ protocol-params datum

// `ProgrammableLogicGlobalParams`: constructor 0, seven fields, in this order:
//   0 registry_node_cs, 1 prog_logic_cred, 2 transfer_cred,
//   3 third_party_cred, 4 unfracking_cred, 5 upgrade_cred,
//   6 max_inline_datum_bytes.
//
// Issue #106 vector 3: `max_inline_datum_bytes` is APPENDED last precisely so
// positions 0-5 are unchanged — this test is what pins that. Field order is
// load-bearing: every accessor is a `tail_list` walk, and the params NFT
// policy (hence PLB's hash, hence every token address) is a function of
// `protocol_params_mint`, which deserialises this exact shape.
test layout_params_datum_seven_fields_in_order() {
  let (tag, fields) = constr(as_data(fixture.protocol_params))
  and {
    tag == 0,
    list.length(fields) == 7,
    field(fields, 0) == as_data(fixture.policy_tokens_registry),
    field(fields, 1) == as_data(fixture.credential_validator_logic_base),
    field(fields, 2) == as_data(fixture.credential_validator_transfer),
    field(fields, 3) == as_data(fixture.credential_validator_third_party),
    field(fields, 4) == as_data(fixture.credential_validator_unfracking),
    field(fields, 5) == as_data(fixture.credential_upgrade_authority),
    field(fields, 6) == as_data(fixture.max_inline_datum_bytes),
  }
}

// The builtin accessors production reads through (PLB, transfer,
// third_party, unfracking) land on the positions the type declares.
test layout_params_accessors_match_raw_positions() {
  let (_, fields) = constr(as_data(fixture.protocol_params))
  and {
    registry_node_cs_field(fields) == fixture.policy_tokens_registry,
    prog_logic_cred_field(fields) == fixture.credential_validator_logic_base,
    transfer_cred_field(fields) == fixture.credential_validator_transfer,
    third_party_cred_field(fields) == fixture.credential_validator_third_party,
    unfracking_cred_field(fields) == fixture.credential_validator_unfracking,
    max_inline_datum_bytes_field(fields) == fixture.max_inline_datum_bytes,
  }
}

// Decode direction: a hand-built constructor 0 with the seven fields in that
// order is accepted as the params type with every field where expected
// (what `protocol_params_mint` does at mint time).
test layout_params_datum_decodes_from_raw_constructor() {
  let raw = builtin.constr_data(
    0,
    [
      as_data(fixture.policy_tokens_registry),
      as_data(fixture.credential_validator_logic_base),
      as_data(fixture.credential_validator_transfer),
      as_data(fixture.credential_validator_third_party),
      as_data(fixture.credential_validator_unfracking),
      as_data(fixture.credential_upgrade_authority),
      as_data(fixture.max_inline_datum_bytes),
    ],
  )
  expect p: ProgrammableLogicGlobalParams = raw
  p == fixture.protocol_params
}

// ------------------------------------------------------ PLB spend redeemer

// `BaseSpendRedeemer`: SpendViaTransfer = constructor 0, SpendViaThirdParty =
// constructor 1, SpendViaUnfracking = constructor 2; all carry
// [params_idx, wdrl_idx] in that order.
test layout_base_spend_redeemer_constructors_and_fields() {
  let (t_tag, t_fields) = constr(
    as_data(SpendViaTransfer { params_idx: 7, wdrl_idx: 3 }),
  )
  let (p_tag, p_fields) = constr(
    as_data(SpendViaThirdParty { params_idx: 7, wdrl_idx: 3 }),
  )
  let (u_tag, u_fields) = constr(
    as_data(SpendViaUnfracking { params_idx: 7, wdrl_idx: 3 }),
  )
  and {
    t_tag == 0,
    t_fields == int_fields([7, 3]),
    p_tag == 1,
    p_fields == int_fields([7, 3]),
    u_tag == 2,
    u_fields == int_fields([7, 3]),
  }
}

test layout_base_spend_redeemer_decodes_from_raw_constructors() {
  expect t: BaseSpendRedeemer = builtin.constr_data(0, int_fields([7, 3]))
  expect p: BaseSpendRedeemer = builtin.constr_data(1, int_fields([7, 3]))
  expect u: BaseSpendRedeemer = builtin.constr_data(2, int_fields([7, 3]))
  and {
    t == SpendViaTransfer { params_idx: 7, wdrl_idx: 3 },
    p == SpendViaThirdParty { params_idx: 7, wdrl_idx: 3 },
    u == SpendViaUnfracking { params_idx: 7, wdrl_idx: 3 },
  }
}

// ------------------------------------------------------ third_party redeemer

// `ThirdPartyRedeemer`: constructor 0, [params_idx, registry_node_idx,
// outputs_start_idx].
test layout_third_party_redeemer_fields() {
  let (tag, fields) = constr(
    as_data(
      ThirdPartyRedeemer {
        params_idx: 1,
        registry_node_idx: 0,
        outputs_start_idx: 2,
      },
    ),
  )
  and {
    tag == 0,
    fields == int_fields([1, 0, 2]),
  }
}

test layout_third_party_redeemer_decodes_from_raw_constructor() {
  expect r: ThirdPartyRedeemer = builtin.constr_data(0, int_fields([1, 0, 2]))
  r == ThirdPartyRedeemer {
    params_idx: 1,
    registry_node_idx: 0,
    outputs_start_idx: 2,
  }
}

// ------------------------------------------------------ transfer redeemer

// `TransferRedeemer`: a single constructor 0 [params_idx, proofs] — the
// former `ProgrammableLogicGlobalRedeemer` lost its ThirdPartyAct and
// UnfrackingAct arms when those paths got their own validators.
// `RegistryProof`: TokenExists = 0, TokenDoesNotExist = 1, each [node_idx].
test layout_transfer_redeemer_constructor_and_fields() {
  let proofs = [TokenExists { node_idx: 2 }, TokenDoesNotExist { node_idx: 3 }]
  let (t_tag, t_fields) = constr(
    as_data(TransferRedeemer { params_idx: 1, proofs }),
  )
  let (e_tag, e_fields) = constr(as_data(TokenExists { node_idx: 2 }))
  let (n_tag, n_fields) = constr(as_data(TokenDoesNotExist { node_idx: 3 }))
  and {
    t_tag == 0,
    list.length(t_fields) == 2,
    field(t_fields, 0) == as_data(1),
    field(t_fields, 1) == as_data(proofs),
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
  expect t: TransferRedeemer = builtin.constr_data(
    0,
    [builtin.i_data(1), raw_proofs],
  )
  t == TransferRedeemer {
    params_idx: 1,
    proofs: [TokenExists { node_idx: 2 }, TokenDoesNotExist { node_idx: 3 }],
  }
}

// ------------------------------------------------------ unfracking redeemer

// `UnfrackingRedeemer`: constructor 0, [params_idx, registry_node_idx,
// outputs_start_idx] — same shape as ThirdPartyRedeemer.
test layout_unfracking_redeemer_fields() {
  let (tag, fields) = constr(
    as_data(
      UnfrackingRedeemer {
        params_idx: 1,
        registry_node_idx: 0,
        outputs_start_idx: 2,
      },
    ),
  )
  and {
    tag == 0,
    fields == int_fields([1, 0, 2]),
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

// ------------------------------------------------------ credential encoding

// `Credential` encodes as the Plutus `Credential`: VerificationKey
// (PubKeyCredential) = constructor 0, Script (ScriptCredential) =
// constructor 1, one bytestring field each. Every credential the protocol
// puts on the wire — the six in the params datum, the four logic
// credentials in a registry node — rides on this encoding, so a flip here
// would silently repoint authorisation from a key to a script.
test layout_credential_constructors_and_field() {
  let (vkey_tag, vkey_fields) = constr(as_data(VerificationKey(hash_a)))
  let (script_tag, script_fields) = constr(as_data(Script(hash_a)))
  and {
    vkey_tag == 0,
    vkey_fields == [as_data(hash_a)],
    script_tag == 1,
    script_fields == [as_data(hash_a)],
  }
}

// ------------------------------------------------------ registry-node datum

// `RegistryNode`: constructor 0, seven fields, in this order:
//   0 key, 1 next, 2 minting_logic_script, 3 transfer_logic_script,
//   4 third_party_transfer_logic_script, 5 unfracking_logic_script,
//   6 global_state_cs.
//
// Field order is load-bearing (see the `RegistryNode` doc comment): the
// minting credential sits at index 2, BEFORE the two transfer credentials,
// keeping the four logic-credential fields contiguous at 2-5 ahead of the
// scalar `global_state_cs`. Off-chain builders and every reader of a node's
// inline datum depend on exactly this shape.
test layout_registry_node_seven_fields_in_order() {
  let node = RegistryNode {
    key: node_key,
    next: node_next,
    minting_logic_script: Script(hash_a),
    transfer_logic_script: Script(hash_b),
    third_party_transfer_logic_script: Script(hash_c),
    // Unset-hook default is a VerificationKey credential — pinned here so
    // the default-deny encoding is covered alongside the Script ones.
    unfracking_logic_script: VerificationKey(hash_d),
    global_state_cs: node_global_state_cs,
  }
  let (tag, fields) = constr(as_data(node))
  and {
    tag == 0,
    list.length(fields) == 7,
    field(fields, 0) == as_data(node_key),
    field(fields, 1) == as_data(node_next),
    field(fields, 2) == as_data(Script(hash_a)),
    field(fields, 3) == as_data(Script(hash_b)),
    field(fields, 4) == as_data(Script(hash_c)),
    field(fields, 5) == as_data(VerificationKey(hash_d)),
    field(fields, 6) == as_data(node_global_state_cs),
  }
}
