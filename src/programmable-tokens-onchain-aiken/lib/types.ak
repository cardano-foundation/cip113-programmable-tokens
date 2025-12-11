// =============================================================================
// CIP-0113 Core Data Types
// =============================================================================
//
// This module defines the core data structures used by CIP-0113 programmable
// tokens. These types are shared across all validators in the protocol.
//
// ## Protocol Overview
//
// CIP-0113 enables programmable tokens on Cardano with enforced transfer logic.
// The protocol uses:
// - A **registry** (sorted linked list) of registered programmable token policies
// - A **blacklist** (sorted linked list) for freeze/seize functionality
// - **Protocol parameters** stored on-chain for global configuration
//
// ## Migration Notes
//
// These types were migrated from the Plutarch implementation:
// - SmartTokens.Types.PTokenDirectory
// - SmartTokens.Types.ProtocolParams
//
// =============================================================================

use cardano/address.{Credential, VerificationKey}
use cardano/assets.{PolicyId}

// =============================================================================
// Constants
// =============================================================================

/// Token name for the origin (sentinel) node in sorted linked lists.
/// The origin node has an empty key and serves as the list head.
/// It points to the first actual entry (or to the max sentinel if empty).
pub const origin_node_tn = #""

/// Token name for the Protocol Parameters NFT.
/// This NFT holds the global configuration for the CIP-0113 protocol.
/// Only one such NFT exists per protocol deployment.
pub const protocol_params_token = "ProtocolParams"

