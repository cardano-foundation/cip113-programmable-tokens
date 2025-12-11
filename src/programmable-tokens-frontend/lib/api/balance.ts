/**
 * Balance API Module
 *
 * This module provides functions for fetching and parsing programmable token
 * balances from the CIP-0113 backend. It handles the complexity of aggregating
 * balances across multiple programmable addresses and converting between
 * on-chain formats and UI-friendly representations.
 *
 * ## Programmable Token Addresses
 *
 * In CIP-0113, tokens are held at "programmable addresses" that combine:
 * - Payment credential: The protocol's programmable_logic_base script
 * - Stake credential: The user's verification key
 *
 * A single user may have balances across multiple programmable addresses
 * (one per protocol version). This module aggregates them into a single view.
 *
 * ## Balance Format
 *
 * The backend returns balances as JSON strings with the format:
 * ```json
 * {
 *   "lovelace": "1000000",
 *   "abc123...def456": "100"  // policyId+assetName -> amount
 * }
 * ```
 *
 * This module parses these strings and provides typed access to the data.
 *
 * ## Asset Naming
 *
 * Cardano asset names are raw bytes, stored on-chain and in the API as hex.
 * This module provides utilities to decode hex asset names to human-readable
 * UTF-8 strings when possible.
 *
 * @module lib/api/balance
 */

import { apiGet } from './client';
import { WalletBalanceResponse, ParsedBalance, ParsedAsset } from '@/types/api';

/**
 * Get comprehensive wallet balance including all programmable token addresses.
 *
 * This function queries the backend for all balances associated with a wallet
 * address across all protocol versions. The backend:
 * 1. Derives the user's programmable addresses for each protocol version
 * 2. Queries the UTxO set for balances at those addresses
 * 3. Returns aggregated balance information
 *
 * @param address - User's wallet address in bech32 format (addr1... or addr_test1...)
 * @param protocolTxHash - Optional protocol version to filter balances; if omitted,
 *                         returns balances across all versions
 * @returns Promise resolving to WalletBalanceResponse with balance entries
 * @throws {ApiException} If the API request fails
 *
 * @example
 * ```typescript
 * const response = await getWalletBalance('addr_test1qz...');
 * console.log(`Found ${response.balances.length} balance entries`);
 * ```
 */
export async function getWalletBalance(
  address: string,
  protocolTxHash?: string
): Promise<WalletBalanceResponse> {
  const params = protocolTxHash ? `?protocolTxHash=${protocolTxHash}` : '';
  return apiGet<WalletBalanceResponse>(`/balances/wallet-balance/${address}${params}`);
}

/**
 * Parse a balance JSON string from the backend.
 *
 * The backend stores balances as JSON strings in the database. This function
 * safely parses them into a typed object. Invalid JSON returns an empty object.
 *
 * @param balanceJson - JSON string like '{"lovelace":"1000000","unit":"amount"}'
 * @returns Parsed object mapping units to amounts (as strings)
 *
 * @example
 * ```typescript
 * const balance = parseBalance('{"lovelace":"1000000"}');
 * console.log(balance.lovelace); // "1000000"
 * ```
 */
export function parseBalance(balanceJson: string): { [key: string]: string } {
  try {
    return JSON.parse(balanceJson);
  } catch (error) {
    console.error('Failed to parse balance JSON:', balanceJson, error);
    return {};
  }
}

/**
 * Split a Cardano token unit into policy ID and asset name.
 *
 * A token unit is the concatenation of:
 * - Policy ID: 56 hex characters (28 bytes)
 * - Asset name: 0-64 hex characters (0-32 bytes)
 *
 * For the special "lovelace" unit, returns empty strings.
 *
 * @param unit - Concatenated policyId+assetName (hex), or "lovelace"
 * @returns Object with policyId and assetNameHex separated
 *
 * @example
 * ```typescript
 * const { policyId, assetNameHex } = splitUnit('abc123...def4564d79546f6b656e');
 * console.log(policyId);      // 'abc123...def456' (56 chars)
 * console.log(assetNameHex);  // '4d79546f6b656e' (remaining)
 * ```
 */
export function splitUnit(unit: string): { policyId: string; assetNameHex: string } {
  if (unit === 'lovelace') {
    return { policyId: '', assetNameHex: '' };
  }

  const POLICY_ID_LENGTH = 56; // 28 bytes * 2 (hex)

  if (unit.length < POLICY_ID_LENGTH) {
    console.warn('Invalid unit length:', unit);
    return { policyId: unit, assetNameHex: '' };
  }

  return {
    policyId: unit.substring(0, POLICY_ID_LENGTH),
    assetNameHex: unit.substring(POLICY_ID_LENGTH),
  };
}

