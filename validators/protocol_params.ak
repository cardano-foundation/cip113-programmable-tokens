//// The protocol-params UTxO — one script, two purposes.
////
//// The protocol-params UTxO holds the protocol-params NFT and the
//// `ProgrammableLogicGlobalParams` datum: the live wiring every programmable
//// token transaction reads. `mint` creates it, exactly once; `spend` makes it
//// upgradable in place while holding the rails that must never bend.
////
//// Merging the pair into ONE multi-purpose validator collapses two hashes into
//// one: every handler of a `validator` block shares a single script hash, so
//// the protocol-params NFT policy id (this script as a minting policy) and the
//// protocol-params address's payment credential (this script as a spending
//// validator) are now THE SAME VALUE, by construction rather than by
//// deployment discipline.
////
//// Two parameters disappear as a direct consequence:
////
////   * `params_spend_addr_hash` — the mint handler used to be told, as a
////     compile-time parameter, which address the NFT must be locked at. It now
////     names itself: `Script(own_policy)`.
////   * `_nonce` — the spend handler carried an unused parameter whose only job
////     was giving each deployment its own address, because it could not be
////     parameterised by the NFT policy (that policy is the hash of the mint
////     script, which was parameterised by this address — a cycle). Merged,
////     the cycle is gone and `utxo_ref` on the mint side already makes every
////     deployment unique. The protocol's identity was always the NFT asset
////     class rather than the address, which is why nothing is lost here.
////
//// Division of labour (deliberate — see the in-place-upgradability design doc):
////   * The STRUCTURAL rails live here, in both handlers: the NFT is created
////     once and continues, it stays at this address, non-ADA value is
////     conserved, the datum stays well-formed, and every credential in it is a
////     well-formed 28-byte hash. `params_wellformed` is called by BOTH
////     handlers, so the state the spend refuses to move to is also a state the
////     mint refuses to create.
////     There are no frozen-field rails left to enforce: `prog_logic_cred` and
////     `registry_node_cs` are no longer datum fields at all — they are
////     compile-time parameters of the delegates. Note precisely what that does
////     and does not buy. The FIELDS are unrepresentable, so no upgrade can edit
////     them in place. The VALUES are still reachable one hop away: an upgrade
////     that rewrites `plg_cred` installs a dispatch layer naming delegate
////     hashes of the authority's choosing, and those delegates carry whatever
////     `prog_logic_cred` and `registry_node_cs` they were applied with. That is
////     the same authority acting in the same transaction, not a separate
////     escape — and it is the pre-existing shape of the upgrade threat model,
////     unchanged here.
////   * The AUTHORISATION decision ("may this upgrade happen?") is trampolined to
////     the `upgrade_cred` withdraw-0 named in the CURRENT (spent) datum.
////     This validator never inspects that authority's internals — no signer
////     keys, no threshold — so the authority model (federated multisig now, a
////     governance-action validator later) can be swapped by rewriting one datum
////     field, with no change here and no residue left behind.
////
////     CHANGING that authority is two-phase, and is the one thing the sitting
////     authority cannot do in a single step (issue #125). Phase 1: the sitting
////     authority writes `pending_upgrade_cred` — an ordinary upgrade, and
////     reversible by another one. Phase 2: the nominee presents its OWN
////     withdraw-0, which promotes it and clears the nomination, and is the
////     only transaction shape that may move `upgrade_cred` at all.
////
////     The evidence demanded is that the incoming authority exists, runs and
////     consents — so a typo, or the hash of a script nobody deployed, can
////     never take over. That is the same evidence a co-signature would give,
////     WITHOUT requiring the nominee to appear in a transaction built by
////     someone else, which no governance action and no slowly-assembled
////     quorum can promise. Splitting the phases is what buys that, and it is
////     why the co-signature form drafted in #125 was rejected.
////
//// v1 policy choices:
////   * value: non-ADA assets STRICTLY equal, in both directions — the NFT can
////     never be split away and junk can never be injected. LOVELACE IS
////     UNCONSTRAINED relative to the input. It used to ratchet upward, which
////     made over-funding unrecoverable by anyone forever; the ratchet defended
////     against nothing, because the ledger's own min-UTxO rule is the real
////     floor and the only party who can spend this UTxO at all is the upgrade
////     authority — already trusted to replace every credential in the datum,
////     including its own successor.
////   * timelock: NONE. The seam is here (validity interval is in `self`) but no
////     delay is enforced in v1.

use aiken/collection/list
use aiken/collection/pairs
use assets.{has_policy_nft_strictly} as my_assets
use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}
use linked_list.{is_28_byte_credential}
use programmable_logic/params.{
  ProgrammableLogicGlobalParams, protocol_params_token,
}
use types.{
  NominateAuthority, PromoteAuthority, ProtocolParamsRedeemer, ProtocolUpgrade,
}

