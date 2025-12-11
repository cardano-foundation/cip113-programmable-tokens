/**
 * Form Validation Utilities for CIP-0113 Frontend
 *
 * This module provides validation functions for user input in the programmable
 * tokens frontend. All validators return a consistent result object with
 * `valid` boolean and optional `error` message.
 *
 * ## Cardano-Specific Constraints
 *
 * - **Asset names**: Maximum 32 bytes (not characters!) in UTF-8 encoding
 * - **Quantities**: Positive integers up to Int64 max (9,223,372,036,854,775,807)
 * - **Addresses**: Bech32 format, prefix 'addr1' (mainnet) or 'addr_test1' (testnet)
 *
 * ## Usage Example
 *
 * ```typescript
 * const nameResult = validateTokenName(userInput);
 * if (!nameResult.valid) {
 *   showError(nameResult.error);
 * }
 * ```
 *
 * @module lib/utils/validation
 */

/**
 * Validation result returned by all validation functions.
 */
export interface ValidationResult {
  /** Whether the input is valid */
  valid: boolean;
  /** Error message if invalid (undefined if valid) */
  error?: string;
}

/**
 * Validate a token name for Cardano asset naming constraints.
 *
 * Cardano asset names are limited to 32 bytes in UTF-8 encoding. Note that
 * multi-byte characters (emojis, accented characters) count as multiple bytes.
 *
 * @param name - The token name to validate
 * @returns Validation result
 *
 * @example
 * ```typescript
 * validateTokenName("MyToken")     // { valid: true }
 * validateTokenName("")            // { valid: false, error: "Token name is required" }
 * validateTokenName("This is a very long token name that exceeds the limit")
 *   // { valid: false, error: "Token name must be 32 bytes or less (currently 52 bytes)" }
 * ```
 */
export function validateTokenName(name: string): ValidationResult {
  if (!name || !name.trim()) {
    return { valid: false, error: 'Token name is required' };
  }

  // Check byte length, not character length!
  // Multi-byte UTF-8 characters (emojis, accented chars) can exceed 32 chars limit
  const byteLength = new TextEncoder().encode(name).length;
  if (byteLength > 32) {
    return { valid: false, error: `Token name must be 32 bytes or less (currently ${byteLength} bytes)` };
  }

  // Check for invalid characters (only printable chars allowed for UX)
  // Cardano technically allows any bytes, but we restrict to printable for usability
  const printableRegex = /^[\x20-\x7E\u00A0-\uFFFF]*$/;
  if (!printableRegex.test(name)) {
    return { valid: false, error: 'Token name contains invalid characters' };
  }

  return { valid: true };
}

/**
 * Validate a minting quantity.
 *
 * Quantities must be positive integers within Cardano's Int64 range.
 *
 * @param quantity - The quantity as a string (to handle large numbers safely)
 * @returns Validation result
 *
 * @example
 * ```typescript
 * validateQuantity("1000")         // { valid: true }
 * validateQuantity("0")            // { valid: false, error: "Quantity must be greater than 0" }
 * validateQuantity("-5")           // { valid: false, error: "Quantity must be a positive whole number" }
 * validateQuantity("1.5")          // { valid: false, error: "Quantity must be a positive whole number" }
 * ```
 */
export function validateQuantity(quantity: string): ValidationResult {
  if (!quantity || !quantity.trim()) {
    return { valid: false, error: 'Quantity is required' };
  }

  // Must be a positive integer (digits only)
  if (!/^\d+$/.test(quantity)) {
    return { valid: false, error: 'Quantity must be a positive whole number' };
  }

  // Use BigInt for safe large number handling
  const value = BigInt(quantity);
  if (value <= BigInt(0)) {
    return { valid: false, error: 'Quantity must be greater than 0' };
  }

  // Cardano Int64 limit
  const maxQuantity = BigInt('9223372036854775807');
  if (value > maxQuantity) {
    return { valid: false, error: 'Quantity exceeds maximum allowed value' };
  }

  return { valid: true };
}

