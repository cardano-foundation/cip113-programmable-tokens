//// The protocol-params UTxO — one script, two purposes.
////
//// The protocol-params UTxO holds the protocol-params NFT and the
//// `ProtocolParams` datum: the live wiring every programmable
//// token transaction reads. `mint` creates it, exactly once; `spend` makes it
//// upgradable in place while holding the rails that must never bend.
////
//// Every handler of a `validator` block shares a single script hash, so the
//// protocol-params NFT policy id (this script as a minting policy) and the
//// protocol-params address's payment credential (this script as a spending
//// validator) are THE SAME VALUE, by construction. The mint handler needs no
//// address parameter: the NFT is locked at `Script(own_policy)`, which it
//// names itself. The spend handler needs no nonce parameter either:
//// `utxo_ref` on the mint side already makes every deployment's policy id —
//// and so its address — unique. The protocol's identity is the NFT asset
//// class, not the address.
////
//// Division of labour:
////   * The STRUCTURAL rails live here, in both handlers: the NFT is created
////     once and continues, it stays at this address, non-ADA value is
////     conserved, the datum stays well-formed, and every credential in it is a
////     well-formed 28-byte hash. `params_well_formed` is called by BOTH
////     handlers, so the state the spend refuses to move to is also a state the
////     mint refuses to create.
////     `programmable_logic_base_cred` and `registry_node_cs` are compile-time
////     parameters of the delegates, not datum fields — no upgrade can edit
////     them in place. The VALUES are still reachable one hop away: an upgrade
////     that rewrites `programmable_logic_global_cred` installs a dispatch layer naming delegate
////     hashes of the authority's choosing, and those delegates carry whatever
////     `programmable_logic_base_cred` and `registry_node_cs` they were applied with. That is
////     the same authority acting in the same transaction, not a separate
////     escape.
////     `upgrade_cred` and `pending_upgrade_cred` ARE datum fields, and each
////     redeemer arm freezes the one it does not own: `ProtocolUpgrade`
////     freezes the nomination, `NominateAuthority` freezes everything but the
////     nomination, so an authority handover can never ride inside a
////     transaction that looks like a parameter change.
////   * The AUTHORISATION decision ("may this upgrade happen?") is trampolined to
////     the `upgrade_cred` withdraw-0 named in the CURRENT (spent) datum.
////     This validator never inspects that authority's internals — no signer
////     keys, no threshold — so the authority model (federated multisig now, a
////     governance-action validator later) can be swapped by rewriting one datum
////     field, with no change here and no residue left behind.
////
////     CHANGING that authority is two-phase — the one thing the sitting
////     authority cannot do in a single step. Phase 1, under
////     `NominateAuthority`: the sitting authority writes
////     `pending_upgrade_cred`, an ordinary, reversible upgrade. Phase 2,
////     under `PromoteAuthority`: the nominee presents its OWN withdraw-0,
////     which promotes it and clears the nomination, and is the only
////     transaction shape that may move `upgrade_cred` at all.
////
////     The evidence demanded is that the incoming authority exists, runs and
////     consents — so a typo, or the hash of a script nobody deployed, can
////     never take over — without requiring the nominee to appear in a
////     transaction built by someone else, which no governance action and no
////     slowly-assembled quorum can promise. Splitting the phases is what buys
////     that.
////
//// Value policy: non-ADA assets STRICTLY equal, in both directions — the NFT
//// can never be split away and junk can never be injected. LOVELACE IS
//// UNCONSTRAINED relative to the input: the ledger's own min-UTxO rule is
//// the real floor, and the only parties who can spend this UTxO at all are
//// the sitting authority, or a standing nominee — both already trusted to
//// replace every credential in the datum, including the authority's own
//// successor.
////
//// Timelock: NONE. The validity interval is available in `self` but no delay
//// is enforced.

use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}
use linked_list.{is_28_byte_credential}
use prog_assets.{expect_only_nft_of_policy}
use programmable_logic/params.{ProtocolParams, protocol_params_token}
use types.{
  NominateAuthority, PromoteAuthority, ProtocolParamsRedeemer, ProtocolUpgrade,
}

/// Every credential in the datum must be a well-formed 28-byte hash.
///
/// A reward account is a header byte + 28-byte hash, so a wrong-length hash can
/// never appear in `tx.withdrawals`. Writing an unsatisfiable `upgrade_cred`
/// is a ONE-WAY BRICK for every future `ProtocolUpgrade` or
/// `NominateAuthority` spend, since both require the sitting authority's own
/// withdraw-0. A standing nomination is the one repair path: `PromoteAuthority`
/// authorises on the NOMINEE's withdraw-0 instead, so a nomination made before
/// the brick can still take over. An unsatisfiable `programmable_logic_global_cred`
/// makes every programmable token UTxO unspendable. `programmable_logic_global_cred`
/// is checked first because it is on the programmable-token spend path
/// (`programmable_logic_base.ak:64-66`), the widest brick this validator can
/// prevent.
///
/// Shared by BOTH handlers on purpose: the mint refuses to create a state the
/// spend would refuse to move to, so the protocol cannot be born in a state no
/// later update could reach.
fn params_well_formed(params: ProtocolParams, is_init init: Bool) -> Bool {
  and {
    is_28_byte_credential(params.programmable_logic_global_cred)?,
    is_28_byte_credential(params.issuance_logic_cred)?,
    is_28_byte_credential(params.transfer_cred)?,
    is_28_byte_credential(params.third_party_cred)?,
    is_28_byte_credential(params.upgrade_cred)?,
    pending_well_formed(params.pending_upgrade_cred, is_init: init)?,
  }
}

