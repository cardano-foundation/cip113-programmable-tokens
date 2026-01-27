/**
 * Compliance API
 * Handles blacklist management and token seizure operations
 */

import { apiPost } from './client';
import type {
  BlacklistInitRequest,
  BlacklistInitResponse,
  AddToBlacklistRequest,
  RemoveFromBlacklistRequest,
  BlacklistOperationResponse,
  SeizeTokensRequest,
  SeizeTokensResponse,
} from '@/types/compliance';

// Re-export types
export type {
  BlacklistInitRequest,
  BlacklistInitResponse,
  AddToBlacklistRequest,
  RemoveFromBlacklistRequest,
  BlacklistOperationResponse,
  SeizeTokensRequest,
  SeizeTokensResponse,
};

/**
 * Initialize a new blacklist for a token
 * Creates the blacklist node on-chain
 *
 * @param request - Blacklist initialization parameters
 * @param protocolTxHash - Optional protocol version transaction hash
 * @returns Promise with blacklist node policy ID and unsigned transaction
 */
export async function initBlacklist(
  request: BlacklistInitRequest,
  protocolTxHash?: string
): Promise<BlacklistInitResponse> {
  const endpoint = protocolTxHash
    ? `/compliance/blacklist/init?protocolTxHash=${protocolTxHash}`
    : '/compliance/blacklist/init';

  return apiPost<BlacklistInitRequest, BlacklistInitResponse>(
    endpoint,
    request,
    { timeout: 60000 }
  );
}

/**
 * Add an address to the blacklist
 * The address will be frozen and unable to transfer tokens
 *
 * @param request - Add to blacklist parameters
 * @param protocolTxHash - Optional protocol version transaction hash
 * @returns Promise<string> - Unsigned transaction CBOR hex
 */
export async function addToBlacklist(
  request: AddToBlacklistRequest,
  protocolTxHash?: string
): Promise<BlacklistOperationResponse> {
  const endpoint = protocolTxHash
    ? `/compliance/blacklist/add?protocolTxHash=${protocolTxHash}`
    : '/compliance/blacklist/add';

  return apiPost<AddToBlacklistRequest, BlacklistOperationResponse>(
    endpoint,
    request,
    { timeout: 60000 }
  );
}

/**
 * Remove an address from the blacklist
 * The address will be unfrozen and able to transfer tokens again
 *
 * @param request - Remove from blacklist parameters
 * @param protocolTxHash - Optional protocol version transaction hash
 * @returns Promise<string> - Unsigned transaction CBOR hex
 */
export async function removeFromBlacklist(
  request: RemoveFromBlacklistRequest,
  protocolTxHash?: string
): Promise<BlacklistOperationResponse> {
  const endpoint = protocolTxHash
    ? `/compliance/blacklist/remove?protocolTxHash=${protocolTxHash}`
    : '/compliance/blacklist/remove';

  return apiPost<RemoveFromBlacklistRequest, BlacklistOperationResponse>(
    endpoint,
    request,
    { timeout: 60000 }
  );
}

/**
 * Seize tokens from a blacklisted address
 * Transfers tokens from a target UTxO to the specified recipient
 *
 * @param request - Seize tokens parameters
 * @param protocolTxHash - Optional protocol version transaction hash
 * @returns Promise<string> - Unsigned transaction CBOR hex
 */
export async function seizeTokens(
  request: SeizeTokensRequest,
  protocolTxHash?: string
): Promise<SeizeTokensResponse> {
  const endpoint = protocolTxHash
    ? `/compliance/seize?protocolTxHash=${protocolTxHash}`
    : '/compliance/seize';

  return apiPost<SeizeTokensRequest, SeizeTokensResponse>(
    endpoint,
    request,
    { timeout: 60000 }
  );
}

/**
 * Check if an address is blacklisted for a given token
 *
 * @param tokenPolicyId - Policy ID of the token
 * @param address - Address to check
 * @param protocolTxHash - Optional protocol version transaction hash
 * @returns Promise<boolean> - Whether the address is blacklisted
 */
export async function isAddressBlacklisted(
  tokenPolicyId: string,
  address: string,
  protocolTxHash?: string
): Promise<boolean> {
  // This would typically be a GET endpoint
  // For now, we'll assume it returns a boolean
  const endpoint = protocolTxHash
    ? `/compliance/blacklist/check?policyId=${tokenPolicyId}&address=${address}&protocolTxHash=${protocolTxHash}`
    : `/compliance/blacklist/check?policyId=${tokenPolicyId}&address=${address}`;

  try {
    const response = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8080'}/api/v1${endpoint}`);
    if (!response.ok) {
      return false;
    }
    const result = await response.json();
    return result.blacklisted === true;
  } catch {
    // If check fails, assume not blacklisted
    return false;
  }
}
