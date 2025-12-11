/**
 * React Hook for Substandard Validators
 *
 * This hook provides access to the available CIP-0113 substandard validators
 * from the backend. Substandards define different programmable token behaviors
 * such as:
 *
 * - **Whitelist**: Only pre-approved addresses can receive tokens
 * - **Blacklist**: Certain addresses are blocked from receiving tokens
 * - **Transfer Limits**: Maximum transfer amounts per transaction/period
 * - **KYC Required**: Transfers require identity verification
 *
 * ## Usage
 *
 * ```typescript
 * function SubstandardSelector() {
 *   const { substandards, isLoading, error, refetch } = useSubstandards();
 *
 *   if (isLoading) return <Spinner />;
 *   if (error) return <ErrorMessage>{error}</ErrorMessage>;
 *
 *   return (
 *     <select>
 *       {substandards.map(s => (
 *         <option key={s.id} value={s.id}>{s.name}</option>
 *       ))}
 *     </select>
 *   );
 * }
 * ```
 *
 * ## State Management
 *
 * The hook manages three pieces of state:
 * - `substandards`: Array of available substandard configurations
 * - `isLoading`: Boolean indicating if data is being fetched
 * - `error`: Error message if fetch failed, null otherwise
 *
 * @module hooks/use-substandards
 */

"use client";

import { useState, useEffect } from 'react';
import { Substandard } from '@/types/api';
import { getSubstandards } from '@/lib/api';

// ============================================================================
// Hook Return Type
// ============================================================================

/**
 * Return type for the useSubstandards hook.
 */
interface UseSubstandardsResult {
  /** Available substandard validators */
  substandards: Substandard[];
  /** Whether data is currently being fetched */
  isLoading: boolean;
  /** Error message if fetch failed, null otherwise */
  error: string | null;
  /** Function to manually refresh the substandards list */
  refetch: () => Promise<void>;
}

// ============================================================================
// Hook Implementation
// ============================================================================

/**
 * Hook for fetching and managing substandard validator data.
 *
 * Automatically fetches substandards on mount and provides a refetch
 * function for manual refresh. The hook handles all loading and error
 * states internally.
 *
 * @returns Object containing substandards array, loading state, error, and refetch function
 *
 * @example
 * ```typescript
 * const { substandards, isLoading, error, refetch } = useSubstandards();
 *
 * // Handle button click to refresh data
 * const handleRefresh = async () => {
 *   await refetch();
 *   toast.success('Substandards refreshed');
 * };
 * ```
 */
export function useSubstandards(): UseSubstandardsResult {
  // State for storing fetched substandards
  const [substandards, setSubstandards] = useState<Substandard[]>([]);
  // Loading state - starts true for initial fetch
  const [isLoading, setIsLoading] = useState(true);
  // Error state - null when no error
  const [error, setError] = useState<string | null>(null);

  // Fetch substandards on component mount
  useEffect(() => {
    /**
     * Internal async function to fetch substandards.
     * Separated from useEffect to handle async properly.
     */
    async function fetchSubstandards() {
      try {
        setIsLoading(true);
        setError(null);
        const data = await getSubstandards();
        setSubstandards(data);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load substandards');
      } finally {
        setIsLoading(false);
      }
    }

    fetchSubstandards();
  }, []);

  /**
   * Manual refetch function.
   * Useful for refresh buttons or after data mutations.
   */
  const refetch = async (): Promise<void> => {
    setIsLoading(true);
    try {
      const data = await getSubstandards();
      setSubstandards(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load substandards');
    } finally {
      setIsLoading(false);
    }
  };

  return {
    substandards,
    isLoading,
    error,
    refetch,
  };
}
