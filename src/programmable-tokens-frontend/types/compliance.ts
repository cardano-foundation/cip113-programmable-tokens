/**
 * Compliance API Types
 * Types for blacklist management and token seizure operations
 */

// ============================================================================
// Blacklist Initialization
// ============================================================================

export interface BlacklistInitRequest {
  substandardId: string;         // Substandard ID (e.g., 'freeze-and-seize')
  adminAddress: string;          // Admin address that will manage this blacklist
  feePayerAddress: string;       // Address that pays for the transaction
}

export interface BlacklistInitResponse {
  policyId: string;              // Policy ID of the blacklist node (from backend)
  unsignedCborTx: string;        // Unsigned transaction CBOR hex
}

// ============================================================================
// Blacklist Add/Remove
// ============================================================================

export interface AddToBlacklistRequest {
  adminAddress: string;          // Blacklist admin's wallet address
  tokenPolicyId: string;         // Policy ID of the token
  targetAddress: string;         // Address to blacklist
}

export interface RemoveFromBlacklistRequest {
  adminAddress: string;          // Blacklist admin's wallet address
  tokenPolicyId: string;         // Policy ID of the token
  targetAddress: string;         // Address to un-blacklist
}

// Backend returns plain text CBOR hex string
export type BlacklistOperationResponse = string;

// ============================================================================
// Token Seizure
// ============================================================================

export interface SeizeTokensRequest {
  adminAddress: string;          // Issuer admin's wallet address
  tokenPolicyId: string;         // Policy ID of the token
  targetTxHash: string;          // Transaction hash containing the UTxO
  targetOutputIndex: number;     // Output index within the transaction
  recipientAddress: string;      // Address to receive seized tokens
}

// Backend returns plain text CBOR hex string
export type SeizeTokensResponse = string;

// ============================================================================
// Shared Types
// ============================================================================

export interface ComplianceOperationResult {
  success: boolean;
  txHash?: string;
  error?: string;
}