/// A nominee is held to the same 28-byte standard as a sitting authority, one
/// phase before it could matter — a wrong-length nomination is refused at
/// nomination time rather than becoming a nominee that can never activate.
///
/// AT INIT the field must additionally be EMPTY. A protocol born mid-handover
/// would hand a nominee the power to take the authority before the deployer
/// had ever exercised it, and nothing legitimate needs it: the sitting
/// authority can nominate one block later, where the act is visible and
/// revocable. Carrying the distinction as a flag on the shared rail — rather
/// than as a separate line at the mint site — is what keeps "the state genesis
/// may create" and "the state an update may move to" defined in one place.
fn pending_well_formed(pending: Option<Credential>, is_init init: Bool) -> Bool {
  when pending is {
    None -> True
    Some(cred) -> and {
        (!init)?,
        is_28_byte_credential(cred)?,
      }
  }
}

/// The datum rail: inline, and decodes as `ProtocolParams`.
/// Returns the VALUE, because both handlers need to constrain the fields and
/// not merely confirm they parse.
fn expect_output_params(output: Output) -> ProtocolParams {
  expect InlineDatum(datum) = output.datum
  expect params: ProtocolParams = datum
  params
}

/// The sitting authority approves, via its withdraw-0. Shared by the two
/// arms it authorises; the NOMINEE's withdrawal is checked separately, in
/// `promote_authority`, because it is a different credential from a different
/// datum field proving a different thing.
fn sitting_authority_approves(
  old: ProtocolParams,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  pairs.has_key(withdrawals, old.upgrade_cred)
}

/// `ProtocolUpgrade`: rewrite mutable wiring. `upgrade_cred` may not move —
/// that is the rail the whole two-phase design rests on, since a direct
/// rewrite would reinstate the one-way brick a wrong-length or undeployed
/// hash would cause. The NOMINATION may not move either, so a handover can
/// never begin inside a transaction that presents itself as a parameter
/// change.
fn protocol_upgrade(
  old: ProtocolParams,
  new: ProtocolParams,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  and {
    sitting_authority_approves(old, withdrawals)?,
    (new.upgrade_cred == old.upgrade_cred)?,
    (new.pending_upgrade_cred == old.pending_upgrade_cred)?,
  }
}

/// `NominateAuthority`: phase 1. The nomination is the ONLY thing that may
/// change — `Some(c)` to nominate or re-nominate, `None` to revoke. Expressed
/// as one record equality over everything else, so a field added to the datum
/// later is frozen here automatically rather than silently omitted.
///
/// Nothing takes effect: `upgrade_cred` is untouched, and the nominee holds no
/// power until it activates itself.
fn nominate_authority(
  old: ProtocolParams,
  new: ProtocolParams,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  and {
    sitting_authority_approves(old, withdrawals)?,
    (new == ProtocolParams {
      ..old,
      pending_upgrade_cred: new.pending_upgrade_cred,
    })?,
  }
}

/// `PromoteAuthority`: phase 2. The standing nominee presents its OWN
/// withdraw-0 — the evidence that its reward account is registered, that it
/// can produce a withdrawal (a script that runs, or a key that signs), and
/// that it consents to take over — and becomes the authority. Both
/// credential forms are accepted: `pending_well_formed` requires only a
/// 28-byte hash, and a stake key's reward account keys the withdrawal map
/// by `VerificationKey`.
///
/// The promotion is PURE, as one record equality: the only permitted
/// difference is that the nomination has become the authority. Written
/// field-by-field this rail leaks — a field added later is simply not
/// mentioned, and the omission is invisible. Same shape as
/// `linked_list.is_updated_registry_node`.
///
/// Splitting promotion from upgrading is what keeps revocation meaningful:
/// nomination and revocation race by construction, and if the nominee wins
/// that race the outcome is the handover the sitting authority already
/// consented to — never a handover plus an arbitrary protocol change smuggled
/// into the very transaction the sitting authority was trying to abort.
fn promote_authority(
  old: ProtocolParams,
  new: ProtocolParams,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  expect Some(nominee) = old.pending_upgrade_cred
  and {
    pairs.has_key(withdrawals, nominee)?,
    (new == ProtocolParams {
      ..old,
      upgrade_cred: nominee,
      pending_upgrade_cred: None,
    })?,
  }
}

