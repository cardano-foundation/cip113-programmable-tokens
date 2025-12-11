/**
 * Token Transfer API Module
 *
 * This module provides functions for transferring programmable tokens via the
 * CIP-0113 backend API. Unlike standard Cardano token transfers, programmable
 * transfers are validated by on-chain smart contracts that enforce the token's
 * registered transfer logic.
 *
 * ## Transfer Architecture
 *
 * Programmable tokens use a two-level validation system:
 *
 * 1. **programmable_logic_base** (spend validator): Guards all programmable
 *    token UTxOs. Simply checks that the global stake validator is invoked.
 *
 * 2. **programmable_logic_global** (stake validator): Performs the actual
 *    validation by looking up the token in the registry and invoking its
 *    registered transfer logic.
 *
 * ## Programmable Addresses
 *
 * Programmable tokens must be held at special "programmable addresses" that
 * combine:
 * - Payment credential: The protocol's programmable_logic_base script
 * - Stake credential: The user's key (for authorization)
 *
 * The backend automatically handles address conversion - you provide regular
 * bech32 addresses and it derives the programmable addresses.
 *
 * ## Token Unit Format
 *
 * Cardano tokens are identified by their "unit" - the concatenation of:
 * - Policy ID: 56 hex characters (28 bytes)
 * - Asset name: 0-64 hex characters (0-32 bytes)
 *
 * Example: `abc123...def456` (policy) + `4d79546f6b656e` (hex for "MyToken")
 *
 * @module lib/api/transfer
 */

import { TransferTokenRequest, TransferTokenResponse } from '@/types/api';
import { apiPost } from './client';

/**
 * Transfer programmable tokens from sender to recipient.
 *
 * This function sends a transfer request to the backend, which constructs
 * an unsigned transaction that:
 * 1. Spends the sender's programmable UTxO containing the tokens
 * 2. Creates a new programmable UTxO for the recipient
 * 3. Returns change to the sender's programmable address
 * 4. Invokes the global programmable logic stake validator
 * 5. Invokes the token's registered transfer logic validator
 *
 * The transaction enforces all transfer rules defined by the token's
 * registered transfer logic contract. For example:
 * - Permissioned tokens may require issuer signature
 * - Blacklistable tokens reject transfers to/from blacklisted addresses
 *
 * @param request - The transfer request containing:
 *   - senderAddress: The sender's base address (bech32)
 *   - unit: The token unit (policyId + assetName as hex)
 *   - quantity: Number of tokens to transfer
 *   - recipientAddress: The recipient's base address (bech32)
 *
 * @param protocolTxHash - Optional protocol version to use; defaults to latest
 *
 * @returns Promise resolving to the transfer response containing:
 *   - unsignedTx: The unsigned transaction CBOR hex
 *
 * @throws {ApiException} If transfer fails (insufficient balance, not registered,
 *   transfer logic rejection, blacklisted address)
 *
 * @example
 * ```typescript
 * import { transferToken } from '@/lib/api/transfer';
 *
 * // Transfer 100 tokens
 * const response = await transferToken({
 *   senderAddress: 'addr_test1qz...',
 *   unit: 'abc123...def4564d79546f6b656e', // policyId + assetName
 *   quantity: '100',
 *   recipientAddress: 'addr_test1qx...'
 * });
 *
 * // Sign and submit
 * const signedTx = await wallet.signTx(response.unsignedTx);
 * const txHash = await wallet.submitTx(signedTx);
 * ```
 */
export async function transferToken(
  request: TransferTokenRequest,
  protocolTxHash?: string
): Promise<TransferTokenResponse> {
  const endpoint = protocolTxHash
    ? `/transfer-token/transfer?protocolTxHash=${protocolTxHash}`
    : '/transfer-token/transfer';

  return apiPost<TransferTokenRequest, TransferTokenResponse>(
    endpoint,
    request,
    { timeout: 60000 } // 60 seconds for transfer transaction
  );
}
