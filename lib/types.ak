// Core data types for CIP-113 programmable tokens
// Migrated from SmartTokens.Types.PTokenDirectory and SmartTokens.Types.ProtocolParams

use cardano/address.{Credential}

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
/// ordinary programmable-token transfer is dispatched to by
/// programmable_logic_base under `SpendViaTransfer`.
///
/// `params_idx` is the index of the protocol-params NFT UTxO in
/// `reference_inputs`. The validator jumps straight to that reference input
/// (`list.at`) and authenticates it by the one-shot params NFT, instead of
/// scanning every reference input to find it — a wrong index simply fails
/// the NFT check. See `params.with_protocol_params_fields`. The standalone
/// `third_party` and `unfracking` validators carry the same field.
pub type TransferRedeemer {
  params_idx: Int,
  /// One registry proof per distinct spent policy, in ascending policy order
  proofs: List<RegistryProof>,
}

/// Redeemer of the standalone `unfracking` withdraw-0 validator (v2).
/// Same index-hint discipline as `ThirdPartyRedeemer`: an unfracking action
/// is single-policy, names its registry node, and pairs every PLB input
/// positionally with a continuing output starting at `outputs_start_idx`.
pub type UnfrackingRedeemer {
  /// Index of the protocol-params NFT UTxO in reference inputs
  params_idx: Int,
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
  /// Index of the protocol-params NFT UTxO in reference inputs
  params_idx: Int,
  /// Index of the subject policy's registry node in reference inputs
  registry_node_idx: Int,
  /// Starting index in outputs where processed outputs begin
  outputs_start_idx: Int,
}

/// Redeemer of the `programmable_logic_base` spend validator.
///
/// PLB runs once per programmable-token input, so its cost is multiplied by
/// every such input in the transaction. It dispatches each spend to ONE of
/// three withdraw-0 validators — `transfer`, `third_party`, `unfracking` — and
/// witnesses WHERE that validator's credential sits
/// in the ledger-ordered withdrawal map (Script credentials first, then
/// VerificationKey, bytewise within each), so the check is a direct
/// `list.expect_at` — O(`wdrl_idx`) cell drops with no comparison on the way —
/// plus one equality, instead of a scan that compares at every entry.
///
/// Self-validating: a wrong `wdrl_idx` resolves to some other credential and a
/// wrong arm names another validator — either way the equality fails, so a
/// dishonest witness can only invalidate its own transaction. Whichever
/// validator it delegates to then enforces its full invariants over the whole
/// transaction, so authorising any one of them is sound. No delegate is ever
/// reached through another: a transfer loads only `transfer`, a seize only
/// `third_party`, an unfracking only `unfracking`.
///
/// ASSUMPTION (documented, not enforced): "a wrong arm fails" holds only while
/// the params datum carries pairwise-distinct `transfer_cred`,
/// `third_party_cred` and `unfracking_cred`. Neither `protocol_params_mint`
/// nor `coordination_spend` checks distinctness; it is the deployer's and the
/// upgrade authority's responsibility. With two equal credentials both arms
/// resolve to the same script, which must then dispatch internally — see
/// `plb_equal_delegate_creds_collapse_the_arms`.
pub type BaseSpendRedeemer {
  /// Delegate to the `transfer` validator. PLB requires the `transfer_cred`
  /// (params datum field 2) at `wdrl_idx`.
  SpendViaTransfer { params_idx: Int, wdrl_idx: Int }
  /// Delegate to the `third_party` (seize / clawback / freeze-enforcement)
  /// validator. PLB requires the `third_party_cred` (params datum field 3)
  /// at `wdrl_idx`.
  SpendViaThirdParty { params_idx: Int, wdrl_idx: Int }
  /// Delegate to the `unfracking` validator (Finding 17, holder-driven
  /// same-owner PLB restructuring). PLB requires the `unfracking_cred`
  /// (params datum field 4) at `wdrl_idx`.
  SpendViaUnfracking { params_idx: Int, wdrl_idx: Int }
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
/// by the cryptographic binding in `registry_mint`, so collision-resistance
/// of blake2b_224 forces credential agreement without a runtime equality
/// check on the redeemer.
pub type MintingRegistryProof {
  RefInput { index: Int }
  OutputIndex { index: Int }
}

/// Redeemer for registry minting policy (linked list operations)
pub type RegistryRedeemer {
  /// Initialize the registry with the origin node
  RegistryInit
  /// Insert a new programmable token policy into the registry.
  ///
  /// `minting_logic_script` is the credential of the substandard's
  /// withdraw-0 minting logic. registry_mint enforces that:
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
  /// policy is NOT constrained by registry_mint: a first mint in the
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
