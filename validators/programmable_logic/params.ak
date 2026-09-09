use aiken/builtin.{head_list, tail_list, unconstr_fields}
use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{InlineDatum, Input}
use utils.{has_currency_symbol}

/// Protocol parameters NFT token name
pub const protocol_params_token = "ProtocolParams"

/// Protocol parameters stored on-chain, referenced by every programmable-token
/// transaction. **Every field here has a named on-chain reader** — that is the
/// rule this record is kept to. A writable field nothing reads is a trap: an
/// operator rewrites it, the transaction succeeds, and nothing changes.
///
/// Fields are ordered by read-frequency / hot-path depth. `plg_cred` sits at
/// field 0 because `programmable_logic_base` reads it once per programmable
/// INPUT — the only per-input read in the protocol — so it pays no `tail_list`
/// step at all.
///
/// **Two phases for field order.** BEFORE genesis, order by read frequency
/// and nothing else — no datum exists yet, so nothing can be misread, and
/// this is the last moment the layout is free. AFTER genesis, a new field is
/// APPENDED, never inserted: the accessors below are positional
/// `head_list`/`tail_list` chains over raw `unconstr_fields`, so a field added
/// at the end costs every deployed reader exactly nothing, while one inserted
/// anywhere else silently deepens — or worse, silently re-points — a hot
/// accessor. `issuance_logic_cred` was moved to field 1 under the first rule
/// (2026-09-08, pre-genesis); `pending_upgrade_cred` sits last under the
/// second.
///
/// What is NOT here, and why:
///   * `prog_logic_cred`, `registry_node_cs` and the seizure datum bound are
///     compile-time PARAMETERS of the delegates. A frozen value never needs to
///     be a datum read — it only needs baking into whatever artifact is itself
///     the replaceable unit, and the delegates are exactly that. Both were
///     still declared here while they had a reader left; they have none now, so
///     they are gone. Removing a field is stronger than freezing it, but only
///     over that field: no upgrade can edit these in place, while the VALUES
///     stay reachable one hop away, through a dispatch-layer swap that installs
///     delegates applied with the values of the authority's choosing.
///   * the three delegate HASHES are baked into `programmable_logic_global`,
///     which is why it never reads this datum. The trust chain is
///     PLB -> params -> PLG -> delegate.
///   * `transfer_cred` / `third_party_cred` remain because `issuance_logic`
///     sits on a DIFFERENT chain: it must locate a delegate's REDEEMER to prove
///     that delegate covered a minting policy's registry node (Finding 04
///     precise delegation). Reading them at runtime is what stops a delegate
///     upgrade stranding issuance.
///   * `issuance_logic_cred` is the replaceable half of issuance (#129). The
///     per-token `issuance_mint` policy is permanent by construction — its
///     hash IS the token's policy id — so every rule that may change lives
///     behind this credential instead.
pub type ProgrammableLogicGlobalParams {
  /// Field 0 — credential of the `programmable_logic_global` dispatcher.
  /// **The hot field**: `programmable_logic_base` reads it on every
  /// programmable input and requires its withdraw-0. This one field IS the
  /// upgrade mechanism — rewriting it swaps the entire dispatch layer without
  /// moving PLB's hash, and therefore without moving a single token address.
  /// First because it is the only per-input read: its accessor walks nothing.
  plg_cred: Credential,
  /// Field 1 — credential of the `issuance_logic` withdraw-0 validator (issue
  /// #129). Read ONLY by `issuance_mint`, the permanent per-token policy, to
  /// learn which script currently carries the protocol's issuance rules and
  /// to require its withdraw-0. Rewriting this field is how those rules are
  /// upgraded for EVERY token, including ones already minted — the permanent
  /// policy's bytes never move, so neither does any policy id. Sits at 1 because
  /// it is read once per ISSUANCE transaction — every mint and burn — which is
  /// the second-hottest read after PLB's.
  issuance_logic_cred: Credential,
  /// Field 2 — credential of the `transfer` withdraw-0 validator. Read ONLY by
  /// `issuance_logic`, to locate that validator's redeemer and check it names
  /// the minting policy's own registry node. PLB does not read it.
  transfer_cred: Credential,
  /// Field 3 — credential of the `third_party` (seize / clawback / freeze)
  /// withdraw-0 validator. Read ONLY by `issuance_mint`, same reason as
  /// `transfer_cred`.
  third_party_cred: Credential,
  /// Field 4 — credential of the upgrade-authority withdraw-0 validator
  /// (trampoline 2). Read ONLY by `protocol_params`, on an upgrade
  /// transaction, to decide *who* may rewrite this datum. A datum field rather
  /// than a script parameter so the authority itself can be swapped in place.
  upgrade_cred: Credential,
  /// Field 5 — the INCOMING upgrade authority while a handover is in flight,
  /// `None` at rest. Read ONLY by `protocol_params`, on the spend path.
  ///
  /// Rewriting `upgrade_cred` in one step is forbidden: a hash for a script
  /// that was never deployed, or a typo, hands the protocol to nobody and
  /// there is no repair path, because the credential named here is the only
  /// one that can authorise the next spend. So a handover is two phases —
  /// the sitting authority NOMINATES here, and the nominee ACTIVATES itself
  /// by presenting its own withdraw-0, which is what proves it exists, runs
  /// and consents. Until then the sitting authority can clear this field.
  ///
  /// Deliberately NOT the co-signature rule this repo first drafted (issue
  /// #125), which required the incoming credential's withdraw-0 in the same
  /// transaction as the nomination. That silently restricts who may become
  /// the upgrade authority to parties that can be scheduled into someone
  /// else's transaction — excluding a governance action, or any authority
  /// that assembles its approval over days. Two phases demand the same
  /// evidence without the coordination.
  pending_upgrade_cred: Option<Credential>,
}

