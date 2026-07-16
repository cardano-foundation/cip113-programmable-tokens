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

/// Redeemer for the global programmable logic stake validator
pub type ProgrammableLogicGlobalRedeemer {
  /// Transfer action with proofs for each token type
  TransferAct { proofs: List<RegistryProof> }
  /// Third party action for administrative / compliance operations —
  /// forced transfer, seizure, freeze enforcement, or burn. Supports multiple
  /// UTxOs of the subject policy in a single transaction.
  ThirdPartyAct {
    /// Index of the registry node in reference inputs
    registry_node_idx: Int,
    /// Starting index in outputs where processed outputs begin
    outputs_start_idx: Int,
  }
  /// Finding 17: Unfracking action — let a holder redistribute the
  /// programmable tokens they already hold across multiple PLB UTxOs
  /// WITHOUT invoking any substandard transfer logic. Used to break
  /// up multi-policy UTxOs into single-policy UTxOs so a freeze on
  /// one policy stops collateral-damaging unrelated policies that
  /// happened to share the same UTxO.
  ///
  /// No payload: the unfracking validator infers everything it needs
  /// from the transaction shape. Caller proves authorisation by
  /// signing for (or invoking the script of) every PLB input being
  /// unfracked; the validator enforces value conservation per policy
  /// at the PLB boundary and refuses to route tokens to any stake
  /// credential the caller did not authorise.
  ///
  /// The invariants do NOT live in programmable_logic_global: under
  /// this redeemer, PLG only requires that the standalone
  /// `unfracking` withdraw-0 validator (whose credential is the
  /// `unfracking_cred` field of the protocol-params datum) is invoked
  /// in the same transaction. This keeps the hot-path PLG reference
  /// script ~600 bytes smaller; only unfracking transactions pay for
  /// the unfracking logic.
  UnfrackingAct
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

/// Selects which registration flow `RegistryInsert` is exercising.
///
/// * `RegisterOnly` — the substandard authorises the registration but no
///   programmable tokens of the new policy are minted. Useful for
///   real-world-asset issuance, supply-aware substandards that need to
///   initialise global state before any token exists, or any scenario
///   where minting cannot happen at registration time.
///
/// * `RegisterAndMint` — registration AND a first mint of the new policy
///   happen in the same transaction. Current behaviour, now explicit.
///
/// In both modes the substandard's `minting_logic_script` MUST appear in
/// `tx.withdrawals` (proof of instance — the substandard authorises the
/// registration). The modes differ only in the `tx.mint` shape:
///   * RegisterOnly  ⇒ no entries under the new policy in `tx.mint`.
///   * RegisterAndMint ⇒ `tx.mint` contains an entry under the new
///     policy. Quantity sign is not checked on-chain: burn-only of a
///     brand-new policy is ledger-impossible (no prior tokens exist
///     before registration), so the first mint is positive by
///     construction.
pub type RegistrationMode {
  RegisterOnly
  RegisterAndMint
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
  ///     (`minting_logic_script` in `tx.withdrawals`) regardless of mode.
  ///
  /// `mode` selects between RegisterOnly (no programmable-token mint
  /// allowed) and RegisterAndMint (registration + first mint, current
  /// behaviour).
  RegistryInsert {
    key: ByteArray,
    minting_logic_script: Credential,
    mode: RegistrationMode,
  }
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
