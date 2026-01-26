/**
 * Admin Tokens API
 *
 * Currently uses mock data. Will be replaced with real API when backend is ready:
 * GET /api/v1/admin/tokens/{pkh}
 */

import {
  AdminTokensResponse,
  AdminTokenInfo,
  AdminRole,
  getMockAdminTokens,
  getTokensByRole,
  hasAdminRoles,
} from "@/lib/mocks/admin-tokens";

// Re-export types
export type { AdminTokensResponse, AdminTokenInfo, AdminRole };

/**
 * Get all tokens where the given PKH has admin roles
 *
 * @param pkh - Payment key hash of the admin
 * @returns Promise<AdminTokensResponse>
 */
export async function getAdminTokens(pkh: string): Promise<AdminTokensResponse> {
  // TODO: Replace with real API call when backend is ready
  // const endpoint = `/admin/tokens/${pkh}`;
  // return apiGet<AdminTokensResponse>(endpoint);

  // For now, use mock data
  return Promise.resolve(getMockAdminTokens(pkh));
}

/**
 * Check if a PKH has any admin roles
 *
 * @param pkh - Payment key hash to check
 * @returns Promise<boolean>
 */
export async function checkHasAdminRoles(pkh: string): Promise<boolean> {
  // TODO: Could be a separate lightweight endpoint
  return Promise.resolve(hasAdminRoles(pkh));
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
  return Promise.resolve(getTokensByRole(pkh, role));
}

/**
 * Extract payment key hash from a Cardano address
 * This is a simplified version - in production use proper address parsing
 */
export function extractPkhFromAddress(address: string): string | null {
  // For bech32 addresses, the PKH is embedded in the address
  // This is a placeholder - the real implementation would use
  // @meshsdk/core or cardano-serialization-lib to properly parse

  // Simple validation
  if (!address.startsWith("addr")) {
    return null;
  }

  // In production, use proper address deserialization
  // For now, we'll use a mock extraction
  // The real PKH would be 28 bytes (56 hex chars)

  // Return a mock PKH for development
  // In reality, this would deserialize the address and extract the payment credential
  return "mockedpkh" + address.substring(5, 20);
}