/// Authenticate the protocol-params NFT reference input by its
/// caller-supplied index and hand back the raw datum fields. Callers
/// extract only the fields their branch needs via the `*_field` accessors
/// below — cheaper than a full `expect _: ProgrammableLogicGlobalParams`
/// deserialisation, which validates every field on every run.
///
/// The redeemer carries `params_idx`, the index of the params UTxO in
/// `reference_inputs`. Instead of scanning every reference input to find the
/// params policy, we jump straight to `list.at(reference_inputs, params_idx)`
/// and authenticate it by the one-shot params NFT: a wrong index simply fails
/// the NFT check. This also makes Finding 082 structurally impossible — a
/// token-less reference-script UTxO is never inspected unless it is the exact
/// input the caller addressed.
///
/// Skipping whole-datum validation here is safe for the same reason
/// registry_node.ak skips it for RegistryNode: we only consume this
/// datum, and the protocol_params mint handler fully deserialises (and thereby
/// shape-checks) it at mint time, so every instance on-chain is
/// well-formed by construction.
pub fn with_protocol_params_fields(
  reference_inputs: List<Input>,
  protocol_params_cs: PolicyId,
  params_idx: Int,
  return: fn(List<Data>) -> result,
) -> result {
  let protocol_params_ref = list.expect_at(reference_inputs, params_idx)

  // Authenticate: the addressed reference input must carry the params
  // policy. Presence of the policy is sufficient — it is a one-shot NFT
  // (the protocol_params mint handler mints exactly one `ProtocolParams` token), so any
  // UTxO bearing it is the genuine params UTxO. A wrong index fails here
  // rather than silently reading some other UTxO's datum. Kept as a bare
  // policy-presence test (not the stricter name+quantity check) because this
  // runs on the hot path — per delegate withdrawal and per PLB input.
  expect
    has_currency_symbol(protocol_params_ref.output.value, protocol_params_cs)

  expect InlineDatum(inline_datum) = protocol_params_ref.output.datum
  return(unconstr_fields(inline_datum))
}

/// Field 0: the `programmable_logic_global` dispatcher credential. THE hot
/// accessor — `programmable_logic_base` calls it once per programmable input,
/// so it sits at depth zero: `head_list` and nothing else.
pub fn plg_cred_field(fields: List<Data>) -> Credential {
  expect plg_cred: Credential = head_list(fields)
  plg_cred
}

/// Field 1: the `issuance_logic` withdraw-0 credential. Read by
/// `issuance_mint` once per issuance transaction: one `tail_list`.
pub fn issuance_logic_cred_field(fields: List<Data>) -> Credential {
  expect issuance_logic_cred: Credential = head_list(tail_list(fields))
  issuance_logic_cred
}

/// Field 2: the `transfer` withdraw-0 credential. Read only by
/// `issuance_logic`, on the delegated path.
pub fn transfer_cred_field(fields: List<Data>) -> Credential {
  expect transfer_cred: Credential = head_list(tail_list(tail_list(fields)))
  transfer_cred
}

/// Field 3: the `third_party` withdraw-0 credential. Read only by
/// `issuance_logic`, on the delegated path.
pub fn third_party_cred_field(fields: List<Data>) -> Credential {
  expect third_party_cred: Credential = head_list(
    tail_list(tail_list(tail_list(fields))),
  )
  third_party_cred
}
// No accessor for field 4 (`upgrade_cred`) or field 5 (`pending_upgrade_cred`):
// their only reader, the protocol_params spend handler, deserialises the
// whole record on its cold path.