/// Empty verification key credential used for uninitialized or placeholder values.
/// Used in origin nodes where no actual script credential is needed.
pub const empty_vkey = VerificationKey(#"")

/// Token name for the Issuance CBOR Hex reference NFT.
/// This NFT contains the prefix and postfix bytes of the issuance minting policy,
/// allowing the registry to verify that new token policies are properly parametrized.
pub const issuance_cbor_hex_token_name = "IssuanceCborHex"

// =============================================================================
// Registry Data Types
// =============================================================================

/// A node in the programmable token registry linked list.
///
/// The registry is a sorted linked list where each node represents a registered
/// programmable token policy. Nodes are ordered lexicographically by their `key`
/// (the policy's currency symbol).
///
/// ## Linked List Structure
///
/// ```text
/// [Origin] -> [Policy A] -> [Policy B] -> ... -> [Max Sentinel]
///    key=""      key=csA       key=csB           key=0xff...ff
/// ```
///
/// ## Invariants
///
/// 1. `key < next` - Keys are strictly ordered
/// 2. Each node has exactly one NFT with token name = key
/// 3. The origin node has key="" and empty credentials
/// 4. The max sentinel has next=0xff...ff (54 bytes of 0xff)
///
/// ## Example
///
/// ```aiken
/// let node = RegistryNode {
///   key: policy_id,
///   next: next_policy_id,
///   transfer_logic_script: Script(transfer_script_hash),
///   third_party_transfer_logic_script: Script(admin_script_hash),
///   global_state_cs: optional_state_nft_cs,
/// }
/// ```
pub type RegistryNode {
  /// The key (currency symbol/policy ID) of this programmable token policy.
  /// This is a 28-byte Blake2b-224 hash of the minting policy script.
  key: ByteArray,
  /// The next key in lexicographical order for linked list traversal.
  /// Points to the next registered policy, or to 0xff...ff for the last node.
  next: ByteArray,
  /// The credential of the transfer logic script that validates token transfers.
  /// This script is invoked (via withdrawal) for every transfer of tokens with this policy.
  transfer_logic_script: Credential,
  /// The credential of the third-party transfer logic script for admin actions.
  /// This script handles seizure, freeze, and other administrative operations.
  third_party_transfer_logic_script: Credential,
  /// Optional currency symbol for a global state NFT associated with this policy.
  /// Can be empty (28 zero bytes) if no global state is used, or a valid policy ID
  /// for policies that need shared mutable state.
  global_state_cs: ByteArray,
}

// =============================================================================
// Blacklist Data Types
// =============================================================================

/// A node in the blacklist linked list for freeze/seize functionality.
///
/// The blacklist is a sorted linked list where each node represents a blacklisted
/// (sanctioned) address. When an address is blacklisted, transfers from that
/// address are blocked, and administrators can seize tokens.
///
/// ## Structure
///
/// Similar to RegistryNode, but simpler - only contains the address hash and
/// pointer to the next entry. No additional credentials are needed since the
/// blacklist is a simple set membership structure.
///
/// ## Invariants
///
/// 1. `key < next` - Keys are strictly ordered
/// 2. Key is typically a 28-byte credential hash (PubKeyHash or ScriptHash)
/// 3. Same origin/sentinel structure as RegistryNode
pub type BlacklistNode {
  /// The key (credential hash) of the blacklisted address.
  /// This is the payment credential hash of the sanctioned address.
  key: ByteArray,
  /// The next key in lexicographical order for linked list traversal.
  next: ByteArray,
}

// =============================================================================
// Protocol Parameters
// =============================================================================

/// Global protocol parameters stored on-chain as an NFT datum.
///
/// This structure contains the essential configuration for the CIP-0113 protocol.
/// It is stored as an inline datum on a UTxO holding the Protocol Parameters NFT,
/// and is referenced by all programmable token transactions.
///
/// ## Usage
///
/// Transactions include the protocol params UTxO as a reference input to:
/// 1. Locate the registry (via `registry_node_cs`)
/// 2. Verify the programmable logic address (via `prog_logic_cred`)
///
/// ## Deployment
///
/// The protocol params NFT is minted once during protocol deployment and
/// should never be updated (immutable configuration).
pub type ProgrammableLogicGlobalParams {
  /// Currency symbol of the registry node NFTs.
  /// All registry entries must hold an NFT from this policy.
  registry_node_cs: PolicyId,
  /// The programmable logic base credential.
  /// This is the payment credential for all programmable token UTxOs.
  /// All tokens locked at this script address are subject to CIP-0113 rules.
  prog_logic_cred: Credential,
}

// =============================================================================
// Proof Types
// =============================================================================

/// Proof that a token policy is (or is not) in the programmable token registry.
///
/// When transferring tokens, each currency symbol in the transaction needs a
/// proof to determine if it's a programmable token that requires transfer logic
/// validation. These proofs reference registry nodes by their index in the
/// transaction's reference inputs.
///
/// ## Usage in TransferAct
///
/// For each currency symbol in the transaction value:
/// - `TokenExists`: The token IS registered, invoke its transfer logic
/// - `TokenDoesNotExist`: The token is NOT registered, skip validation
///
/// ## Proof Verification
///
/// - `TokenExists`: Registry node's key must equal the currency symbol
/// - `TokenDoesNotExist`: Registry node must "cover" the currency symbol
///   (node.key < cs < node.next), proving no entry exists for this cs
pub type RegistryProof {
  /// Token exists in the registry at this reference input index.
  /// The validator will look up the registry node and invoke its transfer_logic_script.
  TokenExists { node_idx: Int }
  /// Token does not exist (proof via covering node at this index).
  /// The validator verifies the covering node spans this currency symbol.
  TokenDoesNotExist { node_idx: Int }
}

/// Proof of blacklist non-membership for freeze/seize validation.
///
/// When processing a transfer, the transfer logic can verify that an address
/// is NOT on the blacklist by providing a covering node proof.
pub type BlacklistProof {
  /// Proof of non-membership via covering node.
  /// The covering node at this index proves the address is not blacklisted.
  NonmembershipProof { node_idx: Int }
}

// =============================================================================
// Redeemer Types
// =============================================================================

/// Redeemer for the global programmable logic stake validator.
///
/// The global validator coordinates all programmable token operations. It uses
/// the "withdraw-zero" pattern where the stake script is invoked via a zero-value
/// withdrawal, allowing it to observe and validate the entire transaction.
///
/// ## Actions
///
/// ### TransferAct
/// Standard token transfer where users send tokens to each other. Each token
/// type requires a proof (TokenExists/TokenDoesNotExist) and the corresponding
/// transfer logic script must be invoked.
///
/// ### ThirdPartyAct
/// Administrative operations like seizure or freeze. A third party (e.g., issuer
/// or regulator) can invoke the third_party_transfer_logic_script to perform
/// actions on tokens without owner consent.
pub type ProgrammableLogicGlobalRedeemer {
  /// Transfer action with proofs for each token type.
  /// The proofs list must match the order of currency symbols in the transaction value.
  TransferAct { proofs: List<RegistryProof> }
  /// Third party action for admin operations (seizure, freeze, etc.).
  /// Supports processing multiple UTxOs in a single transaction for efficiency.
  ThirdPartyAct {
    /// Index of the registry node in reference inputs.
    /// This node identifies which programmable token policy is being acted upon.
    registry_node_idx: Int,
    /// List of input indices to process (supports multi-UTxO operations).
    /// Each index points to an input from the programmable logic address.
    input_idxs: List<Int>,
    /// Starting index in outputs where processed outputs begin.
    /// For each input at input_idxs[i], output is at outputs_start_idx + i.
    outputs_start_idx: Int,
    /// Length of input_idxs list for validation.
    /// Prevents malicious actors from claiming more inputs than provided.
    length_input_idxs: Int,
  }
}

/// Action for the issuance minting policy.
///
/// When minting new programmable tokens, this redeemer specifies which minting
/// logic script must be invoked to authorize the mint.
pub type SmartTokenMintingAction {
  /// The credential of the minting logic script that must be invoked.
  /// This script contains the business logic for minting (e.g., one-shot, redeemable).
  minting_logic_cred: Credential,
}

// =============================================================================
// Registry Operations
// =============================================================================

/// Redeemer for the registry minting policy (linked list operations).
///
/// The registry minting policy controls the creation and modification of
/// registry entries. Each operation maintains the sorted linked list invariants.
pub type RegistryRedeemer {
  /// Initialize the registry with the origin (sentinel) node.
  /// This must be the first operation and creates the empty list structure.
  /// Mints exactly one NFT with token name "" (empty).
  RegistryInit
  /// Insert a new programmable token policy into the registry.
  /// The key is the policy's currency symbol, and hashed_param is used
  /// to verify the policy was created with the correct issuance template.
  RegistryInsert { key: ByteArray, hashed_param: ByteArray }
}

// =============================================================================
// Blacklist Operations
// =============================================================================

/// Redeemer for the blacklist minting policy (linked list operations).
///
/// The blacklist minting policy controls adding and removing addresses from
/// the blacklist. Similar to the registry, it maintains sorted linked list invariants.
pub type BlacklistRedeemer {
  /// Initialize the blacklist with the origin (sentinel) node.
  /// Creates the empty blacklist structure.
  BlacklistInit
  /// Insert a credential (address) into the blacklist.
  /// The key is typically a 28-byte payment credential hash.
  BlacklistInsert { key: ByteArray }
  /// Remove a credential from the blacklist.
  /// Allows previously blacklisted addresses to transfer tokens again.
  BlacklistRemove { key: ByteArray }
}

// =============================================================================
// Issuance Configuration
// =============================================================================

/// Issuance CBOR hex reference data stored on-chain.
///
/// This structure contains the prefix and postfix of the parametrized minting
/// policy script. When registering a new programmable token, the registry
/// validator uses these bytes to reconstruct and verify the policy ID.
///
/// ## How It Works
///
/// A parametrized minting policy has structure:
/// `version_header + prefix + serialized_param + postfix`
///
/// By storing prefix and postfix on-chain, the registry can:
/// 1. Accept the hashed_param from the registrant
/// 2. Reconstruct the full script bytes
/// 3. Hash to get the expected policy ID
/// 4. Verify it matches the currency symbol being registered
///
/// This ensures only properly-formed minting policies can be registered.
pub type IssuanceCborHex {
  /// Prefix bytes of the minting policy script (before the parameter).
  prefix_cbor_hex: ByteArray,
  /// Postfix bytes of the minting policy script (after the parameter).
  postfix_cbor_hex: ByteArray,
}
