"use client";

import { useEffect, useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Copy, LogOut, Wallet } from "lucide-react";
import { truncateAddress, formatADAWithSymbol, getNetworkDisplayName } from "@/lib/utils";
import { useToast } from "@/components/ui/toast";

export function WalletInfo() {
  const { connected, wallet, disconnect } = useWallet();
  const { toast } = useToast();
  const [address, setAddress] = useState<string>("");
  const [balance, setBalance] = useState<string>("0");
  const [isLoading, setIsLoading] = useState(true);

  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";

  useEffect(() => {
    async function loadWalletInfo() {
      if (!connected || !wallet) {
        setIsLoading(false);
        return;
      }

      try {
        setIsLoading(true);
        const usedAddresses = await wallet.getUsedAddresses();
        if (usedAddresses && usedAddresses.length > 0) {
          setAddress(usedAddresses[0]);
        }

        const lovelace = await wallet.getLovelace();
        setBalance(lovelace);
      } catch (error) {
        console.error("Failed to load wallet info:", error);
        toast({
          variant: "error",
          title: "Error",
          description: "Failed to load wallet information",
        });
      } finally {
        setIsLoading(false);
      }
    }

    loadWalletInfo();
  }, [connected, wallet, toast]);

  const handleCopyAddress = async () => {
    try {
      await navigator.clipboard.writeText(address);
      toast({
        variant: "success",
        title: "Copied!",
        description: "Address copied to clipboard",
        duration: 2000,
      });
    } catch (error) {
      toast({
        variant: "error",
        title: "Error",
        description: "Failed to copy address",
      });
    }
  };

  const handleDisconnect = () => {
    disconnect();
    setAddress("");
    setBalance("0");
  };

  if (!connected || !wallet) {
    return null;
  }

  return (
    <Card>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Wallet className="h-5 w-5 text-primary-500" />
            <span className="font-semibold text-white">Wallet Info</span>
          </div>
          <Badge variant="info" size="sm">
            {getNetworkDisplayName(network)}
          </Badge>
        </div>

        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <div className="h-8 w-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : (
          <>
            <div className="space-y-2">
              <label className="text-sm text-dark-300">Address</label>
              <div className="flex items-center gap-2">
                <code className="flex-1 px-3 py-2 bg-dark-900 rounded text-sm text-primary-400 font-mono">
                  {truncateAddress(address)}
                </code>
                <button
                  onClick={handleCopyAddress}
                  className="p-2 hover:bg-dark-700 rounded transition-colors"
                  title="Copy address"
                >
                  <Copy className="h-4 w-4 text-dark-400 hover:text-white" />
                </button>
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-sm text-dark-300">Balance</label>
              <div className="px-3 py-2 bg-dark-900 rounded">
                <span className="text-2xl font-bold text-white">
                  {formatADAWithSymbol(balance)}
                </span>
              </div>
            </div>

            <Button
              onClick={handleDisconnect}
              variant="ghost"
              size="md"
              className="w-full"
            >
              <LogOut className="h-4 w-4 mr-2" />
              Disconnect
            </Button>
          </>
        )}
      </CardContent>
    </Card>
  );
}