/**
 * Validate a Cardano address in bech32 format.
 *
 * Supports both mainnet (addr1) and testnet (addr_test1) addresses.
 * Empty addresses are allowed (will use the issuer's address).
 *
 * @param address - The address to validate (optional, empty string allowed)
 * @returns Validation result
 *
 * @example
 * ```typescript
 * validateCardanoAddress("")                    // { valid: true } - empty is OK
 * validateCardanoAddress("addr_test1qz...")     // { valid: true }
 * validateCardanoAddress("addr1qy...")          // { valid: true }
 * validateCardanoAddress("invalid")             // { valid: false, error: "Address must start with..." }
 * ```
 */
export function validateCardanoAddress(address: string): ValidationResult {
  // Empty is allowed (will use issuer address as recipient)
  if (!address || !address.trim()) {
    return { valid: true };
  }

  const trimmed = address.trim();

  // Check address prefix
  const mainnetPrefix = 'addr1';
  const testnetPrefix = 'addr_test1';

  if (!trimmed.startsWith(mainnetPrefix) && !trimmed.startsWith(testnetPrefix)) {
    return { valid: false, error: 'Address must start with addr1 (mainnet) or addr_test1 (testnet)' };
  }

  // Validate length bounds
  // Testnet addresses are longer due to the prefix
  if (trimmed.startsWith(testnetPrefix)) {
    if (trimmed.length < 98 || trimmed.length > 130) {
      return { valid: false, error: 'Invalid testnet address length' };
    }
  } else {
    if (trimmed.length < 58 || trimmed.length > 103) {
      return { valid: false, error: 'Invalid mainnet address length' };
    }
  }

  // Validate bech32 character set in the address body
  const prefixLength = trimmed.startsWith(testnetPrefix) ? testnetPrefix.length : mainnetPrefix.length;
  const addressBody = trimmed.slice(prefixLength);

  // Bech32 alphabet excludes: 1, b, i, o (to avoid confusion)
  const bech32Regex = /^[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+$/;
  if (!bech32Regex.test(addressBody)) {
    return { valid: false, error: 'Address contains invalid characters' };
  }

  return { valid: true };
}

// =============================================================================
// Hex String Validation
// =============================================================================

/**
 * Validate a hexadecimal string format.
 *
 * Hex strings must have even length (each byte = 2 hex chars) and contain
 * only valid hex characters (0-9, a-f, A-F).
 *
 * @param hex - The hex string to validate (with or without 0x prefix)
 * @returns Validation result
 *
 * @example
 * ```typescript
 * validateHexString("4d79546f6b656e")      // { valid: true }
 * validateHexString("0x4d79546f6b656e")    // { valid: true }
 * validateHexString("abc")                  // { valid: false, error: "...even length" }
 * validateHexString("xyz123")               // { valid: false, error: "...invalid characters" }
 * ```
 */
export function validateHexString(hex: string): ValidationResult {
  if (!hex) {
    return { valid: false, error: 'Hex string is required' };
  }

  // Remove 0x prefix if present
  const cleaned = hex.startsWith('0x') ? hex.slice(2) : hex;

  // Must be even length (2 hex chars per byte)
  if (cleaned.length % 2 !== 0) {
    return { valid: false, error: 'Hex string must have even length' };
  }

  // Must contain only hex characters
  const hexRegex = /^[0-9a-fA-F]*$/;
  if (!hexRegex.test(cleaned)) {
    return { valid: false, error: 'Hex string contains invalid characters' };
  }

  return { valid: true };
}

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Calculate the UTF-8 byte length of a string.
 *
 * Useful for checking Cardano asset name constraints, which are in bytes
 * not characters. Multi-byte characters (emojis, accented chars) count as
 * multiple bytes.
 *
 * @param str - The string to measure
 * @returns Byte length when encoded as UTF-8
 *
 * @example
 * ```typescript
 * getByteLength("hello")   // 5 (ASCII = 1 byte per char)
 * getByteLength("héllo")   // 6 (é = 2 bytes)
 * getByteLength("👍")      // 4 (emoji = 4 bytes)
 * ```
 */
export function getByteLength(str: string): number {
  return new TextEncoder().encode(str).length;
}