validator protocol_params(utxo_ref: OutputReference) {
  mint(_redeemer: Data, own_policy: PolicyId, self: Transaction) {
    trace @"Starting protocol_params mint validation"

    // One-shot: the named UTxO must be consumed, so this policy can mint once
    // and only once, and every deployment gets a distinct policy id.
    list.expect_any(
      self.inputs,
      fn(input) { input.output_reference == utxo_ref },
    )

    // Exactly one token, named `ProtocolParams`, under this policy.
    expect
      expect_only_nft_of_policy(self.mint, own_policy, protocol_params_token)

    // `has_nft_strict` is strict about the WHOLE value, not just the policy:
    // it matches only a value whose non-ADA half is exactly this one NFT. So
    // this finder is also the no-junk-token rail — an output bundling another
    // asset with the params NFT is simply not found, and genesis fails. A
    // separate value check here would be dead code.
    let nft_output = list.expect_find(
      self.outputs,
      fn(output) {
        assets.has_nft_strict(output.value, own_policy, protocol_params_token)
      },
    )

    let genesis_params = expect_output_params(nft_output)

    and {
      // Genesis must satisfy the rails every later update satisfies — the
      // protocol must not be born in a state the spend handler would refuse to
      // move to.
      // `is_init: True` is what additionally forbids a nomination baked into
      // the genesis datum — see `pending_well_formed`.
      params_well_formed(genesis_params, is_init: True)?,
      // No reference script may be attached to the protocol-params UTxO, on
      // either handler: one here would be paid for by every transaction that
      // references this UTxO.
      (nft_output.reference_script == None)?,
      // Locked at THIS script, wearing its spending hat. No parameter is needed
      // to say so: the mint and spend handlers share one hash, so the policy
      // minting the NFT IS the credential that must lock it. `from_script`
      // carries no stake credential, so the params UTxO can never be
      // delegated.
      (nft_output.address == address.from_script(own_policy))?,
    }
  }

  spend(
    datum: Option<ProtocolParams>,
    redeemer: ProtocolParamsRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    trace @"Starting protocol_params spend validation"

    // Current wiring, from the UTxO being spent. `upgrade_cred` is the
    // authority for the `ProtocolUpgrade` and `NominateAuthority` arms;
    // `PromoteAuthority` is authorised by the standing nominee instead.
    expect Some(old_params) = datum

    // Own input + own address (the protocol-params address). All structural checks
    // key on this input so junk UTxOs parked at the address cannot interfere.
    let own_input = list.expect_find(
      self.inputs,
      fn(i) { i.output_reference == own_ref },
    )
    let own_address = own_input.output.address

    // No "exactly one input at this address" rail, on purpose. Double
    // satisfaction is already dead: the continuing output is singular (below),
    // its non-ADA value must equal THIS input's exactly, and only one UTxO can
    // ever carry the one-shot params NFT — so a second input at the address
    // has different non-ADA content, and its own run of this validator fails
    // the transaction. Proven by `params_spend_fails_junk_run_alongside_genuine`.
    // Exactly one continuing output, at this address: the protocol-params UTxO
    // continues, singular.
    expect [cont] = list.filter(
      self.outputs,
      fn(o) { o.address == own_address },
    )

    // No reference script may be attached to the protocol-params UTxO.
    expect (cont.reference_script == None)?

    // Value: non-ADA assets must match EXACTLY — preserving the NFT, forbidding
    // junk-token injection and splitting the NFT away. Lovelace is deliberately
    // unconstrained relative to the input; see the value policy note above.
    expect assets.expect_match_assets(cont.value, own_input.output.value)?

    // Continuing datum must be inline, well-formed, and carry only well-formed
    // credentials — the rail that stops an upgrade from bricking PLB / delegate
    // datum reads. No value rail is needed here: exact non-ADA equality above
    // already carries genesis's shape forward.
    let new_params = expect_output_params(cont)
    expect params_well_formed(new_params, is_init: False)?

    // Authorisation, via the `upgrade_cred` withdraw-0. The redeemer DECLARES
    // which of the three upgrade-path shapes this is, and each arm is one
    // closed rule set read against the OLD datum — the state being spent
    // decides who may spend it.
    //
    // Declaring the action is not decoration: it is what makes the three rule
    // sets mutually exclusive. `ProtocolUpgrade` freezes the nomination and
    // `NominateAuthority` freezes everything else, so an authority handover
    // can never begin inside a transaction that looks like a parameter
    // change, and a promotion can never carry one.
    when redeemer is {
      ProtocolUpgrade ->
        protocol_upgrade(old_params, new_params, self.withdrawals)
      NominateAuthority ->
        nominate_authority(old_params, new_params, self.withdrawals)
      PromoteAuthority ->
        promote_authority(old_params, new_params, self.withdrawals)
    }
  }

  else(_) {
    fail
  }
}
