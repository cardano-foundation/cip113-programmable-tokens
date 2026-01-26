/**
 * API Types for CIP-113 Backend Integration
 */

// ============================================================================
// Substandards
// ============================================================================

export interface SubstandardValidator {
  title: string;
  script_bytes: string;
  script_hash: string;
}

export interface Substandard {
  id: string;
  validators: SubstandardValidator[];
}

export type SubstandardsResponse = Substandard[];

// ============================================================================
// Token Registration
// ============================================================================

/** Base type for all registration requests */
export interface BaseRegisterTokenRequest {
  substandardId: string;       // Discriminator - backend knows which contracts to use
  feePayerAddress: string;     // User's wallet address (renamed from registrarAddress)
  assetName: string;           // HEX ENCODED token name
  quantity: string;            // Amount to register/mint
  recipientAddress: string;    // Recipient address (can be empty string)
}

/** Dummy substandard - no extra fields needed */
export interface DummyRegisterRequest extends BaseRegisterTokenRequest {
  substandardId: 'dummy';
}

/** Freeze-and-seize substandard - requires blacklist info */
export interface FreezeAndSeizeRegisterRequest extends BaseRegisterTokenRequest {
  substandardId: 'freeze-and-seize';
  adminPubKeyHash: string;         // Payment key hash derived from feePayerAddress
  blacklistNodePolicyId: string;   // From blacklist initialization step
}

/** Discriminated union of all registration request types */
export type RegisterTokenRequest = DummyRegisterRequest | FreezeAndSeizeRegisterRequest;

export interface RegisterTokenResponse {
  policyId: string;              // Generated policy ID
  unsignedCborTx: string;        // Unsigned transaction CBOR hex
}

// ============================================================================
// Minting (Admin - mint to existing registered token)
// ============================================================================

export interface MintTokenRequest {
  feePayerAddress: string;      // Issuer admin's wallet address
  tokenPolicyId: string;        // Policy ID of registered token
  assetName: string;            // HEX ENCODED token name
  quantity: string;             // Amount as string to handle large numbers
  recipientAddress: string;     // Recipient address
}

// Backend returns plain text CBOR hex string (not JSON)
export type MintTokenResponse = string;

export interface MintFormData {
  tokenName: string;           // Human-readable name (will be hex encoded)
  quantity: string;            // Amount to mint
  policyId: string;            // Policy ID of registered token
  recipientAddress: string;    // Recipient address
}

// ============================================================================
// Legacy Minting (for registration flow - deprecated)
// ============================================================================

export interface LegacyMintTokenRequest {
  issuerBaseAddress: string;
  substandardName: string;
  substandardIssueContractName: string;
  recipientAddress?: string;
  assetName: string;      // HEX ENCODED token name
  quantity: string;       // Amount as string to handle large numbers
}

export interface LegacyMintFormData {
  tokenName: string;           // Human-readable name (will be hex encoded)
  quantity: string;            // Amount to mint
  substandardId: string;       // Substandard ID (e.g., "dummy")
  validatorTitle: string;      // Validator contract name
  recipientAddress?: string;   // Optional recipient (defaults to issuer)
}

// ============================================================================
// Protocol Blueprint
// ============================================================================

export interface ProtocolBlueprint {
  validators: Array<{
    title: string;
    redeemer: unknown;
    datum: unknown;
    compiledCode: string;
    hash: string;
  }>;
  preamble: {
    title: string;
    description: string;
    version: string;
  };
}

// ============================================================================
// Protocol Version
// ============================================================================

export interface ProtocolVersionInfo {
  registryNodePolicyId: string;
  progLogicScriptHash: string;
  txHash: string;
  slot: number;
  timestamp: number; // Unix timestamp in seconds (convert to ms for JS Date)
  default: boolean; // Jackson serializes isDefault as "default"
}

// ============================================================================
// Token Transfer
// ============================================================================

export interface TransferTokenRequest {
  senderAddress: string;      // Sender's wallet address
  unit: string;               // Full unit (policyId + assetName hex)
  quantity: string;           // Amount to transfer
  recipientAddress: string;   // Recipient's address
}

// Backend returns plain text CBOR hex string (not JSON)
export type TransferTokenResponse = string;

// ============================================================================
// Balance
// ============================================================================

export interface BalanceLogEntity {
  id: number;
  address: string;
  paymentScriptHash: string;
  stakeKeyHash: string | null;
  txHash: string;
  slot: number;
  blockHeight: number;
  balance: string; // JSON string: {"lovelace": "1000000", "unit": "amount"}
  createdAt: string;
}

export interface WalletBalanceResponse {
  walletAddress: string;
  paymentHash: string;
  stakeHash: string | null;
  balances: BalanceLogEntity[];
}

// Parsed balance entry for UI
export interface ParsedBalance {
  lovelace: string;
  assets: ParsedAsset[];
}

export interface ParsedAsset {
  unit: string;           // Full unit (policyId + assetName hex)
  policyId: string;       // Policy ID (56 chars)
  assetNameHex: string;   // Asset name in hex
  assetName: string;      // Decoded asset name (UTF-8, or hex if decode fails)
  amount: string;         // Amount as string
  isProgrammable: boolean; // Whether this is a registered programmable token
}

// ============================================================================
// Transaction History
// ============================================================================

export type TransactionType = 'MINT' | 'BURN' | 'TRANSFER' | 'REGISTER' | null;

export interface TransactionHistoryEntry {
  txHash: string;
  address: string;
  slot: number;
  timestamp: number; // Unix timestamp in seconds
  transactionType: TransactionType;
  balanceDiff: Record<string, string>; // unit -> signed amount (e.g., "+1000", "-50")
}

export type TransactionHistoryResponse = TransactionHistoryEntry[];

// ============================================================================
// API Error
// ============================================================================

export interface ApiError {
  message: string;
  status?: number;
  details?: unknown;
}

export class ApiException extends Error {
  constructor(
    message: string,
    public status?: number,
    public details?: unknown
  ) {
    super(message);
    this.name = 'ApiException';
  }
}
