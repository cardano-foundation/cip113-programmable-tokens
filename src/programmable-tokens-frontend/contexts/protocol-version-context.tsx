/**
 * Protocol Version Context
 *
 * This React context provides access to available CIP-0113 protocol versions
 * and manages the currently selected version. It enables:
 *
 * - Listing all deployed protocol versions
 * - Selecting a specific version for queries
 * - Persisting selection in localStorage
 * - Automatic fallback to default version
 *
 * ## Usage
 *
 * ```tsx
 * function ProtocolSelector() {
 *   const { versions, selectedVersion, selectVersion } = useProtocolVersion();
 *
 *   return (
 *     <select
 *       value={selectedVersion?.txHash}
 *       onChange={(e) => selectVersion(e.target.value)}
 *     >
 *       {versions.map(v => (
 *         <option key={v.txHash} value={v.txHash}>
 *           {v.registryNodePolicyId.slice(0, 8)}...
 *         </option>
 *       ))}
 *     </select>
 *   );
 * }
 * ```
 *
 * ## Context Value
 *
 * - `versions`: Array of all available protocol versions
 * - `selectedVersion`: Currently selected version (or null)
 * - `isLoading`: Whether versions are being fetched
 * - `error`: Error message if fetch failed
 * - `selectVersion`: Function to change selected version
 * - `resetToDefault`: Function to reset to default version
 *
 * @module contexts/protocol-version-context
 */

"use client";

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { ProtocolVersionInfo } from '@/types/api';
import { getProtocolVersions } from '@/lib/api';

interface ProtocolVersionContextType {
  versions: ProtocolVersionInfo[];
  selectedVersion: ProtocolVersionInfo | null;
  isLoading: boolean;
  error: string | null;
  selectVersion: (txHash: string) => void;
  resetToDefault: () => void;
}

const ProtocolVersionContext = createContext<ProtocolVersionContextType | undefined>(undefined);

const STORAGE_KEY = 'selectedProtocolVersion';

export function ProtocolVersionProvider({ children }: { children: ReactNode }) {
  const [versions, setVersions] = useState<ProtocolVersionInfo[]>([]);
  const [selectedTxHash, setSelectedTxHash] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Load versions from API and initialize selection
  useEffect(() => {
    async function loadVersions() {
      try {
        setIsLoading(true);
        setError(null);
        const data = await getProtocolVersions();
        setVersions(data);

        // Check localStorage first
        const saved = localStorage.getItem(STORAGE_KEY);

        if (saved) {
          // Verify the saved version exists in the loaded data
          const savedVersion = data.find(v => v.txHash === saved);
          if (savedVersion) {
            setSelectedTxHash(saved);
            return;
          } else {
            // Saved version not found in API response, clear localStorage
            localStorage.removeItem(STORAGE_KEY);
          }
        }

        // No valid saved version, use default or first available
        const defaultVersion = data.find(v => v.default);

        if (defaultVersion) {
          setSelectedTxHash(defaultVersion.txHash);
        } else if (data.length > 0) {
          setSelectedTxHash(data[0].txHash);
        }
      } catch (err) {
        console.error('Failed to load protocol versions:', err);
        setError('Failed to load protocol versions');
      } finally {
        setIsLoading(false);
      }
    }

    loadVersions();
  }, []);

  // Save to localStorage when changed
  useEffect(() => {
    if (selectedTxHash) {
      localStorage.setItem(STORAGE_KEY, selectedTxHash);
    }
  }, [selectedTxHash]);

  const selectedVersion = selectedTxHash
    ? versions.find(v => v.txHash === selectedTxHash) || null
    : null;

  const selectVersion = (txHash: string) => {
    setSelectedTxHash(txHash);
  };

  const resetToDefault = () => {
    const defaultVersion = versions.find(v => v.default);
    if (defaultVersion) {
      setSelectedTxHash(defaultVersion.txHash);
    }
  };

  const value: ProtocolVersionContextType = {
    versions,
    selectedVersion,
    isLoading,
    error,
    selectVersion,
    resetToDefault,
  };

  return (
    <ProtocolVersionContext.Provider value={value}>
      {children}
    </ProtocolVersionContext.Provider>
  );
}

export function useProtocolVersion() {
  const context = useContext(ProtocolVersionContext);
  if (context === undefined) {
    throw new Error('useProtocolVersion must be used within a ProtocolVersionProvider');
  }
  return context;
}
