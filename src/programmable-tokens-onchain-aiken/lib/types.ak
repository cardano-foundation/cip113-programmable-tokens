// Core data types for CIP-0143 programmable tokens
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
  /// Third party action for admin operations (seizure, freeze, etc.)
  /// Supports multiple UTxOs in a single transaction
  ThirdPartyAct {
    /// Index of the registry node in reference inputs
    registry_node_idx: Int,
    /// Starting index in outputs where processed outputs begin
    outputs_start_idx: Int,
    /// Length of input_idxs list (for validation)
    length_inputs: Int,
  }
}

/// Action for the minting policy
pub type SmartTokenMintingAction {
  /// The credential of the minting logic script that must be invoked
  minting_logic_cred: Credential,
  /// Minting Registry Proofs
  minting_registry_proof: MintingRegistryProof,
}

pub type MintingRegistryProof {
  RefInput { index: Int }
  OutputIndex { index: Int }
}

/// Redeemer for registry minting policy (linked list operations)
pub type RegistryRedeemer {
  /// Initialize the registry with the origin node
  RegistryInit
  /// Insert a new programmable token policy into the registry
  RegistryInsert { key: ByteArray, hashed_param: ByteArray }
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