/**
 * Decode a hex-encoded asset name to a UTF-8 string.
 *
 * Cardano asset names are raw bytes that can contain any data. When the bytes
 * represent valid UTF-8 text (common for user-friendly token names), this
 * function decodes them. Otherwise, it returns the original hex string.
 *
 * @param assetNameHex - Hex-encoded asset name
 * @returns Decoded UTF-8 string, or original hex if decoding fails
 *
 * @example
 * ```typescript
 * decodeAssetName('4d79546f6b656e'); // Returns 'MyToken'
 * decodeAssetName('');               // Returns ''
 * decodeAssetName('00ff');           // Returns '00ff' (invalid UTF-8)
 * ```
 */
export function decodeAssetName(assetNameHex: string): string {
  if (!assetNameHex) {
    return '';
  }

  try {
    // Convert hex to bytes
    const bytes = new Uint8Array(
      assetNameHex.match(/.{1,2}/g)?.map(byte => parseInt(byte, 16)) || []
    );

    // Decode as UTF-8
    const decoder = new TextDecoder('utf-8', { fatal: true });
    return decoder.decode(bytes);
  } catch (error) {
    // Decoding failed, return hex
    console.debug('Failed to decode asset name, using hex:', assetNameHex);
    return assetNameHex;
  }
}

/**
 * Check if a policy ID is registered as a programmable token.
 *
 * **Note**: This is currently a placeholder implementation. The actual check
 * should query the on-chain registry. For now, the backend handles filtering
 * of programmable vs non-programmable tokens when returning balances.
 *
 * @param policyId - The 56-character hex policy ID to check
 * @returns Promise resolving to true if registered (currently always false)
 *
 * @todo Implement actual registry lookup via backend API
 */
export async function isProgrammableToken(policyId: string): Promise<boolean> {
  try {
    // Placeholder: In production, this should query the registry endpoint
    // and check if the policyId exists in the on-chain registry
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8080'}/api/v1/protocol/registry`
    );

    if (!response.ok) {
      return false;
    }

    // Note: Registry check is currently handled by the backend
    // This function returns false to indicate the feature needs full implementation
    return false;
  } catch (error) {
    console.error('Failed to check if token is programmable:', error);
    return false;
  }
}

/**
 * Parse wallet balance response into a UI-friendly format.
 *
 * This function takes the raw API response and:
 * 1. Aggregates lovelace across all balance entries
 * 2. Aggregates tokens by unit (combining amounts across addresses)
 * 3. Decodes asset names from hex to human-readable strings
 * 4. Splits units into policy ID and asset name components
 *
 * All tokens returned from programmable addresses are marked as programmable
 * since they can only exist there if they passed registry validation.
 *
 * @param response - WalletBalanceResponse from the API
 * @returns ParsedBalance with aggregated lovelace and assets array
 *
 * @example
 * ```typescript
 * const response = await getWalletBalance(address);
 * const parsed = await parseWalletBalance(response);
 *
 * console.log(`Total ADA: ${parsed.lovelace}`);
 * parsed.assets.forEach(asset => {
 *   console.log(`${asset.assetName}: ${asset.amount}`);
 * });
 * ```
 */
export async function parseWalletBalance(
  response: WalletBalanceResponse
): Promise<ParsedBalance> {
  let totalLovelace = BigInt(0);
  const assetMap = new Map<string, { unit: string; amount: bigint }>();

  // Aggregate balances from all addresses
  for (const balanceEntry of response.balances) {
    const balance = parseBalance(balanceEntry.balance);

    // Aggregate lovelace
    if (balance.lovelace) {
      totalLovelace += BigInt(balance.lovelace);
    }

    // Aggregate assets
    for (const [unit, amount] of Object.entries(balance)) {
      if (unit === 'lovelace') continue;

      const existing = assetMap.get(unit);
      if (existing) {
        existing.amount += BigInt(amount);
      } else {
        assetMap.set(unit, { unit, amount: BigInt(amount) });
      }
    }
  }

  // Convert to ParsedAsset array
  const assets: ParsedAsset[] = await Promise.all(
    Array.from(assetMap.values()).map(async ({ unit, amount }) => {
      const { policyId, assetNameHex } = splitUnit(unit);
      const assetName = decodeAssetName(assetNameHex);

      // All tokens in programmable token addresses are programmable by definition
      // They can only exist at these addresses if they passed the registry validation
      const isProgrammable = true;

      return {
        unit,
        policyId,
        assetNameHex,
        assetName,
        amount: amount.toString(),
        isProgrammable,
      };
    })
  );

  return {
    lovelace: totalLovelace.toString(),
    assets,
  };
}
