/**
 * Balance API Client
 * Handles fetching programmable token balances
 */

import { apiGet } from './client';
import { WalletBalanceResponse, ParsedBalance, ParsedAsset } from '@/types/api';

/**
 * Get comprehensive wallet balance including all programmable token addresses
 *
 * @param address - User's wallet address (bech32)
 * @param protocolTxHash - Optional protocol version tx hash to filter balances
 * @returns WalletBalanceResponse with merged balances from all programmable token addresses
 */
export async function getWalletBalance(
  address: string,
  protocolTxHash?: string
): Promise<WalletBalanceResponse> {
  const params = protocolTxHash ? `?protocolTxHash=${protocolTxHash}` : '';
  return apiGet<WalletBalanceResponse>(`/balances/wallet-balance/${address}${params}`);
}

/**
 * Parse a balance JSON string from BalanceLogEntity
 *
 * @param balanceJson - JSON string like '{"lovelace":"1000000","unit":"amount"}'
 * @returns Parsed object with lovelace and assets separated
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
 * Split a unit string into policy ID and asset name
 * Policy ID is always 56 characters (28 bytes hex)
 *
 * @param unit - Concatenated policyId+assetName (hex)
 * @returns Object with policyId and assetNameHex
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
 * Decode hex-encoded asset name to UTF-8 string
 * Falls back to hex string if decoding fails
 *
 * @param assetNameHex - Hex-encoded asset name
 * @returns Decoded string or original hex if decode fails
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
 * Check if a policy ID is registered as a programmable token
 * Currently makes API call to check registry (could be optimized with caching)
 *
 * @param policyId - Policy ID to check
 * @returns Promise<boolean> - true if registered
 */
export async function isProgrammableToken(policyId: string): Promise<boolean> {
  try {
    // Use the /programmable-only endpoint as a proxy to check if token is registered
    // TODO: Could be optimized with a dedicated /registry/check/{policyId} endpoint
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8080'}/api/v1/protocol/registry`
    );

    if (!response.ok) {
      return false;
    }

    const registry = await response.json();

    // Check if policyId exists in registry
    // Registry structure depends on backend implementation
    // For now, return false and let backend handle filtering
    return false; // TODO: Implement proper registry check
  } catch (error) {
    console.error('Failed to check if token is programmable:', error);
    return false;
  }
}

/**
 * Parse wallet balance response into UI-friendly format
 * Aggregates balances across multiple programmable token addresses
 *
 * @param response - WalletBalanceResponse from API
 * @returns ParsedBalance with aggregated lovelace and assets
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

      // For now, assume all tokens in programmable token addresses are programmable
      // TODO: Call isProgrammableToken(policyId) for accurate check
      const isProgrammable = true;

      // Get blacklist status from backend response
      const isBlacklisted = response.blacklistStatuses?.[unit] ?? false;

      return {
        unit,
        policyId,
        assetNameHex,
        assetName,
        amount: amount.toString(),
        isProgrammable,
        isBlacklisted,
      };
    })
  );

  return {
    lovelace: totalLovelace.toString(),
    assets,
  };
}
