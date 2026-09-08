// Core data types for CIP-113 programmable tokens
// Migrated from SmartTokens.Types.PTokenDirectory and SmartTokens.Types.ProtocolParams

use cardano/address.{Credential}
use cardano/assets.{PolicyId}

/// Token name for the issuance CBOR hex reference NFT
pub const issuance_cbor_hex_token_name = "IssuanceCborHex"

/// Proof that a token is (or is not) in the registry
pub type RegistryProof {
  /// Token exists in the registry at this reference input index
  TokenExists { node_idx: Int }
  /// Token does not exist (proof via covering node at this index)
  TokenDoesNotExist { node_idx: Int }
}

/// Redeemer of the `transfer` withdraw-0 validator — the script every
/// ordinary programmable-token transfer is dispatched to, by
/// `programmable_logic_global` under a `TransferAct` arm.
///
/// This redeemer carries NO `params_idx`: the `transfer` validator no longer
/// reads the protocol-params datum at all. The three values it used to read
/// there — `prog_logic_cred`, `registry_node_cs` and the seizure datum bound —
/// are compile-time parameters of the validator now. Same for the standalone
/// `third_party` and `unfracking` redeemers.
pub type TransferRedeemer {
  /// One registry proof per distinct spent policy, in ascending policy order
  proofs: List<RegistryProof>,
}

/// Redeemer of the standalone `unfracking` withdraw-0 validator (v2).
/// Same index-hint discipline as `ThirdPartyRedeemer`: an unfracking action
/// is single-policy, names its registry node, and pairs every PLB input
/// positionally with a continuing output starting at `outputs_start_idx`.
pub type UnfrackingRedeemer {
  /// Index of the acted-on policy's registry node in reference inputs
  registry_node_idx: Int,
  /// Starting index in outputs where the paired continuing outputs begin
  outputs_start_idx: Int,
}

/// Redeemer of the standalone `third_party` withdraw-0 validator.
/// Same index-hint discipline as `UnfrackingRedeemer`: a third-party
/// (seize / clawback / freeze-enforcement) action names its subject
/// policy's registry node and pairs every acted-on PLB input positionally
/// with a continuing output starting at `outputs_start_idx`. Carries the
/// exact fields the old inline `ThirdPartyAct` arm did — the logic moved
/// out of the former coordinator into its own script, the redeemer surface is unchanged.
pub type ThirdPartyRedeemer {
  /// Index of the subject policy's registry node in reference inputs
  registry_node_idx: Int,
  /// Starting index in outputs where processed outputs begin
  outputs_start_idx: Int,
}

/// Redeemer of the `programmable_logic_base` spend validator.
///
/// PLB runs once per programmable-token input, so its cost is multiplied by
/// every such input in the transaction — which is why it now does the smallest
/// job in the protocol: locate the params datum, read ONE credential
/// (`plg_cred`, field 2), and require that credential's withdraw-0 at the
/// witnessed index. No arm, no `when`, no choice of accessor.
///
/// It witnesses WHERE the dispatcher's credential sits in the ledger-ordered
/// withdrawal map (Script credentials first, then VerificationKey, bytewise
/// within each), so the check is a direct `list.expect_at` — O(`wdrl_idx`) cell
/// drops with no comparison on the way — plus one equality, instead of a scan
/// that compares at every entry.
///
/// Self-validating: a wrong `wdrl_idx` resolves to some other credential and
/// the equality fails, so a dishonest witness can only invalidate its own
/// transaction.
///
/// **The pairwise-distinctness ASSUMPTION is gone.** PLB used to choose between
/// three credentials by redeemer arm, which was only sound while those three
/// were distinct — a property nothing on-chain enforced. There is now exactly
/// one credential on this path, so there is nothing to collide.
pub type BaseSpendRedeemer {
  /// Index of the protocol-params NFT UTxO in `reference_inputs`.
  params_idx: Int,
  /// Index of `plg_cred`'s entry in the ledger-ordered withdrawal map.
  wdrl_idx: Int,
}

/// Redeemer of the `programmable_logic_global` dispatcher.
///
/// PLG is reached from PLB (which named it via `plg_cred`) and does exactly one
/// thing: prove that the delegate for the chosen ACTION was invoked. The three
/// delegate hashes are compile-time parameters of PLG, so it never reads the
/// params datum — the trust chain is PLB -> params -> PLG -> delegate, and PLG
/// is the link that turns "some dispatcher ran" into "the right delegate ran".
///
/// The arms carry NO payload on purpose. Everything a delegate needs — registry
/// proofs, node indices, output offsets — travels in that delegate's OWN
/// redeemer, where the delegate itself validates it. Duplicating any of it here
/// would create a second, unchecked claim about the same fact, and forcing the
/// two to agree would mean PLG decoding the delegate's redeemer — which is
/// exactly the work this design exists to avoid.
pub type ProgrammableLogicGlobalRedeemer {
  /// An ordinary transfer: requires the `transfer` validator's withdraw-0.
  TransferAct
  /// A third-party action (seize / clawback / freeze enforcement): requires
  /// the `third_party` validator's withdraw-0.
  ThirdPartyAct
  /// Holder-driven same-owner restructuring (Finding 17): requires the
  /// `unfracking` validator's withdraw-0.
  UnfrackingAct
}

