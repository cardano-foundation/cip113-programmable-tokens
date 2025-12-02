/**
 * API Types for CIP-0113 Backend Integration
 *
 * This module defines TypeScript interfaces for the CIP-0113 backend API.
 * These types ensure type safety when communicating with the Java backend
 * and help catch integration errors at compile time.
 *
 * @module types/api
 */

// =============================================================================
// Substandards
// =============================================================================

/**
 * A validator within a substandard.
 *
 * Represents a single compiled Plutus script from an Aiken blueprint.
 * Used for transfer logic, issuance logic, or other custom validators.
 *
 * @example
 * ```typescript
 * const validator: SubstandardValidator = {
 *   title: "transfer_logic.transfer_logic.withdraw",
 *   script_bytes: "59010f010000...",
 *   script_hash: "abc123def456..."
 * };
 * ```
 */
export interface SubstandardValidator {
  /**
   * The full title of the validator from the Aiken blueprint.
   * Format: `module.validator.purpose` (e.g., "transfer_logic.transfer_logic.withdraw")
   */
  title: string;

  /**
   * The compiled CBOR hex of the Plutus script.
   * This is the actual script bytes that will be used on-chain.
   */
  script_bytes: string;

  /**
   * The Blake2b-224 hash of the script (28 bytes hex = 56 characters).
   * This is the script credential/policy ID.
   */
  script_hash: string;
}

/**
 * A substandard definition containing multiple validators.
 *
 * Substandards are pre-built collections of validators that implement
 * specific token behavior patterns (e.g., freeze-and-seize, whitelisting).
 *
 * @example
 * ```typescript
 * const substandard: Substandard = {
 *   id: "dummy",
 *   validators: [
 *     { title: "issuance_logic...", script_bytes: "...", script_hash: "..." },
 *     { title: "transfer_logic...", script_bytes: "...", script_hash: "..." }
 *   ]
 * };
 * ```
 */
export interface Substandard {
  /**
   * Unique identifier for the substandard.
   * Corresponds to the folder name in the backend's substandards directory.
   */
  id: string;

  /**
   * List of validators included in this substandard.
   * Typically includes at least issuance and transfer logic validators.
   */
  validators: SubstandardValidator[];
}

/**
 * Response type for the GET /api/v1/substandards endpoint.
 * Returns an array of all available substandards.
 */
export type SubstandardsResponse = Substandard[];

// =============================================================================
// Minting
// =============================================================================

/**
 * Request body for the POST /api/v1/issue-token/mint endpoint.
 *
 * This request triggers the creation of an unsigned minting transaction
 * that the client must sign and submit.
 *
 * @example
 * ```typescript
 * const request: MintTokenRequest = {
 *   issuerBaseAddress: "addr_test1qz...",
 *   substandardName: "dummy",
 *   substandardIssueContractName: "issuance_logic",
 *   assetName: "4d79546f6b656e", // "MyToken" in hex
 *   quantity: "1000000"
 * };
 * ```
 */
export interface MintTokenRequest {
  /**
   * The issuer's base address in bech32 format.
   * This address will be used as the source of funds for transaction fees
   * and as the default recipient if recipientAddress is not specified.
   */
  issuerBaseAddress: string;

  /**
   * The substandard ID to use for minting.
   * Must match a substandard loaded by the backend (e.g., "dummy").
   */
  substandardName: string;

  /**
   * The name of the issuance contract within the substandard.
   * Uses partial matching (e.g., "issuance_logic" matches "issuance_logic.issuance_logic.withdraw").
   */
  substandardIssueContractName: string;

  /**
   * Optional recipient address for the minted tokens.
   * If not provided, tokens are sent to the issuer address.
   */
  recipientAddress?: string;

  /**
   * The asset name in HEX encoding.
   * Maximum 32 bytes (64 hex characters).
   * Use `stringToHex()` from lib/api/minting.ts to encode.
   */
  assetName: string;

  /**
   * The quantity to mint as a decimal string.
   * Using string to handle large numbers (BigInt) safely in JSON.
   * Maximum: 9,223,372,036,854,775,807 (Int64 max)
   */
  quantity: string;
}

/**
 * Response type for minting endpoints.
 *
 * The backend returns the unsigned transaction as plain text CBOR hex,
 * not as JSON. This type alias documents this behavior.
 */
export type MintTokenResponse = string;

/**
 * Form data structure for the minting UI.
 *
 * This is the user-facing data structure before conversion to API format.
 * Note that tokenName is human-readable (will be hex encoded before API call).
 */
export interface MintFormData {
  /**
   * Human-readable token name.
   * Will be converted to hex encoding before sending to the API.
   * Maximum 32 bytes in UTF-8 encoding.
   */
  tokenName: string;

  /**
   * Amount to mint as a string.
   * Must be a positive integer.
   */
  quantity: string;

  /**
   * Selected substandard ID (e.g., "dummy").
   */
  substandardId: string;

  /**
   * Selected validator contract name within the substandard.
   */
  validatorTitle: string;

  /**
   * Optional recipient address.
   * If empty, tokens go to the issuer's address.
   */
  recipientAddress?: string;
}

// =============================================================================
// Protocol Blueprint
// =============================================================================

/**
 * Protocol blueprint structure returned by GET /api/v1/protocol/blueprint.
 *
 * This is the Aiken plutus.json format containing all compiled validators
 * for the CIP-0113 protocol core.
 */
export interface ProtocolBlueprint {
  /**
   * Array of all validators in the protocol.
   */
  validators: Array<{
    /** Validator title (e.g., "programmable_logic_global.programmable_logic_global.withdraw") */
    title: string;
    /** Redeemer schema (JSON) */
    redeemer: unknown;
    /** Datum schema (JSON) */
    datum: unknown;
    /** Compiled CBOR hex of the validator */
    compiledCode: string;
    /** Blake2b-224 hash of the script */
    hash: string;
  }>;

  /**
   * Blueprint preamble with metadata.
   */
  preamble: {
    /** Human-readable title */
    title: string;
    /** Description of the protocol */
    description: string;
    /** Semantic version */
    version: string;
  };
}

// =============================================================================
// API Error Handling
// =============================================================================

/**
 * Structure for API error responses.
 *
 * Used for consistent error handling across the frontend.
 */
export interface ApiError {
  /** Human-readable error message */
  message: string;
  /** HTTP status code (if applicable) */
  status?: number;
  /** Additional error details */
  details?: unknown;
}

/**
 * Custom exception class for API errors.
 *
 * Extends Error to include HTTP status code and additional details.
 * Used by the API client to wrap fetch errors.
 *
 * @example
 * ```typescript
 * try {
 *   const result = await apiGet('/endpoint');
 * } catch (error) {
 *   if (error instanceof ApiException) {
 *     console.log(`HTTP ${error.status}: ${error.message}`);
 *   }
 * }
 * ```
 */
export class ApiException extends Error {
  /**
   * Create a new ApiException.
   *
   * @param message - Human-readable error message
   * @param status - HTTP status code (optional)
   * @param details - Additional error details (optional)
   */
  constructor(
    message: string,
    public status?: number,
    public details?: unknown
  ) {
    super(message);
    this.name = 'ApiException';
  }
}
