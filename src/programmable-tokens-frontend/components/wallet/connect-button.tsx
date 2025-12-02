/**
 * Wallet Connect Button Component
 *
 * This component provides a button for connecting Cardano wallets using
 * the Mesh SDK. It displays a modal with supported wallet options and
 * shows connection status when connected.
 *
 * ## Supported Wallets
 * - Nami
 * - Eternl
 * - Lace
 * - Flint
 *
 * ## States
 * - **Disconnected**: Shows "Connect Wallet" button
 * - **Connecting**: Shows loading state during connection
 * - **Connected**: Shows wallet name with success badge
 *
 * ## Connection Flow
 * 1. User clicks "Connect Wallet"
 * 2. Modal appears with wallet options
 * 3. User selects wallet (must be installed)
 * 4. Mesh SDK handles CIP-30 connection
 * 5. Badge shows connected wallet name
 *
 * @module components/wallet/connect-button
 */

"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * List of wallet configurations for connection modal.
 */
const SUPPORTED_WALLETS = [
  { id: "nami", name: "Nami", icon: "🦎" },
  { id: "eternl", name: "Eternl", icon: "♾️" },
  { id: "lace", name: "Lace", icon: "🎀" },
  { id: "flint", name: "Flint", icon: "🔥" },
];

/**
 * Wallet connection button with modal selector.
 *
 * Integrates with Mesh SDK to connect to CIP-30 compatible Cardano wallets.
 * Displays connection status and provides modal for wallet selection.
 *
 * @returns React component
 *
 * @example
 * ```tsx
 * // In header component
 * <ConnectButton />
 * ```
 */
export function ConnectButton() {
  const { connect, connected, name } = useWallet();
  const [showModal, setShowModal] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);

  const handleConnect = async (walletId: string) => {
    setIsConnecting(true);
    try {
      await connect(walletId);
      setShowModal(false);
    } catch (error) {
      console.error("Failed to connect wallet:", error);
    } finally {
      setIsConnecting(false);
    }
  };

  if (connected) {
    return (
      <Badge variant="success" size="md" className="px-4 py-2">
        <span className="w-2 h-2 rounded-full bg-primary-500 animate-pulse mr-2" />
        Connected to {name}
      </Badge>
    );
  }

  return (
    <>
      <Button onClick={() => setShowModal(true)} variant="primary" size="md">
        Connect Wallet
      </Button>

      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-in fade-in">
          <Card className="w-full max-w-md">
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle>Connect Wallet</CardTitle>
              <button
                onClick={() => setShowModal(false)}
                className="text-dark-400 hover:text-white transition-colors"
              >
                <X className="h-5 w-5" />
              </button>
            </CardHeader>
            <CardContent className="space-y-3">
              <p className="text-sm text-dark-300 mb-4">
                Select a wallet to connect to the CIP-113 Programmable Tokens application
              </p>
              {SUPPORTED_WALLETS.map((wallet) => (
                <button
                  key={wallet.id}
                  onClick={() => handleConnect(wallet.id)}
                  disabled={isConnecting}
                  className={cn(
                    "w-full flex items-center gap-3 p-4 rounded-lg border border-dark-700",
                    "bg-dark-800 hover:bg-dark-700 hover:border-primary-500",
                    "transition-all duration-200",
                    "disabled:opacity-50 disabled:cursor-not-allowed"
                  )}
                >
                  <span className="text-3xl">{wallet.icon}</span>
                  <span className="text-white font-medium">{wallet.name}</span>
                  {isConnecting && (
                    <div className="ml-auto">
                      <div className="h-4 w-4 border-2 border-primary-500 border-t-transparent rounded-full animate-spin" />
                    </div>
                  )}
                </button>
              ))}
              <p className="text-xs text-dark-400 mt-4 text-center">
                Make sure your wallet extension is installed and unlocked
              </p>
            </CardContent>
          </Card>
        </div>
      )}
    </>
  );
}
