//// Coordination-UTxO spending validator (in-place upgradability, trampoline 2).
////
//// The coordination UTxO holds the protocol-params NFT and the
//// `ProgrammableLogicGlobalParams` datum — the live wiring every programmable
//// token transaction reads. Replacing the old always-fail lock, this validator
//// makes that UTxO spendable so the wiring can be UPGRADED in place, while
//// freezing the invariants that must never change.
////
//// Division of labour (deliberate — see the in-place-upgradability design doc):
////   * THIS spend validator enforces the STRUCTURAL rails: the NFT continues,
////     stays at this address, value is conserved, the datum stays well-formed,
////     and the permanently-frozen fields (`prog_logic_cred`, `registry_node_cs`)
////     are unchanged. These can never be delegated away.
////   * The AUTHORISATION decision ("may this upgrade happen?") is trampolined to
////     the `upgrade_cred` withdraw-0 named in the CURRENT (spent) datum.
////     This validator never inspects that authority's internals — no signer
////     keys, no threshold — so the authority model (federated multisig now, a
////     governance-action validator later) can be swapped by rewriting one datum
////     field, with no change here and no residue left behind.
////
//// Cycle note: this validator is parameterised by an arbitrary `nonce`, NOT by
//// the params NFT policy. The NFT policy is the hash of `protocol_params_mint`,
//// which is itself parameterised by THIS validator's address — so depending on
//// the policy here would be circular. Instead the coordination UTxO is
//// identified structurally (sole input/output at this address) and the NFT is
//// preserved by strict value conservation. Safety does not rest on naming the
//// policy: the params NFT is one-shot, so only one genuine coordination UTxO can
//// ever exist, and the readers (PLB / delegate) locate it by that policy themselves.
//// The `nonce` only gives each deployment its own coordination address.
////
//// v1 policy choices (both are single-line changes if revisited):
////   * value: non-ADA assets STRICTLY equal; ADA ratchets (output >= input),
////     so a min-UTxO parameter rise can always be absorbed by topping up and
////     can never strand the coordination UTxO. The ratchet is one-way:
////     over-funding is unrecoverable by design.
////   * timelock: NONE. The seam is here (validity interval is in `self`) but no
////     delay is enforced in v1.

use aiken/collection/list
use cardano/assets
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use linked_list.{is_28_byte_credential}
use pairs
use programmable_logic/params.{ProgrammableLogicGlobalParams}

validator coordination_spend(_nonce: ByteArray) {
  spend(
    datum: Option<ProgrammableLogicGlobalParams>,
    _redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    trace @"Starting coordination_spend validation"

    // Current wiring, from the UTxO being spent. `upgrade_cred` here is the
    // authority that must approve this spend; the frozen fields anchor the check.
    expect Some(old_params) = datum

    // Own input + own address (the coordination address). All structural checks
    // key on this input so junk UTxOs parked at the address cannot interfere.
    expect Some(own_input) = find_input(self.inputs, own_ref)
    let own_address = own_input.output.address

    // Exactly one input at this address: never spend two coordination-address
    // UTxOs in one tx (removes any multi-input ambiguity / double-satisfaction).
    expect [_] = list.filter(
      self.inputs,
      fn(i) { i.output.address == own_address },
    )

    // Exactly one continuing output, at this address: the coordination UTxO
    // continues, singular.
    expect [cont] = list.filter(
      self.outputs,
      fn(o) { o.address == own_address },
    )

    // Value conservation: non-ADA assets must match EXACTLY — preserving the
    // NFT, forbidding junk-token injection and splitting the NFT away — while
    // ADA may only grow (top-up allowed, drain forbidden), so a min-UTxO
    // parameter rise can never strand the coordination UTxO.
    expect assets.expect_match(cont.value, own_input.output.value, >=)?

    // Continuing datum must be inline and a well-formed ProgrammableLogicGlobalParams
    // — the rail that stops an upgrade from bricking PLB / delegate datum reads.
    expect InlineDatum(cont_datum) = cont.datum
    expect new_params: ProgrammableLogicGlobalParams = cont_datum

    and {
      // Frozen anchors — an upgrade may never change these.
      // prog_logic_cred IS every token's payment credential (address); changing
      // it would strand all tokens. registry_node_cs is the registry, which is
      // deliberately outside upgrade scope.
      (new_params.prog_logic_cred == old_params.prog_logic_cred)?,
      (new_params.registry_node_cs == old_params.registry_node_cs)?,
      // Every MUTABLE credential must be a well-formed 28-byte hash. A reward
      // account is a header byte + 28-byte hash, so a wrong-length hash can
      // never appear in tx.withdrawals. Writing one here is a ONE-WAY BRICK:
      // an unsatisfiable upgrade_cred makes this validator's own
      // authority check below permanently unsatisfiable, with no repair path,
      // and an unsatisfiable transfer_cred makes every programmable
      // token UTxO unspendable. Same rule linked_list.ak already applies to
      // every registry-node credential.
      is_28_byte_credential(new_params.transfer_cred)?,
      is_28_byte_credential(new_params.unfracking_cred)?,
      is_28_byte_credential(new_params.upgrade_cred)?,
      // Same one-way-brick rule for the third-party validator credential: a
      // wrong-length hash can never appear in tx.withdrawals, so writing one
      // would make every SpendViaThirdParty base spend permanently
      // unsatisfiable (freezing the third-party/seize path for all policies).
      is_28_byte_credential(new_params.third_party_cred)?,
      // No reference script may be attached to the coordination UTxO.
      (cont.reference_script == None)?,
      // Authorisation (trampoline 2): the CURRENT datum's upgrade authority must
      // approve, via its withdraw-0. Read from the OLD datum on purpose — the
      // sitting authority authorises every change, including a change of authority.
      // The upgrade authority's withdraw-0 must be present; mirrors the
      // trampoline-1 check in programmable_logic_base.
      self.withdrawals |> pairs.has_key_or_fail(old_params.upgrade_cred),
    }
  }

  else(_) {
    fail
  }
}
