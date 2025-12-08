"use client";

import { useState, useEffect } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { X, Wallet } from "lucide-react";
import { cn } from "@/lib/utils";

interface InstalledWallet {
  id: string;
  name: string;
  icon: string;
}

const WALLET_STORAGE_KEY = 'connectedWallet';

export function ConnectButton() {
  const { connect, connected, name, disconnect } = useWallet();
  const [showModal, setShowModal] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [installedWallets, setInstalledWallets] = useState<InstalledWallet[]>([]);
  const [hasAttemptedAutoConnect, setHasAttemptedAutoConnect] = useState(false);

  // Detect installed wallets using CIP-30
  useEffect(() => {
    if (typeof window === 'undefined') return;

    const detectWallets = () => {
      const wallets: InstalledWallet[] = [];

      if (typeof window.cardano !== 'undefined' && window.cardano) {
        // Iterate through all properties in window.cardano
        Object.keys(window.cardano).forEach((key) => {
          const wallet = window.cardano?.[key];
          // Check if it's a valid CIP-30 wallet (has name and icon)
          if (wallet && typeof wallet === 'object' && wallet.name && wallet.icon) {
            wallets.push({
              id: key,
              name: wallet.name,
              icon: wallet.icon
            });
          }
        });
      }

      setInstalledWallets(wallets);
    };

    // Detect immediately
    detectWallets();

    // Also detect after a short delay (some wallets load asynchronously)
    const timeoutId = setTimeout(detectWallets, 500);

    return () => clearTimeout(timeoutId);
  }, []);

  // Auto-reconnect to previously connected wallet
  useEffect(() => {
    if (typeof window === 'undefined') return;
    if (connected || hasAttemptedAutoConnect) return;

    const autoReconnect = async () => {
      try {
        const savedWalletId = localStorage.getItem(WALLET_STORAGE_KEY);
        if (!savedWalletId) {
          setHasAttemptedAutoConnect(true);
          return;
        }

        // Wait a bit for wallets to be detected
        await new Promise(resolve => setTimeout(resolve, 600));

        // Check if the saved wallet is still installed
        if (window.cardano?.[savedWalletId]) {
          console.log(`Auto-reconnecting to ${savedWalletId}...`);
          await connect(savedWalletId);
        } else {
          // Wallet no longer installed, clear storage
          localStorage.removeItem(WALLET_STORAGE_KEY);
        }
      } catch (error) {
        console.error('Auto-reconnect failed:', error);
        localStorage.removeItem(WALLET_STORAGE_KEY);
      } finally {
        setHasAttemptedAutoConnect(true);
      }
    };

    autoReconnect();
  }, [connect, connected, hasAttemptedAutoConnect]);

  const handleConnect = async (walletId: string) => {
    setIsConnecting(true);
    try {
      await connect(walletId);
      // Save wallet ID to localStorage for auto-reconnect
      localStorage.setItem(WALLET_STORAGE_KEY, walletId);
      setShowModal(false);
    } catch (error) {
      console.error("Failed to connect wallet:", error);
      localStorage.removeItem(WALLET_STORAGE_KEY);
    } finally {
      setIsConnecting(false);
    }
  };

  const handleDisconnect = () => {
    disconnect();
    localStorage.removeItem(WALLET_STORAGE_KEY);
  };

  if (connected) {
    return (
      <div className="relative group">
        <Badge variant="success" size="md" className="px-4 py-2 cursor-pointer">
          <span className="w-2 h-2 rounded-full bg-primary-500 animate-pulse mr-2" />
          Connected to {name}
        </Badge>

        {/* Disconnect button on hover */}
        <button
          onClick={handleDisconnect}
          className="absolute top-full right-0 mt-1 px-3 py-1.5 bg-dark-800 border border-dark-700 rounded text-xs text-dark-300 hover:text-white hover:border-red-500 transition-colors opacity-0 group-hover:opacity-100 whitespace-nowrap"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <div className="relative">
      <Button onClick={() => setShowModal(true)} variant="primary" size="md">
        <Wallet className="h-4 w-4 mr-2" />
        Connect Wallet
      </Button>

      {showModal && (
        <>
          {/* Backdrop */}
          <div
            className="fixed inset-0 z-40"
            onClick={() => setShowModal(false)}
          />

          {/* Dropdown */}
          <Card className="absolute top-full right-0 mt-2 w-80 z-50 shadow-xl">
            <CardHeader className="flex flex-row items-center justify-between pb-3">
              <CardTitle className="text-base">Connect Wallet</CardTitle>
              <button
                onClick={() => setShowModal(false)}
                className="text-dark-400 hover:text-white transition-colors"
              >
                <X className="h-4 w-4" />
              </button>
            </CardHeader>
            <CardContent className="space-y-2">
              {installedWallets.length === 0 ? (
                <div className="text-center py-8">
                  <Wallet className="h-12 w-12 text-dark-600 mx-auto mb-3" />
                  <p className="text-sm text-dark-300 mb-2">
                    No wallets detected
                  </p>
                  <p className="text-xs text-dark-400">
                    Please install a Cardano wallet extension
                  </p>
                </div>
              ) : (
                <>
                  <p className="text-xs text-dark-400 mb-3">
                    Select a wallet to connect
                  </p>
                  {installedWallets.map((wallet) => (
                    <button
                      key={wallet.id}
                      onClick={() => handleConnect(wallet.id)}
                      disabled={isConnecting}
                      className={cn(
                        "w-full flex items-center gap-3 p-3 rounded-lg border border-dark-700",
                        "bg-dark-800 hover:bg-dark-700 hover:border-primary-500",
                        "transition-all duration-200",
                        "disabled:opacity-50 disabled:cursor-not-allowed"
                      )}
                    >
                      {/* Wallet Icon */}
                      <div className="w-8 h-8 rounded-lg overflow-hidden flex-shrink-0 bg-dark-900">
                        {wallet.icon ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
                            src={wallet.icon}
                            alt={`${wallet.name} icon`}
                            className="w-full h-full object-cover"
                          />
                        ) : (
                          <div className="w-full h-full flex items-center justify-center">
                            <Wallet className="h-4 w-4 text-dark-500" />
                          </div>
                        )}
                      </div>

                      {/* Wallet Name */}
                      <span className="text-white font-medium flex-1 text-left">{wallet.name}</span>

                      {/* Loading Spinner */}
                      {isConnecting && (
                        <div className="h-4 w-4 border-2 border-primary-500 border-t-transparent rounded-full animate-spin" />
                      )}
                    </button>
                  ))}
                </>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
