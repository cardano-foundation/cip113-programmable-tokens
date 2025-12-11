/**
 * Token Registration API Module
 *
 * This module provides functions for registering new programmable token policies
 * via the CIP-0113 backend API. Registration is the first step in the token
 * lifecycle - it creates an on-chain registry entry that associates a policy ID
 * with its transfer logic validators.
 *
 * ## Registration vs Minting
 *
 * - **Registration**: Creates a new policy in the registry (one-time per policy)
 * - **Minting**: Creates tokens under a registered policy (can be done multiple times)
 *
 * For simple use cases, registration and initial minting can be combined in a
 * single transaction by providing a non-zero quantity.
 *
 * ## Validator Triple
 *
 * During registration, you select three validators that define token behavior:
 * - **Issue logic**: Controls who can mint (e.g., only the owner)
 * - **Transfer logic**: Controls transfer conditions (e.g., permissioned, free)
 * - **Third-party logic**: Optional hook for external validation (e.g., blacklist)
 *
 * @module lib/api/registration
 */

import { RegisterTokenRequest, RegisterTokenResponse } from '@/types/api';
import { apiPost } from './client';

/**
 * Register a new programmable token policy in the on-chain registry.
 *
 * This function sends a registration request to the backend, which constructs
 * an unsigned transaction that:
 * 1. Mints a registry NFT with the new policy ID
 * 2. Creates a registry node with the validator triple
 * 3. Inserts the node into the sorted linked list
 * 4. Optionally mints initial tokens (if quantity > 0)
 *
 * The returned unsigned transaction must be signed with the user's wallet
 * and submitted to the network.
 *
 * @param request - The registration request containing:
 *   - registrarAddress: The registering wallet's address
 *   - substandardName: ID of the substandard (e.g., "dummy", "permissioned")
 *   - substandardIssueContractName: Name of the issue logic validator
 *   - substandardTransferContractName: Name of the transfer logic validator
 *   - substandardThirdPartyContractName: Optional third-party validator
 *   - assetName: Token name as hex (use stringToHex from minting.ts)
 *   - quantity: Initial tokens to mint (can be "0" for registration-only)
 *   - recipientAddress: Optional recipient for initial tokens
 *
 * @param protocolTxHash - Optional protocol version to use; defaults to latest
 *
 * @returns Promise resolving to the registration response containing:
 *   - unsignedTx: The unsigned transaction CBOR hex
 *   - policyId: The new token's policy ID
 *
 * @throws {ApiException} If registration fails (invalid request, network error)
 *
 * @example
 * ```typescript
 * import { registerToken } from '@/lib/api/registration';
 * import { stringToHex } from '@/lib/api/minting';
 *
 * const response = await registerToken({
 *   registrarAddress: wallet.address,
 *   substandardName: 'permissioned',
 *   substandardIssueContractName: 'issuance_logic',
 *   substandardTransferContractName: 'permissioned_transfer',
 *   assetName: stringToHex('MyToken'),
 *   quantity: '1000000'
 * });
 *
 * const signedTx = await wallet.signTx(response.unsignedTx);
 * const txHash = await wallet.submitTx(signedTx);
 * console.log(`Registered policy ${response.policyId} in tx ${txHash}`);
 * ```
 */
export async function registerToken(
  request: RegisterTokenRequest,
  protocolTxHash?: string
): Promise<RegisterTokenResponse> {
  const endpoint = protocolTxHash
    ? `/issue-token/register?protocolTxHash=${protocolTxHash}`
    : '/issue-token/register';

  return apiPost<RegisterTokenRequest, RegisterTokenResponse>(
    endpoint,
    request,
    { timeout: 60000 } // 60 seconds for registration transaction
  );
}