/// Redeemer of the `protocol_params` SPEND handler — which of the three
/// upgrade-path transaction shapes this is.
///
/// The arms carry NO payload, for the same reason
/// `ProgrammableLogicGlobalRedeemer`'s do not: every value the branch needs is
/// already in the continuing datum, which is validated regardless. A
/// credential repeated here would be a second, unchecked claim about the same
/// fact, and forcing the two to agree costs a comparison that buys nothing.
///
/// The arms exist to make each transaction DECLARE its intent, so that each
/// branch is one closed rule set rather than a disjunction the reader has to
/// solve. Note what that buys beyond legibility: because `ProtocolUpgrade`
/// freezes the nomination and `NominateAuthority` freezes everything else, a
/// nomination can never ride along inside a parameter change. Anyone watching
/// the chain sees an authority handover begin as its own transaction.
///
/// This does NOT reopen audit-3 finding 02 (issue #124), which is about the
/// PLB redeemer carrying action variants: PLB must stay action-agnostic
/// because its hash is baked into every token address, so an action set
/// change there would be a token-address migration. `protocol_params` is the
/// upgrade path itself — replacing it is a redeploy by definition — so there
/// is no such coupling to protect here.
pub type ProtocolParamsRedeemer {
  /// Rewrite mutable protocol wiring. May change `plg_cred`, `transfer_cred`
  /// and `third_party_cred`; may NOT touch `upgrade_cred` or the nomination.
  /// Authorised by the sitting `upgrade_cred`'s withdraw-0.
  ProtocolUpgrade
  /// Phase 1 of a handover: set (or clear) `pending_upgrade_cred` and nothing
  /// else. `Some(c)` nominates or re-nominates, `None` revokes. Authorised by
  /// the sitting `upgrade_cred`'s withdraw-0.
  NominateAuthority
  /// Phase 2 of a handover: the standing nominee becomes `upgrade_cred` and
  /// the nomination clears; nothing else moves. Authorised by the NOMINEE's
  /// own withdraw-0 — the evidence that it exists, runs and consents.
  PromoteAuthority
}

/// Redeemer for the issuance minting policy.
///
/// The redeemer is the registry proof itself — a `RefInput` index for a
/// subsequent mint (registry node already exists), or an `OutputIndex` for
/// the first mint (registry node being created in the same tx).
///
/// The substandard's withdraw-0 invocation (proof of instance) is checked
/// directly against the validator's `minting_logic_cred` parameter — no
/// separate redeemer field needed. The validator parameter is baked into
/// the policy id at compile time and pinned to `registry.minting_logic_script`
/// by the cryptographic binding in the `registry` validator's mint handler,
/// so collision-resistance
/// of blake2b_224 forces credential agreement without a runtime equality
/// check on the redeemer.
pub type MintingRegistryProof {
  RefInput { index: Int }
  OutputIndex { index: Int }
}

/// Redeemer of the PERMANENT issuance policy (`issuance_mint`, issue #129):
/// nothing but an index hint locating the protocol-params UTxO among the
/// reference inputs. Everything that could ever change — registry proofs,
/// custody, delegate redeemer shapes — travels in `IssuanceLogicRedeemer`
/// instead, so this type can stay frozen for as long as any token exists.
pub type IssuanceRedeemer {
  params_idx: Int,
}

/// Redeemer of the REPLACEABLE `issuance_logic` withdraw-0: one registry
/// proof per policy issued (minted or burned) in this transaction, keyed by
/// policy id.
///
/// The keys are the one frozen interface between the two scripts. The
/// permanent policy decodes this value only as far as `Pairs<PolicyId, Data>`
/// and asks whether its own policy is a key; it never looks at a value. So
/// the proof shape may change with the protocol, and the map shape may not.
pub type IssuanceLogicRedeemer =
  Pairs<PolicyId, MintingRegistryProof>

/// Redeemer for registry minting policy (linked list operations)
pub type RegistryRedeemer {
  /// Initialize the registry with the origin node
  RegistryInit
  /// Insert a new programmable token policy into the registry.
  ///
  /// `minting_logic_script` is the credential of the substandard's
  /// withdraw-0 minting logic. The `registry` mint handler enforces that:
  ///   * the new node's datum field `minting_logic_script` equals this
  ///     value (datum-matches-redeemer check, prevents the registrar
  ///     from writing a different credential into the datum than they
  ///     claim in the redeemer);
  ///   * the issuance template parameterised with this credential hashes
  ///     to `key` (cryptographic binding: the `hashed_param` used in the
  ///     policy id derivation is the inner 28-byte hash of this
  ///     credential — derived inside the validator, NOT supplied as a
  ///     separate redeemer field);
  ///   * the substandard's withdraw-0 logic is invoked
  ///     (`minting_logic_script` in `tx.withdrawals`).
  ///
  /// Whether the registration also carries a first mint of the new
  /// policy is NOT constrained by the `registry` mint handler: a first mint in the
  /// same tx is validated by `issuance_mint` as usual, and registering
  /// without any mint is equally valid (useful for real-world-asset
  /// issuance or supply-aware substandards that must initialise global
  /// state before any token exists). A substandard that wants a strict
  /// register-then-mint lifecycle must enforce it in its own minting
  /// logic.
  RegistryInsert { key: ByteArray, minting_logic_script: Credential }
}

/// Issuance CBOR hex reference data
/// This contains the prefix and postfix of the minting policy script
/// Used to validate programmable token registrations
pub type IssuanceCborHex {
  /// Prefix bytes of the minting policy script
  prefix_cbor_hex: ByteArray,
  /// Postfix bytes of the minting policy script
  postfix_cbor_hex: ByteArray,
}
