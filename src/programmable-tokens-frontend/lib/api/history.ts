/**
 * Transaction History API
 */

import { TransactionHistoryResponse } from '@/types/api';
import { apiGet } from './client';

export interface GetHistoryParams {
  stakeKeyHash: string;
  protocolTxHash?: string;
  limit?: number;
}

/**
 * Fetch transaction history by stake key hash
 * Optionally filter by protocol version (protocolTxHash)
 *
 * @param params - Query parameters
 * @returns List of transaction history entries
 */
export async function getTransactionHistory(
  params: GetHistoryParams
): Promise<TransactionHistoryResponse> {
  const { stakeKeyHash, protocolTxHash, limit = 10 } = params;

  // Build query string
  const queryParams = new URLSearchParams({
    limit: limit.toString(),
  });

  if (protocolTxHash) {
    queryParams.append('protocolTxHash', protocolTxHash);
  }

  const endpoint = `/history/by-stake/${stakeKeyHash}?${queryParams.toString()}`;

  return apiGet<TransactionHistoryResponse>(endpoint);
}
