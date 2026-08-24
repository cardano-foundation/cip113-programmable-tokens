use aiken/builtin.{head_list, tail_list, unconstr_fields}
use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{InlineDatum, Input}

/// Protocol parameters NFT token name
pub const protocol_params_token = "ProtocolParams"

/// Protocol parameters stored on-chain, referenced by all programmable-token
/// transactions. Fields are ordered by read-frequency / hot-path depth: the
/// registry policy and base payment credential (read by the transfer /
/// third-party containment checks) first, then the two credentials
/// programmable_logic_base dispatches to on every per-input spend
/// (`transfer_cred`, `third_party_cred`), then the rarer `unfracking_cred`,
/// then the coldest `upgrade_cred` (read only by coordination_spend).
/// `max_inline_datum_bytes` is appended LAST so that adding it left every
/// pre-existing accessor at its original depth; it is read once per delegate
/// invocation rather than per input, so paying six `tail_list` hops for it
/// once per transaction is cheaper than displacing a hot field.
pub type ProgrammableLogicGlobalParams {
  /// Field 0 — currency symbol of the registry node NFTs.
  registry_node_cs: PolicyId,
  /// Field 1 — the programmable-logic-base PAYMENT credential: the shared
  /// payment credential every programmable-token UTxO lives at.
  prog_logic_cred: Credential,
  /// Field 2 — credential of the `transfer` withdraw-0 validator.
  /// programmable_logic_base requires it on a `SpendViaTransfer` dispatch.
  /// This is what makes the transfer validator swappable in place: an
  /// upgrade rewrites this field instead of re-deploying PLB (whose hash
  /// anchors every token address).
  transfer_cred: Credential,
  /// Field 3 — credential of the standalone third-party-transfer (seize /
  /// clawback / freeze) withdraw-0 validator. programmable_logic_base requires
  /// it on a `SpendViaThirdParty` dispatch. Swappable in place.
  third_party_cred: Credential,
  /// Field 4 — credential of the `unfracking` withdraw-0 validator
  /// (Finding 17). programmable_logic_base requires it on a
  /// `SpendViaUnfracking` dispatch. Swappable in place.
  unfracking_cred: Credential,
  /// Field 5 — credential of the upgrade-authority withdraw-0 validator
  /// (trampoline 2). Read ONLY by coordination_spend, on an upgrade
  /// transaction, to decide *who* may rewrite this datum. Making it a datum
  /// field (rather than a coordination_spend parameter) is what lets the
  /// upgrade authority itself be swapped in place — federated multisig now, a
  /// governance-action validator later — without moving the coordination UTxO.
  /// Last of the original six because it is the coldest read.
  upgrade_cred: Credential,
  /// Field 6 — maximum serialised size, in BYTES, of the inline datum a
  /// programmable-token (PLB) output may carry (issue #106, vector 3).
  ///
  /// A seizure must reproduce the paired input's datum byte-for-byte on the
  /// continuing output, so an unbounded datum lets a holder push the seizure
  /// transaction past `maxTxSize` — or, short of that, collapse how many
  /// UTxOs an issuer can seize per transaction. The holder pays nothing for
  /// it: `transfer` never pairs an input to an output, so it never reads the
  /// datum. Bounding it at CREATION is what keeps every PLB UTxO seizable.
  ///
  /// A datum field rather than a compile-time constant so the bound can be
  /// retuned — DeFi order and loan state grows — by rewriting this datum
  /// instead of re-deploying the delegates. It grants the upgrade authority
  /// no new power: it can already swap `transfer_cred` for a validator with
  /// no bound at all, which is strictly more.
  ///
  /// APPENDED LAST on purpose: every pre-existing accessor keeps its current
  /// `tail_list` depth, so adding it costs the hot paths (above all PLB's
  /// per-input credential read) exactly nothing. It is itself read ONCE per
  /// delegate invocation and threaded down to the output walk, never re-read
  /// per output, so its own depth is paid once per transaction.
  max_inline_datum_bytes: Int,
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
/// datum, and protocol_params_mint fully deserialises (and thereby
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
  // (protocol_params_mint mints exactly one `ProtocolParams` token), so any
  // UTxO bearing it is the genuine params UTxO. A wrong index fails here
  // rather than silently reading some other UTxO's datum. Kept as a bare
  // policy-presence test (not the stricter name+quantity check) because this
  // runs on the hot path — per delegate withdrawal and per PLB input.
  expect
    !dict.is_empty(
      value.tokens(protocol_params_ref.output.value, protocol_params_cs),
    )

  expect InlineDatum(inline_datum) = protocol_params_ref.output.datum
  return(unconstr_fields(inline_datum))
}

/// Field 0: currency symbol of the registry node NFTs.
pub fn registry_node_cs_field(fields: List<Data>) -> PolicyId {
  expect registry_node_cs: PolicyId = head_list(fields)
  registry_node_cs
}

/// Field 1: the programmable-logic-base (PLB) payment credential.
pub fn prog_logic_cred_field(fields: List<Data>) -> Credential {
  expect prog_logic_cred: Credential = head_list(tail_list(fields))
  prog_logic_cred
}

/// Field 2: the `transfer` withdraw-0 credential. Read by
/// programmable_logic_base on a `SpendViaTransfer` dispatch.
pub fn transfer_cred_field(fields: List<Data>) -> Credential {
  expect transfer_cred: Credential = head_list(tail_list(tail_list(fields)))
  transfer_cred
}

/// Field 3: the standalone third-party-transfer withdraw-0 credential.
/// Read by programmable_logic_base on a `SpendViaThirdParty` dispatch.
pub fn third_party_cred_field(fields: List<Data>) -> Credential {
  expect third_party_cred: Credential = head_list(
    tail_list(tail_list(tail_list(fields))),
  )
  third_party_cred
}

/// Field 4: the `unfracking` withdraw-0 credential (Finding 17). Read by
/// programmable_logic_base on a `SpendViaUnfracking` dispatch.
pub fn unfracking_cred_field(fields: List<Data>) -> Credential {
  expect unfracking_cred: Credential = head_list(
    tail_list(tail_list(tail_list(tail_list(fields)))),
  )
  unfracking_cred
}

// No accessor for field 5 (`upgrade_cred`): its only reader,
// coordination_spend, deserialises the whole record on its cold path.

/// Field 6: the maximum serialised inline-datum size a PLB output may carry.
/// Read ONCE per delegate invocation (transfer / third_party / unfracking /
/// issuance_mint) and threaded down to the output walk.
pub fn max_inline_datum_bytes_field(fields: List<Data>) -> Int {
  expect max_inline_datum_bytes: Int = head_list(
    tail_list(tail_list(tail_list(tail_list(tail_list(tail_list(fields)))))),
  )
  max_inline_datum_bytes
}