/// Every credential in the datum must be a well-formed 28-byte hash.
///
/// A reward account is a header byte + 28-byte hash, so a wrong-length hash can
/// never appear in `tx.withdrawals`. Writing one here is a ONE-WAY BRICK: an
/// unsatisfiable `upgrade_cred` makes this validator's own authority check
/// permanently unsatisfiable, with no repair path, and an unsatisfiable
/// `plg_cred` makes every programmable token UTxO unspendable. `plg_cred` is
/// checked first because it is the one credential on the SPEND path, and so the
/// widest brick this validator can prevent.
///
/// Shared by BOTH handlers on purpose. The rail used to exist only on the
/// update path, which left the protocol able to be BORN in exactly the state
/// every later update is refused for.
fn params_wellformed(
  params: ProgrammableLogicGlobalParams,
  is_init init: Bool,
) -> Bool {
  and {
    is_28_byte_credential(params.plg_cred)?,
    is_28_byte_credential(params.transfer_cred)?,
    is_28_byte_credential(params.third_party_cred)?,
    is_28_byte_credential(params.upgrade_cred)?,
    pending_wellformed(params.pending_upgrade_cred, is_init: init)?,
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
fn pending_wellformed(pending: Option<Credential>, is_init init: Bool) -> Bool {
  when pending is {
    None -> True
    Some(cred) -> and {
        (!init)?,
        is_28_byte_credential(cred)?,
      }
  }
}

/// The datum rail: inline, and decodes as `ProgrammableLogicGlobalParams`.
/// Returns the VALUE, because both handlers need to constrain the fields and
/// not merely confirm they parse.
fn output_params(output: Output) -> ProgrammableLogicGlobalParams {
  expect InlineDatum(datum) = output.datum
  expect params: ProgrammableLogicGlobalParams = datum
  params
}

/// The sitting authority approves, via its withdraw-0. Shared by the two
/// arms it authorises; the NOMINEE's withdrawal is checked separately, in
/// `promote_authority`, because it is a different credential from a different
/// datum field proving a different thing.
fn sitting_authority_approves(
  old: ProgrammableLogicGlobalParams,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  pairs.has_key(withdrawals, old.upgrade_cred)
}

/// `ProtocolUpgrade`: rewrite mutable wiring. `upgrade_cred` may not move —
/// that is the rail the whole two-phase design rests on, since a direct
/// rewrite would reinstate the one-way brick this issue exists to close. The
/// NOMINATION may not move either, so a handover can never begin inside a
/// transaction that presents itself as a parameter change.
fn protocol_upgrade(
  old: ProgrammableLogicGlobalParams,
  new: ProgrammableLogicGlobalParams,
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
  old: ProgrammableLogicGlobalParams,
  new: ProgrammableLogicGlobalParams,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  and {
    sitting_authority_approves(old, withdrawals)?,
    (new == ProgrammableLogicGlobalParams {
      ..old,
      pending_upgrade_cred: new.pending_upgrade_cred,
    })?,
  }
}

/// `PromoteAuthority`: phase 2. The standing nominee presents its OWN
/// withdraw-0 — the evidence that it exists, is a script that can run, and
/// consents to take over — and becomes the authority.
///
/// The promotion is PURE, as one record equality: the only permitted
/// difference is that the nomination has become the authority. Written
/// field-by-field this rail leaks — a field added later is simply not
/// mentioned, and the omission is invisible (mutation-verified 2026-09-07:
/// the `transfer_cred` comparison in the first draft killed no test, and
/// would have gone on killing none as fields accumulated). Same shape as
/// `linked_list.is_updated_directory_node`.
///
/// Splitting promotion from upgrading is what keeps revocation meaningful:
/// nomination and revocation race by construction, and if the nominee wins
/// that race the outcome is the handover the sitting authority already
/// consented to — never a handover plus an arbitrary protocol change smuggled
/// into the very transaction the sitting authority was trying to abort.
fn promote_authority(
  old: ProgrammableLogicGlobalParams,
  new: ProgrammableLogicGlobalParams,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  expect Some(nominee) = old.pending_upgrade_cred
  and {
    pairs.has_key(withdrawals, nominee)?,
    (new == ProgrammableLogicGlobalParams {
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
    expect has_policy_nft_strictly(self.mint, own_policy, protocol_params_token)

    // `has_nft_strict` is strict about the WHOLE value, not just the policy:
    // it matches only a value whose non-ADA half is exactly this one NFT. So
    // this finder is also the no-junk-token rail — an output bundling another
    // asset with the params NFT is simply not found, and genesis fails. A
    // separate value check here would be dead code (mutation-verified: it
    // killed no test).
    let nft_output = list.expect_find(
      self.outputs,
      fn(output) {
        assets.has_nft_strict(output.value, own_policy, protocol_params_token)
      },
    )

    let genesis_params = output_params(nft_output)

    and {
      // Genesis must satisfy the rails every later update satisfies — the
      // protocol must not be born in a state the spend handler would refuse to
      // move to.
      // `is_init: True` is what additionally forbids a nomination baked into
      // the genesis datum — see `pending_wellformed`.
      params_wellformed(genesis_params, is_init: True)?,
      // A reference script here is paid for by every transaction that
      // references this UTxO. The spend handler already forbids one on the
      // continuing output; genesis is where that asymmetry started.
      (nft_output.reference_script == None)?,
      // Locked at THIS script, wearing its spending hat. No parameter is needed
      // to say so: the mint and spend handlers share one hash, so the policy
      // minting the NFT IS the credential that must lock it.
      (nft_output.address == address.from_script(own_policy))?,
    }
  }

  spend(
    datum: Option<ProgrammableLogicGlobalParams>,
    redeemer: ProtocolParamsRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    trace @"Starting protocol_params spend validation"

    // Current wiring, from the UTxO being spent. `upgrade_cred` here is the
    // authority that must approve this spend.
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
    // unconstrained relative to the input; see the v1 policy note above.
    expect assets.expect_match_assets(cont.value, own_input.output.value)?

    // Continuing datum must be inline, well-formed, and carry only well-formed
    // credentials — the rail that stops an upgrade from bricking PLB / delegate
    // datum reads. No value rail is needed here: exact non-ADA equality above
    // already carries genesis's shape forward.
    let new_params = output_params(cont)
    expect params_wellformed(new_params, is_init: False)?

    // Authorisation (trampoline 2). The redeemer DECLARES which of the three
    // upgrade-path shapes this is, and each arm is one closed rule set read
    // against the OLD datum — the state being spent decides who may spend it.
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
