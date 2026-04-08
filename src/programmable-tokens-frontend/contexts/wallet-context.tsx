"use client";

import {
  createContext,
  useContext,
  useState,
  useCallback,
  useMemo,
  type ReactNode,
} from "react";

// ---------------------------------------------------------------------------
// Address conversion (CIP-30 hex → bech32)
// Uses Evolution SDK via our CIP-113 SDK
// ---------------------------------------------------------------------------

import { addressHexToBech32, assembleSignedTx } from "@cip113/sdk";

// ---------------------------------------------------------------------------
// CIP-30 Wallet API types
// ---------------------------------------------------------------------------

/** CIP-30 wallet API returned by `getCardano()[name].enable()` */
export interface WalletApi {
  getUsedAddresses(): Promise<string[]>;
  getUnusedAddresses(): Promise<string[]>;
  getChangeAddress(): Promise<string>;
  getBalance(): Promise<string>;
  getUtxos(): Promise<string[] | undefined>;
  signTx(tx: string, partialSign?: boolean): Promise<string>;
  submitTx(tx: string): Promise<string>;
  /** CIP-103 batch signing (not all wallets support this) */
  signTxs(txs: string[], partialSign?: boolean): Promise<string[]>;
  getLovelace(): Promise<string>;
}

/** Shape of `getCardano()[name]` before enable() */
interface CIP30WalletEntry {
  name: string;
  icon: string;
  apiVersion?: string;
  enable(): Promise<WalletApi>;
  isEnabled(): Promise<boolean>;
}

// Use module augmentation only if getCardano() isn't already declared
// eslint-disable-next-line @typescript-eslint/no-namespace
declare namespace CardanoCIP30 {
  type CardanoWindow = Record<string, CIP30WalletEntry | undefined>;
}

function getCardano(): Record<string, CIP30WalletEntry | undefined> | undefined {
  if (typeof window === "undefined") return undefined;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (window as any).cardano as CardanoCIP30.CardanoWindow | undefined;
}

// ---------------------------------------------------------------------------
// Context types
// ---------------------------------------------------------------------------

export interface WalletContextValue {
  /** Whether a wallet is currently connected */
  connected: boolean;
  /** Name of the connected wallet (e.g., "eternl", "lace") */
  name: string;
  /** The CIP-30 wallet API (always non-null — throws if not connected) */
  wallet: WalletApi;
  /** Connect to a wallet by its CIP-30 key (e.g., "eternl") */
  connect(walletKey: string): Promise<void>;
  /** Disconnect the current wallet */
  disconnect(): void;
}

/** Stub wallet that throws on any method call. Used before connecting. */
const DISCONNECTED_WALLET: WalletApi = {
  getUsedAddresses: () => { throw new Error("Wallet not connected"); },
  getUnusedAddresses: () => { throw new Error("Wallet not connected"); },
  getChangeAddress: () => { throw new Error("Wallet not connected"); },
  getBalance: () => { throw new Error("Wallet not connected"); },
  getUtxos: () => { throw new Error("Wallet not connected"); },
  signTx: () => { throw new Error("Wallet not connected"); },
  submitTx: () => { throw new Error("Wallet not connected"); },
  signTxs: () => { throw new Error("Wallet not connected"); },
  getLovelace: () => { throw new Error("Wallet not connected"); },
};

const WalletContext = createContext<WalletContextValue | null>(null);

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

export function WalletProvider({ children }: { children: ReactNode }) {
  const [walletApi, setWalletApi] = useState<WalletApi>(DISCONNECTED_WALLET);
  const [walletName, setWalletName] = useState("");

  const connect = useCallback(async (walletKey: string) => {
    const entry = getCardano()?.[walletKey];
    if (!entry) {
      throw new Error(`Wallet "${walletKey}" not found in getCardano()`);
    }

    const api = await entry.enable();

    // Wrap the raw CIP-30 API to:
    // 1. Convert hex addresses to bech32 (CIP-30 returns hex, Mesh returned bech32)
    // 2. Assemble signed tx (CIP-30 signTx returns witness set, not full tx)
    // 3. Normalize getLovelace
    // 4. Add signTxs fallback
    const wrappedApi: WalletApi = {
      ...api,
      async getUsedAddresses() {
        const hexAddrs = await api.getUsedAddresses();
        return hexAddrs.map(addressHexToBech32);
      },
      async getUnusedAddresses() {
        const hexAddrs = await api.getUnusedAddresses();
        return hexAddrs.map(addressHexToBech32);
      },
      async getChangeAddress() {
        const hexAddr = await api.getChangeAddress();
        return addressHexToBech32(hexAddr);
      },
      async signTx(tx: string, partialSign?: boolean) {
        // CIP-30 signTx returns the witness set CBOR, not the full signed tx.
        // We need to assemble the full signed tx for submitTx.
        const witnessSetHex = await api.signTx(tx, partialSign);
        return assembleSignedTx(tx, witnessSetHex);
      },
      async getLovelace() {
        if (typeof api.getLovelace === "function") {
          return api.getLovelace();
        }
        const balance = await api.getBalance();
        return balance;
      },
      async signTxs(txs: string[], partialSign?: boolean) {
        if (typeof api.signTxs === "function") {
          // CIP-103 signTxs returns witness sets
          const witnessSets = await api.signTxs(txs, partialSign);
          return txs.map((tx, i) => assembleSignedTx(tx, witnessSets[i]));
        }
        // Fallback: sequential signing (each already assembled via our signTx wrapper above)
        const signed: string[] = [];
        for (const tx of txs) {
          signed.push(await wrappedApi.signTx(tx, partialSign));
        }
        return signed;
      },
    };

    setWalletApi(wrappedApi);
    setWalletName(entry.name);
  }, []);

  const disconnect = useCallback(() => {
    setWalletApi(DISCONNECTED_WALLET);
    setWalletName("");
  }, []);

  const value = useMemo<WalletContextValue>(
    () => ({
      connected: walletApi !== DISCONNECTED_WALLET,
      name: walletName,
      wallet: walletApi,
      connect,
      disconnect,
    }),
    [walletApi, walletName, connect, disconnect]
  );

  return (
    <WalletContext.Provider value={value}>{children}</WalletContext.Provider>
  );
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

/**
 * Hook to access wallet connection state and CIP-30 API.
 *
 * Drop-in replacement for `useWallet()` from `@meshsdk/react`.
 */
export function useWallet(): WalletContextValue {
  const ctx = useContext(WalletContext);
  if (!ctx) {
    throw new Error("useWallet must be used within a <WalletProvider>");
  }
  return ctx;
}
