/**
 * Form validation utilities for CIP-113 frontend
 */

/**
 * Validate token name (max 32 bytes UTF-8)
 */
export function validateTokenName(name: string): { valid: boolean; error?: string } {
  if (!name || !name.trim()) {
    return { valid: false, error: 'Token name is required' };
  }

  const byteLength = new TextEncoder().encode(name).length;
  if (byteLength > 32) {
    return { valid: false, error: `Token name must be 32 bytes or less (currently ${byteLength} bytes)` };
  }

  // Check for invalid characters (only alphanumeric and basic symbols allowed)
  // Cardano asset names can contain any bytes, but for UX we restrict to printable chars
  const printableRegex = /^[\x20-\x7E\u00A0-\uFFFF]*$/;
  if (!printableRegex.test(name)) {
    return { valid: false, error: 'Token name contains invalid characters' };
  }

  return { valid: true };
}

/**
 * Validate minting quantity
 */
export function validateQuantity(quantity: string): { valid: boolean; error?: string } {
  if (!quantity || !quantity.trim()) {
    return { valid: false, error: 'Quantity is required' };
  }

  // Must be positive integer
  if (!/^\d+$/.test(quantity)) {
    return { valid: false, error: 'Quantity must be a positive whole number' };
  }

  const value = BigInt(quantity);
  if (value <= BigInt(0)) {
    return { valid: false, error: 'Quantity must be greater than 0' };
  }

  // Max is 2^63 - 1 (Cardano Int64 limit)
  const maxQuantity = BigInt('9223372036854775807');
  if (value > maxQuantity) {
    return { valid: false, error: 'Quantity exceeds maximum allowed value' };
  }

  return { valid: true };
}

/**
 * Validate Cardano address format (bech32)
 */
export function validateCardanoAddress(address: string): { valid: boolean; error?: string } {
  // Empty is allowed (will use issuer address)
  if (!address || !address.trim()) {
    return { valid: true };
  }

  const trimmed = address.trim();

  // Basic bech32 format check
  // Mainnet addresses start with 'addr1'
  // Testnet addresses start with 'addr_test1'
  const mainnetPrefix = 'addr1';
  const testnetPrefix = 'addr_test1';

  if (!trimmed.startsWith(mainnetPrefix) && !trimmed.startsWith(testnetPrefix)) {
    return { valid: false, error: 'Address must start with addr1 (mainnet) or addr_test1 (testnet)' };
  }

  // Check length bounds (mainnet 98-103 chars, testnet 108-113 chars)
  if (trimmed.startsWith(testnetPrefix)) {
    if (trimmed.length < 98 || trimmed.length > 130) {
      return { valid: false, error: 'Invalid testnet address length' };
    }
  } else {
    if (trimmed.length < 58 || trimmed.length > 103) {
      return { valid: false, error: 'Invalid mainnet address length' };
    }
  }

  // For testnet, extract the part after 'addr_test1' to check characters
  // For mainnet, extract the part after 'addr1'
  const prefixLength = trimmed.startsWith(testnetPrefix) ? testnetPrefix.length : mainnetPrefix.length;
  const addressBody = trimmed.slice(prefixLength);

  // Check for valid bech32 characters (excluding 1, b, i, o which are invalid in bech32)
  const bech32Regex = /^[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+$/;
  if (!bech32Regex.test(addressBody)) {
    return { valid: false, error: 'Address contains invalid characters' };
  }

  return { valid: true };
}

/**
 * Validate hex string format
 */
export function validateHexString(hex: string): { valid: boolean; error?: string } {
  if (!hex) {
    return { valid: false, error: 'Hex string is required' };
  }

  // Remove 0x prefix if present
  const cleaned = hex.startsWith('0x') ? hex.slice(2) : hex;

  // Must be even length
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

/**
 * Calculate UTF-8 byte length of a string
 */
export function getByteLength(str: string): number {
  return new TextEncoder().encode(str).length;
}
