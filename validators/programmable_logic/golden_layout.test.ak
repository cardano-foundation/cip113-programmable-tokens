//// Golden Data-layout tests — the on-chain encoding of consensus-critical
//// types, frozen. Ported discipline from the Plutarch reference impl's
//// `GoldenEncoding` suite (wsc-poc): the constructor INDEX and field ORDER
//// of datums and redeemers are consensus rules — a refactor that reorders
//// a record field or a constructor silently changes every script hash and
//// breaks every off-chain builder. These tests turn that into a red test.
////
//// Each test destructures the compiled `Data` with `un_constr_data`, so
//// the assertion is against what the node actually sees, independent of
//// any Aiken-side sugar.

use aiken/builtin.{head_list, un_b_data, un_constr_data, un_i_data}
use cardano/address.{Script, VerificationKey}
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use registry_node.{RegistryNode}
use types.{
  ThirdPartyAct, TokenDoesNotExist, TokenExists, TransferAct, UnfrackingAct,
  UnfrackingRedeemer,
}

const key_28: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const next_28: ByteArray =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const hash_a: ByteArray =
  #"11111111111111111111111111111111111111111111111111111111"

const hash_b: ByteArray =
  #"22222222222222222222222222222222222222222222222222222222"

const hash_c: ByteArray =
  #"33333333333333333333333333333333333333333333333333333333"

const hash_d: ByteArray =
  #"44444444444444444444444444444444444444444444444444444444"

const cs_28: ByteArray =
  #"55555555555555555555555555555555555555555555555555555555"

// Credential encodes as Plutus `Credential`: VerificationKey
// (PubKeyCredential) = constr 0, Script (ScriptCredential) = constr 1,
// one bytestring field each.
test golden_credential_encoding() {
  let Pair(vkey_ix, vkey_fields) = un_constr_data(
    as_data(VerificationKey(hash_a)),
  )
  let Pair(script_ix, script_fields) = un_constr_data(as_data(Script(hash_a)))
  expect [vkey_hash] = vkey_fields
  expect [script_hash] = script_fields
  and {
    (vkey_ix == 0)?,
    (script_ix == 1)?,
    (un_b_data(vkey_hash) == hash_a)?,
    (un_b_data(script_hash) == hash_a)?,
  }
}

// RegistryNode datum: constr 0 with SEVEN fields in declaration order —
// key, next, minting_logic_script, transfer_logic_script,
// third_party_transfer_logic_script, unfracking_logic_script,
// global_state_cs. (Note minting logic sits at index 2, BEFORE the two
// transfer credentials.)
test golden_registry_node_layout() {
  let node = RegistryNode {
    key: key_28,
    next: next_28,
    minting_logic_script: Script(hash_a),
    transfer_logic_script: Script(hash_b),
    third_party_transfer_logic_script: Script(hash_c),
    unfracking_logic_script: VerificationKey(hash_d),
    global_state_cs: cs_28,
  }
  let Pair(ix, fields) = un_constr_data(as_data(node))
  expect  
      [
        f_key, f_next, f_minting, f_transfer, f_third_party, f_unfracking,
        f_global_state,
      ]
    = fields
  and {
    (ix == 0)?,
    (un_b_data(f_key) == key_28)?,
    (un_b_data(f_next) == next_28)?,
    (un_constr_data(f_minting).1st == 1)?,
    (un_b_data(head_list(un_constr_data(f_minting).2nd)) == hash_a)?,
    (un_constr_data(f_transfer).1st == 1)?,
    (un_b_data(head_list(un_constr_data(f_transfer).2nd)) == hash_b)?,
    (un_constr_data(f_third_party).1st == 1)?,
    (un_b_data(head_list(un_constr_data(f_third_party).2nd)) == hash_c)?,
    // Unset-hook default is VerificationKey — constr 0 here.
    (un_constr_data(f_unfracking).1st == 0)?,
    (un_b_data(head_list(un_constr_data(f_unfracking).2nd)) == hash_d)?,
    (un_b_data(f_global_state) == cs_28)?,
  }
}

// Protocol-params datum: constr 0 with THREE fields —
// registry_node_cs, prog_logic_cred, unfracking_cred.
test golden_protocol_params_layout() {
  let params = ProgrammableLogicGlobalParams {
    registry_node_cs: cs_28,
    prog_logic_cred: Script(hash_a),
    unfracking_cred: Script(hash_b),
  }
  let Pair(ix, fields) = un_constr_data(as_data(params))
  expect [f_cs, f_prog, f_unfracking] = fields
  and {
    (ix == 0)?,
    (un_b_data(f_cs) == cs_28)?,
    (un_constr_data(f_prog).1st == 1)?,
    (un_constr_data(f_unfracking).1st == 1)?,
    (un_b_data(head_list(un_constr_data(f_unfracking).2nd)) == hash_b)?,
  }
}

// PLG redeemer constructor indices: TransferAct = 0 (one field, the
// proofs list), ThirdPartyAct = 1 (two Int fields, registry_node_idx
// THEN outputs_start_idx), UnfrackingAct = 2 (no fields).
test golden_plg_redeemer_indices() {
  let Pair(transfer_ix, transfer_fields) = un_constr_data(
    as_data(TransferAct { proofs: [] }),
  )
  let Pair(third_party_ix, third_party_fields) = un_constr_data(
    as_data(ThirdPartyAct { registry_node_idx: 7, outputs_start_idx: 9 }),
  )
  let Pair(unfracking_ix, unfracking_fields) = un_constr_data(
    as_data(UnfrackingAct),
  )
  expect [_proofs] = transfer_fields
  expect [f_node_idx, f_outputs_start] = third_party_fields
  expect [] = unfracking_fields
  and {
    (transfer_ix == 0)?,
    (third_party_ix == 1)?,
    (un_i_data(f_node_idx) == 7)?,
    (un_i_data(f_outputs_start) == 9)?,
    (unfracking_ix == 2)?,
  }
}

// Registry proofs: TokenExists = constr 0, TokenDoesNotExist = constr 1,
// each carrying the node index as its single Int field.
test golden_registry_proof_indices() {
  let Pair(exists_ix, exists_fields) = un_constr_data(
    as_data(TokenExists { node_idx: 3 }),
  )
  let Pair(not_exists_ix, not_exists_fields) = un_constr_data(
    as_data(TokenDoesNotExist { node_idx: 4 }),
  )
  expect [f_exists_idx] = exists_fields
  expect [f_not_exists_idx] = not_exists_fields
  and {
    (exists_ix == 0)?,
    (not_exists_ix == 1)?,
    (un_i_data(f_exists_idx) == 3)?,
    (un_i_data(f_not_exists_idx) == 4)?,
  }
}

// Unfracking redeemer: constr 0 with registry_node_idx THEN
// outputs_start_idx.
test golden_unfracking_redeemer_layout() {
  let Pair(ix, fields) = un_constr_data(
    as_data(UnfrackingRedeemer { registry_node_idx: 5, outputs_start_idx: 6 }),
  )
  expect [f_node_idx, f_outputs_start] = fields
  and {
    (ix == 0)?,
    (un_i_data(f_node_idx) == 5)?,
    (un_i_data(f_outputs_start) == 6)?,
  }
}
