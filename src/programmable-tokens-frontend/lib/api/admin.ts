/**
 * Admin Tokens API
 *
 * Fetches tokens where the connected wallet has admin roles:
 * GET /api/v1/admin/tokens/{pkh}
 */

import { apiGet } from './client';

// ============================================================================
// Types
// ============================================================================

export type AdminRole = "ISSUER_ADMIN" | "BLACKLIST_MANAGER";

export interface AdminTokenInfo {
  policyId: string;
  assetName: string;          // Hex encoded
  assetNameDisplay: string;   // Human readable
  substandardId: string;
  roles: AdminRole[];
  details: {
    blacklistNodePolicyId?: string;
    issuerAdminPkh?: string;
    blacklistAdminPkh?: string;
  };
}

export interface AdminTokensResponse {
  adminPkh: string;
  tokens: AdminTokenInfo[];
}

// ============================================================================
// API Functions
// ============================================================================

/**
 * Get all tokens where the given PKH has admin roles
 *
 * @param pkh - Payment key hash of the admin
 * @returns Promise<AdminTokensResponse>
 */
export async function getAdminTokens(pkh: string): Promise<AdminTokensResponse> {
  const endpoint = `/admin/tokens/${pkh}`;
  return apiGet<AdminTokensResponse>(endpoint);
}

/**
 * Check if a PKH has any admin roles
 *
 * @param pkh - Payment key hash to check
 * @returns Promise<boolean>
 */
export async function checkHasAdminRoles(pkh: string): Promise<boolean> {
  try {
    const response = await getAdminTokens(pkh);
    return response.tokens.length > 0;
  } catch {
    return false;
  }
}

/**
 * Get tokens where PKH has a specific role
 *
 * @param pkh - Payment key hash of the admin
 * @param role - Role to filter by
 * @returns Promise<AdminTokenInfo[]>
 */
export async function getTokensWithRole(
  pkh: string,
  role: AdminRole
): Promise<AdminTokenInfo[]> {
  const response = await getAdminTokens(pkh);
  return response.tokens.filter((token) => token.roles.includes(role));
}

/**
 * Extract payment key hash from a Cardano address
 * Uses MeshSDK's deserializeAddress for proper parsing
 */
export async function extractPkhFromAddress(address: string): Promise<string | null> {
  // Simple validation
  if (!address.startsWith("addr")) {
    return null;
  }

  try {
    // Dynamic import to avoid WASM issues during SSR
    const { deserializeAddress } = await import('@meshsdk/core');
    const deserialized = deserializeAddress(address);
    return deserialized.pubKeyHash || null;
  } catch (error) {
    console.error("Failed to deserialize address:", error);
    return null;
  }
}
