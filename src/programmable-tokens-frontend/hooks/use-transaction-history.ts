"use client";

import { useState, useEffect } from 'react';
import { TransactionHistoryResponse } from '@/types/api';
import { getTransactionHistory, GetHistoryParams } from '@/lib/api';

export function useTransactionHistory(stakeKeyHash: string | null, protocolTxHash?: string, limit?: number) {
  const [history, setHistory] = useState<TransactionHistoryResponse>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Don't fetch if no stake key hash
    if (!stakeKeyHash) {
      setHistory([]);
      setIsLoading(false);
      return;
    }

    async function fetchHistory() {
      try {
        setIsLoading(true);
        setError(null);

        const params: GetHistoryParams = {
          stakeKeyHash: stakeKeyHash!,
          protocolTxHash,
          limit,
        };

        const data = await getTransactionHistory(params);
        setHistory(data);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load transaction history');
        setHistory([]);
      } finally {
        setIsLoading(false);
      }
    }

    fetchHistory();
  }, [stakeKeyHash, protocolTxHash, limit]);

  return {
    history,
    isLoading,
    error,
    refetch: () => {
      if (!stakeKeyHash) return Promise.resolve();

      setIsLoading(true);
      return getTransactionHistory({
        stakeKeyHash,
        protocolTxHash,
        limit,
      })
        .then(setHistory)
        .catch(err => setError(err.message))
        .finally(() => setIsLoading(false));
    },
  };
}
