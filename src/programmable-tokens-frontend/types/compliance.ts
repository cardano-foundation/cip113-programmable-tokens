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
  tokenPolicyId: string;         // Policy ID of the token
  targetAddress: string;         // Address to blacklist
  feePayerAddress: string;       // Address that pays for the transaction
}

export interface RemoveFromBlacklistRequest {
  tokenPolicyId: string;         // Policy ID of the token
  targetAddress: string;         // Address to un-blacklist
  feePayerAddress: string;       // Address that pays for the transaction
}

// Backend returns TransactionContext as JSON
export interface TransactionContextResponse<T = unknown> {
  unsignedCborTx: string;
  metadata: T | null;
  isSuccessful: boolean;
  error: string | null;
}

export type BlacklistOperationResponse = TransactionContextResponse<void>;

// ============================================================================
// Token Seizure
// ============================================================================

export interface SeizeTokensRequest {
  feePayerAddress: string;       // Address that pays for the transaction
  unit: string;                  // Policy ID + asset name (format: policyId.assetName)
  utxoTxHash: string;            // Transaction hash containing the UTxO
  utxoOutputIndex: number;       // Output index within the transaction
  destinationAddress: string;    // Address to receive seized tokens
}

export type SeizeTokensResponse = TransactionContextResponse<void>;

// ============================================================================
// Shared Types
// ============================================================================

export interface ComplianceOperationResult {
  success: boolean;
  txHash?: string;
  error?: string;
}
