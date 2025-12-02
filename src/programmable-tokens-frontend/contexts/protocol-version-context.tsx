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
        console.log('Loaded protocol versions:', data);
        setVersions(data);

        // Check localStorage first
        const saved = localStorage.getItem(STORAGE_KEY);
        console.log('Saved protocol version from localStorage:', saved);

        if (saved) {
          // Verify the saved version exists in the loaded data
          const savedVersion = data.find(v => v.txHash === saved);
          if (savedVersion) {
            console.log('Using saved protocol version:', savedVersion.txHash);
            setSelectedTxHash(saved);
            return;
          } else {
            console.log('Saved version not found in API response, clearing localStorage');
            localStorage.removeItem(STORAGE_KEY);
          }
        }

        // No valid saved version, use default or first available
        const defaultVersion = data.find(v => v.default);
        console.log('Default protocol version:', defaultVersion);

        if (defaultVersion) {
          console.log('Using default protocol version:', defaultVersion.txHash);
          setSelectedTxHash(defaultVersion.txHash);
        } else {
          console.log('No default version found, using first available');
          if (data.length > 0) {
            console.log('Using first protocol version:', data[0].txHash);
            setSelectedTxHash(data[0].txHash);
          }
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
    console.log('resetToDefault called');
    console.log('Available versions:', versions);
    const defaultVersion = versions.find(v => v.default);
    console.log('Found default version:', defaultVersion);
    if (defaultVersion) {
      console.log('Resetting to default version:', defaultVersion.txHash);
      setSelectedTxHash(defaultVersion.txHash);
    } else {
      console.warn('No default version found to reset to');
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
