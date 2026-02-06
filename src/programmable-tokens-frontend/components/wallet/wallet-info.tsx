"use client";

import { useEffect, useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Copy, LogOut, Wallet, Coins, RefreshCw, Send, Snowflake } from "lucide-react";
import { truncateAddress, formatADAWithSymbol, getNetworkDisplayName } from "@/lib/utils";
import { useToast } from "@/components/ui/toast";
import { getWalletBalance, parseWalletBalance } from "@/lib/api";
import { ParsedBalance, ParsedAsset } from "@/types/api";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { TransferModal } from "@/components/transfer/TransferModal";

const WALLET_STORAGE_KEY = 'connectedWallet';

export function WalletInfo() {
  const { connected, wallet, disconnect } = useWallet();
  const { toast } = useToast();
  const { selectedVersion } = useProtocolVersion();
  const [address, setAddress] = useState<string>("");
  const [balance, setBalance] = useState<string>("0");
  const [programmableBalance, setProgrammableBalance] = useState<ParsedBalance | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isLoadingProgrammable, setIsLoadingProgrammable] = useState(false);

  // Transfer modal state
  const [transferModalOpen, setTransferModalOpen] = useState(false);
  const [selectedAsset, setSelectedAsset] = useState<ParsedAsset | null>(null);

  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";

  const handleOpenTransferModal = (asset: ParsedAsset) => {
    setSelectedAsset(asset);
    setTransferModalOpen(true);
  };

  const handleCloseTransferModal = () => {
    setTransferModalOpen(false);
    setSelectedAsset(null);
    // Refresh balances after transfer
    if (address) {
      loadProgrammableBalances(address);
    }
  };

  // Load programmable token balances
  const loadProgrammableBalances = async (walletAddress: string) => {
    try {
      setIsLoadingProgrammable(true);
      const response = await getWalletBalance(
        walletAddress,
        selectedVersion?.txHash
      );
      const parsed = await parseWalletBalance(response);
      setProgrammableBalance(parsed);
    } catch (error) {
      console.error("Failed to load programmable token balances:", error);
      // Don't show error toast - just means no programmable tokens yet
      setProgrammableBalance(null);
    } finally {
      setIsLoadingProgrammable(false);
    }
  };

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
          const addr = usedAddresses[0];
          setAddress(addr);

          // Load programmable token balances
          loadProgrammableBalances(addr);
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connected, wallet, toast]);

  // Reload programmable balances when protocol version changes
  useEffect(() => {
    if (address && selectedVersion) {
      loadProgrammableBalances(address);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedVersion?.txHash]);

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
    localStorage.removeItem(WALLET_STORAGE_KEY);
    setAddress("");
    setBalance("0");
    setProgrammableBalance(null);
  };

  const handleRefreshProgrammable = () => {
    if (address) {
      loadProgrammableBalances(address);
    }
  };

  const [isRefreshingAll, setIsRefreshingAll] = useState(false);

  const handleRefreshAll = async () => {
    if (!wallet || !address) return;

    try {
      setIsRefreshingAll(true);
      // Refresh ADA balance
      const lovelace = await wallet.getLovelace();
      setBalance(lovelace);
      // Refresh programmable tokens
      await loadProgrammableBalances(address);
      toast({
        variant: "success",
        title: "Refreshed",
        description: "Balances updated",
        duration: 2000,
      });
    } catch (error) {
      console.error("Failed to refresh balances:", error);
      toast({
        variant: "error",
        title: "Error",
        description: "Failed to refresh balances",
      });
    } finally {
      setIsRefreshingAll(false);
    }
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
              <div className="flex items-center justify-between">
                <label className="text-sm text-dark-300">Wallet Balance</label>
                <button
                  onClick={handleRefreshAll}
                  disabled={isRefreshingAll || isLoadingProgrammable}
                  className="p-1 hover:bg-dark-700 rounded transition-colors disabled:opacity-50"
                  title="Refresh all balances"
                >
                  <RefreshCw className={`h-3 w-3 text-dark-400 hover:text-white ${isRefreshingAll ? 'animate-spin' : ''}`} />
                </button>
              </div>
              <div className="px-3 py-2 bg-dark-900 rounded">
                <span className="text-2xl font-bold text-white">
                  {formatADAWithSymbol(balance)}
                </span>
              </div>
            </div>

            {/* Programmable Token Balances Section */}
            <div className="space-y-2 pt-2 border-t border-dark-700">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Coins className="h-4 w-4 text-accent-500" />
                  <label className="text-sm text-dark-300">Programmable Tokens</label>
                </div>
                <button
                  onClick={handleRefreshProgrammable}
                  disabled={isLoadingProgrammable}
                  className="p-1 hover:bg-dark-700 rounded transition-colors disabled:opacity-50"
                  title="Refresh programmable token balances"
                >
                  <RefreshCw className={`h-3 w-3 text-dark-400 hover:text-white ${isLoadingProgrammable ? 'animate-spin' : ''}`} />
                </button>
              </div>

              {isLoadingProgrammable ? (
                <div className="flex items-center justify-center py-4">
                  <div className="h-6 w-6 border-4 border-accent-500 border-t-transparent rounded-full animate-spin" />
                </div>
              ) : programmableBalance && (programmableBalance.assets.length > 0 || BigInt(programmableBalance.lovelace) > 0) ? (
                <div className="space-y-3">
                  {/* Locked ADA */}
                  {BigInt(programmableBalance.lovelace) > 0 && (
                    <div className="px-3 py-2 bg-dark-900 rounded">
                      <div className="flex items-center justify-between">
                        <div>
                          <p className="text-xs text-dark-400">Locked ADA</p>
                          <p className="text-sm text-white font-medium" title="ADA locked with programmable tokens">
                            {formatADAWithSymbol(programmableBalance.lovelace)}
                          </p>
                        </div>
                        <Badge variant="info" size="sm">Locked</Badge>
                      </div>
                    </div>
                  )}

                  {/* Programmable Tokens List */}
                  {programmableBalance.assets.length > 0 && (
                    <div className="space-y-2">
                      {programmableBalance.assets.map((asset, index) => (
                        <div key={`${asset.unit}-${index}`} className="px-3 py-2 bg-dark-900 rounded">
                          <div className="flex items-start justify-between gap-2">
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2 mb-1">
                                <p className="text-sm font-medium text-white truncate">
                                  {asset.assetName || asset.assetNameHex}
                                </p>
                                {asset.isProgrammable && (
                                  <Badge variant="success" size="sm">Programmable</Badge>
                                )}
                                {asset.isBlacklisted && (
                                  <Badge variant="error" size="sm">Frozen</Badge>
                                )}
                              </div>
                              <p className="text-xs text-dark-400 truncate" title={asset.policyId}>
                                Policy: {asset.policyId.substring(0, 16)}...
                              </p>
                            </div>
                            <div className="flex items-center gap-2">
                              <div className="text-right">
                                <p className="text-sm font-bold text-accent-400">
                                  {asset.amount}
                                </p>
                              </div>
                              {asset.isBlacklisted ? (
                                <div
                                  className="p-1.5 rounded cursor-not-allowed opacity-50"
                                  title="The funds have been frozen"
                                >
                                  <Snowflake className="h-4 w-4 text-blue-400" />
                                </div>
                              ) : (
                                <button
                                  onClick={() => handleOpenTransferModal(asset)}
                                  className="p-1.5 hover:bg-dark-700 rounded transition-colors"
                                  title={`Transfer ${asset.assetName}`}
                                >
                                  <Send className="h-4 w-4 text-primary-400 hover:text-primary-300" />
                                </button>
                              )}
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              ) : (
                <div className="px-3 py-6 bg-dark-900 rounded text-center">
                  <Coins className="h-8 w-8 text-dark-600 mx-auto mb-2" />
                  <p className="text-sm text-dark-400">No programmable tokens found</p>
                  <p className="text-xs text-dark-500 mt-1">
                    Register and mint tokens to see them here
                  </p>
                </div>
              )}
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

      {/* Transfer Modal */}
      {selectedAsset && (
        <TransferModal
          isOpen={transferModalOpen}
          onClose={handleCloseTransferModal}
          asset={selectedAsset}
          senderAddress={address}
        />
      )}
    </Card>
  );
}
