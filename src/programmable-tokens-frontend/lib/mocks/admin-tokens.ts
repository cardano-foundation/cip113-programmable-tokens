/**
 * Mock Admin Tokens Data
 *
 * This will be replaced by a real API endpoint:
 * GET /api/v1/admin/tokens/{pkh}
 */

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

/**
 * Mock admin tokens for development
 * In production, this will be fetched from the backend
 */
export function getMockAdminTokens(pkh: string): AdminTokensResponse {
  // For development, return mock data
  // The real API will look up tokens where this PKH is an admin

  // Example mock data - in reality this would come from the database
  const mockTokens: AdminTokenInfo[] = [
    {
      policyId: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
      assetName: "4d79546f6b656e", // "MyToken" in hex
      assetNameDisplay: "MyToken",
      substandardId: "freeze-and-seize",
      roles: ["ISSUER_ADMIN", "BLACKLIST_MANAGER"],
      details: {
        blacklistNodePolicyId: "f1e2d3c4b5a6f1e2d3c4b5a6f1e2d3c4b5a6f1e2d3c4b5a6f1e2d3c4",
        issuerAdminPkh: pkh,
        blacklistAdminPkh: pkh,
      },
    },
  ];

  return {
    adminPkh: pkh,
    tokens: mockTokens,
  };
}

/**
 * Check if a PKH has any admin roles
 */
export function hasAdminRoles(pkh: string): boolean {
  const response = getMockAdminTokens(pkh);
  return response.tokens.length > 0;
}

/**
 * Get tokens where PKH has a specific role
 */
export function getTokensByRole(pkh: string, role: AdminRole): AdminTokenInfo[] {
  const response = getMockAdminTokens(pkh);
  return response.tokens.filter((token) => token.roles.includes(role));
}
