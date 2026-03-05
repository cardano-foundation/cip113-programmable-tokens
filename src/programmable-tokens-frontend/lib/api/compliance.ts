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
  AddToWhitelistRequest,
  RemoveFromWhitelistRequest,
  WhitelistOperationResponse,
  GovernanceInitRequest,
  GovernanceInitResponse,
  GovernanceAddRequest,
  GovernanceRemoveRequest,
  GovernanceOperationResponse,
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
  AddToWhitelistRequest,
  RemoveFromWhitelistRequest,
  WhitelistOperationResponse,
  GovernanceInitRequest,
  GovernanceInitResponse,
  GovernanceAddRequest,
  GovernanceRemoveRequest,
  GovernanceOperationResponse,
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

// ============================================================================
// Whitelist Operations
// ============================================================================

/**
 * Add an address to the whitelist (KYC approval)
 */
export async function addToWhitelist(
  request: AddToWhitelistRequest,
  protocolTxHash?: string
): Promise<WhitelistOperationResponse> {
  const endpoint = protocolTxHash
    ? `/compliance/whitelist/add?protocolTxHash=${protocolTxHash}`
    : '/compliance/whitelist/add';

  return apiPost<AddToWhitelistRequest, WhitelistOperationResponse>(
    endpoint,
    request,
    { timeout: 60000 }
  );
}

/**
 * Remove an address from the whitelist (revoke KYC approval)
 */
export async function removeFromWhitelist(
  request: RemoveFromWhitelistRequest,
  protocolTxHash?: string
): Promise<WhitelistOperationResponse> {
  const endpoint = protocolTxHash
    ? `/compliance/whitelist/remove?protocolTxHash=${protocolTxHash}`
    : '/compliance/whitelist/remove';

  return apiPost<RemoveFromWhitelistRequest, WhitelistOperationResponse>(
    endpoint,
    request,
    { timeout: 60000 }
  );
}

// ============================================================================
// Governance Operations
// ============================================================================

/**
 * Initialize governance for a whitelist-multiadmin token.
 * Creates manager_signatures, manager_list, and whitelist linked lists.
 */
export async function initGovernance(
  request: GovernanceInitRequest,
  substandardId: string = 'whitelist-send-receive-multiadmin',
  protocolTxHash?: string
): Promise<GovernanceInitResponse> {
  const params = new URLSearchParams({ substandardId });
  if (protocolTxHash) params.set('protocolTxHash', protocolTxHash);

  return apiPost<GovernanceInitRequest, GovernanceInitResponse>(
    `/compliance/governance/init?${params.toString()}`,
    request,
    { timeout: 90000 }
  );
}

/**
 * Add a manager credential to the governance list
 */
export async function addAdmin(
  request: GovernanceAddRequest,
  protocolTxHash?: string
): Promise<GovernanceOperationResponse> {
  const endpoint = protocolTxHash
    ? `/compliance/governance/add?protocolTxHash=${protocolTxHash}`
    : '/compliance/governance/add';

  return apiPost<GovernanceAddRequest, GovernanceOperationResponse>(
    endpoint,
    request,
    { timeout: 60000 }
  );
}

/**
 * Remove a manager credential from the governance list
 */
export async function removeAdmin(
  request: GovernanceRemoveRequest,
  protocolTxHash?: string
): Promise<GovernanceOperationResponse> {
  const endpoint = protocolTxHash
    ? `/compliance/governance/remove?protocolTxHash=${protocolTxHash}`
    : '/compliance/governance/remove';

  return apiPost<GovernanceRemoveRequest, GovernanceOperationResponse>(
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
