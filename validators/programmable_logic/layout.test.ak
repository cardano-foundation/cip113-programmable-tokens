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
use programmable_logic/fixture
use programmable_logic/params.{
  ProgrammableLogicGlobalParams, prog_logic_cred_field, registry_node_cs_field,
  third_party_cred_field, transfer_cred_field, unfracking_cred_field,
}
use types.{
  BaseSpendRedeemer, MintingRegistryProof, OutputIndex,
  ProgrammableLogicGlobalRedeemer, RefInput, RegistryProof, SpendViaGlobal,
  SpendViaThirdParty, ThirdPartyRedeemer, TokenDoesNotExist, TokenExists,
  TransferAct, UnfrackingAct, UnfrackingRedeemer,
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

// `ProgrammableLogicGlobalParams`: constructor 0, six fields, in this order:
//   0 registry_node_cs, 1 prog_logic_cred, 2 transfer_cred,
//   3 third_party_cred, 4 unfracking_cred, 5 upgrade_cred.
test layout_params_datum_six_fields_in_order() {
  let (tag, fields) = constr(as_data(fixture.protocol_params))
  and {
    tag == 0,
    list.length(fields) == 6,
    field(fields, 0) == as_data(fixture.policy_tokens_registry),
    field(fields, 1) == as_data(fixture.credential_validator_logic_base),
    field(fields, 2) == as_data(fixture.credential_validator_logic_global),
    field(fields, 3) == as_data(fixture.credential_validator_third_party),
    field(fields, 4) == as_data(fixture.credential_validator_unfracking),
    field(fields, 5) == as_data(fixture.credential_upgrade_authority),
  }
}

// The builtin accessors production reads through (PLB, PLG, third_party,
// unfracking) land on the positions the type declares.
test layout_params_accessors_match_raw_positions() {
  let (_, fields) = constr(as_data(fixture.protocol_params))
  and {
    registry_node_cs_field(fields) == fixture.policy_tokens_registry,
    prog_logic_cred_field(fields) == fixture.credential_validator_logic_base,
    transfer_cred_field(fields) == fixture.credential_validator_logic_global,
    third_party_cred_field(fields) == fixture.credential_validator_third_party,
    unfracking_cred_field(fields) == fixture.credential_validator_unfracking,
  }
}

// Decode direction: a hand-built constructor 0 with the six fields in that
// order is accepted as the params type with every field where expected
// (what `protocol_params_mint` does at mint time).
test layout_params_datum_decodes_from_raw_constructor() {
  let raw = builtin.constr_data(
    0,
    [
      as_data(fixture.policy_tokens_registry),
      as_data(fixture.credential_validator_logic_base),
      as_data(fixture.credential_validator_logic_global),
      as_data(fixture.credential_validator_third_party),
      as_data(fixture.credential_validator_unfracking),
      as_data(fixture.credential_upgrade_authority),
    ],
  )
  expect p: ProgrammableLogicGlobalParams = raw
  p == fixture.protocol_params
}

// ------------------------------------------------------ PLB spend redeemer

// `BaseSpendRedeemer`: SpendViaGlobal = constructor 0, SpendViaThirdParty =
// constructor 1; both carry [params_idx, wdrl_idx] in that order.
test layout_base_spend_redeemer_constructors_and_fields() {
  let (g_tag, g_fields) = constr(
    as_data(SpendViaGlobal { params_idx: 7, wdrl_idx: 3 }),
  )
  let (t_tag, t_fields) = constr(
    as_data(SpendViaThirdParty { params_idx: 7, wdrl_idx: 3 }),
  )
  and {
    g_tag == 0,
    g_fields == int_fields([7, 3]),
    t_tag == 1,
    t_fields == int_fields([7, 3]),
  }
}

test layout_base_spend_redeemer_decodes_from_raw_constructors() {
  expect g: BaseSpendRedeemer = builtin.constr_data(0, int_fields([7, 3]))
  expect t: BaseSpendRedeemer = builtin.constr_data(1, int_fields([7, 3]))
  and {
    g == SpendViaGlobal { params_idx: 7, wdrl_idx: 3 },
    t == SpendViaThirdParty { params_idx: 7, wdrl_idx: 3 },
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

// ------------------------------------------------------ PLG redeemer

// `ProgrammableLogicGlobalRedeemer` after the split: TransferAct =
// constructor 0 [params_idx, proofs]; UnfrackingAct = constructor 1
// [params_idx] (it was 2 while ThirdPartyAct occupied 1). `RegistryProof`:
// TokenExists = 0, TokenDoesNotExist = 1, each [node_idx].
test layout_plg_redeemer_constructors_and_fields() {
  let proofs = [TokenExists { node_idx: 2 }, TokenDoesNotExist { node_idx: 3 }]
  let (t_tag, t_fields) = constr(as_data(TransferAct { params_idx: 1, proofs }))
  let (u_tag, u_fields) = constr(as_data(UnfrackingAct { params_idx: 1 }))
  let (e_tag, e_fields) = constr(as_data(TokenExists { node_idx: 2 }))
  let (n_tag, n_fields) = constr(as_data(TokenDoesNotExist { node_idx: 3 }))
  and {
    t_tag == 0,
    field(t_fields, 0) == as_data(1),
    field(t_fields, 1) == as_data(proofs),
    u_tag == 1,
    u_fields == int_fields([1]),
    e_tag == 0,
    e_fields == int_fields([2]),
    n_tag == 1,
    n_fields == int_fields([3]),
  }
}

test layout_plg_redeemer_decodes_from_raw_constructors() {
  let raw_proofs = builtin.list_data(
    [
      builtin.constr_data(0, int_fields([2])),
      builtin.constr_data(1, int_fields([3])),
    ],
  )
  expect t: ProgrammableLogicGlobalRedeemer = builtin.constr_data(
    0,
    [builtin.i_data(1), raw_proofs],
  )
  expect u: ProgrammableLogicGlobalRedeemer = builtin.constr_data(
    1,
    int_fields([1]),
  )
  and {
    t == TransferAct {
      params_idx: 1,
      proofs: [TokenExists { node_idx: 2 }, TokenDoesNotExist { node_idx: 3 }],
    },
    u == UnfrackingAct { params_idx: 1 },
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
