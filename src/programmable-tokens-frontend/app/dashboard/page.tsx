"use client";

import { useEffect, useState } from "react";
import { useWallet } from "@meshsdk/react";
import { PageContainer } from "@/components/layout";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/toast";
import { History, RefreshCw, AlertCircle, Wallet, Copy, ExternalLink } from "lucide-react";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { useTransactionHistory } from "@/hooks/use-transaction-history";
import { getWalletBalance } from "@/lib/api";
import { TransactionType } from "@/types/api";
import { truncateAddress, formatDate, getExplorerTxUrl } from "@/lib/utils/format";

export default function DashboardPage() {
  const { connected, wallet } = useWallet();
  const { selectedVersion } = useProtocolVersion();
  const { toast } = useToast();
  const [stakeKeyHash, setStakeKeyHash] = useState<string | null>(null);
  const [walletAddress, setWalletAddress] = useState<string | null>(null);
  const [isLoadingStakeKey, setIsLoadingStakeKey] = useState(true);

  // Copy to clipboard helper
  const copyToClipboard = async (text: string, label: string) => {
    try {
      await navigator.clipboard.writeText(text);
      toast({
        variant: "success",
        title: "Copied!",
        description: `${label} copied to clipboard`,
        duration: 2000,
      });
    } catch (error) {
      toast({
        variant: "error",
        title: "Failed to copy",
        description: "Could not copy to clipboard",
      });
    }
  };

  // Load stake key hash from wallet balance API
  useEffect(() => {
    async function loadStakeKey() {
      if (!connected || !wallet) {
        setStakeKeyHash(null);
        setWalletAddress(null);
        setIsLoadingStakeKey(false);
        return;
      }

      try {
        setIsLoadingStakeKey(true);
        const usedAddresses = await wallet.getUsedAddresses();
        if (usedAddresses && usedAddresses.length > 0) {
          const addr = usedAddresses[0];
          setWalletAddress(addr);

          // Get stake key hash from balance API
          const balanceResponse = await getWalletBalance(addr, selectedVersion?.txHash);
          if (balanceResponse.stakeHash) {
            setStakeKeyHash(balanceResponse.stakeHash);
          }
        }
      } catch (error) {
        console.error("Failed to load stake key:", error);
      } finally {
        setIsLoadingStakeKey(false);
      }
    }

    loadStakeKey();
  }, [connected, wallet, selectedVersion]);

  // Fetch transaction history using the hook
  const { history, isLoading, error, refetch } = useTransactionHistory(
    stakeKeyHash,
    selectedVersion?.txHash,
    20 // Show last 20 transactions
  );

  if (!connected) {
    return (
      <PageContainer>
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-12">
            <Wallet className="h-16 w-16 text-dark-500 mb-4" />
            <h2 className="text-xl font-semibold mb-2">Connect Your Wallet</h2>
            <p className="text-dark-300 text-center max-w-md">
              Please connect your wallet to view your transaction history and dashboard
            </p>
          </CardContent>
        </Card>
      </PageContainer>
    );
  }

  return (
    <PageContainer>
      <div className="space-y-6">
        {/* Page Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold text-white flex items-center gap-2">
              <History className="h-8 w-8 text-primary-500" />
              Dashboard
            </h1>
            <p className="text-dark-300 mt-1">
              View your transaction history and programmable token activity
            </p>
          </div>
          <Button
            onClick={() => refetch()}
            disabled={isLoading || isLoadingStakeKey}
            variant="secondary"
            size="sm"
          >
            <RefreshCw className={`h-4 w-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
            Refresh
          </Button>
        </div>

        {/* Wallet Info Card */}
        {walletAddress && (
          <Card>
            <CardHeader>
              <CardTitle>Wallet Information</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-dark-300 mb-1">Address</p>
                  <div className="flex items-center gap-2">
                    <p className="font-mono text-sm">{truncateAddress(walletAddress)}</p>
                    <button
                      onClick={() => copyToClipboard(walletAddress, "Address")}
                      className="p-1 hover:bg-dark-700 rounded transition-colors"
                      title="Copy address"
                    >
                      <Copy className="h-4 w-4 text-dark-400 hover:text-primary-500" />
                    </button>
                  </div>
                </div>
                {stakeKeyHash && (
                  <div>
                    <p className="text-sm text-dark-300 mb-1">Stake Key Hash</p>
                    <div className="flex items-center gap-2">
                      <p className="font-mono text-sm">{truncateAddress(stakeKeyHash)}</p>
                      <button
                        onClick={() => copyToClipboard(stakeKeyHash, "Stake key hash")}
                        className="p-1 hover:bg-dark-700 rounded transition-colors"
                        title="Copy stake key hash"
                      >
                        <Copy className="h-4 w-4 text-dark-400 hover:text-primary-500" />
                      </button>
                    </div>
                  </div>
                )}
                {selectedVersion && (
                  <div>
                    <p className="text-sm text-dark-300 mb-1">Protocol Version</p>
                    <div className="flex items-center gap-2">
                      <p className="font-mono text-sm">{truncateAddress(selectedVersion.txHash)}</p>
                      <button
                        onClick={() => copyToClipboard(selectedVersion.txHash, "Protocol version")}
                        className="p-1 hover:bg-dark-700 rounded transition-colors"
                        title="Copy protocol version"
                      >
                        <Copy className="h-4 w-4 text-dark-400 hover:text-primary-500" />
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Transaction History Card */}
        <Card>
          <CardHeader>
            <CardTitle>Transaction History</CardTitle>
            <CardDescription>
              Recent transactions involving your programmable tokens
              {selectedVersion && " (filtered by selected protocol version)"}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {isLoadingStakeKey || isLoading ? (
              <div className="flex items-center justify-center py-12">
                <RefreshCw className="h-8 w-8 text-primary-500 animate-spin" />
              </div>
            ) : error ? (
              <div className="flex flex-col items-center justify-center py-12">
                <AlertCircle className="h-12 w-12 text-red-500 mb-4" />
                <p className="text-red-500 text-center">{error}</p>
                <Button onClick={() => refetch()} className="mt-4" variant="secondary">
                  Try Again
                </Button>
              </div>
            ) : history.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-dark-300">
                <History className="h-12 w-12 mb-4" />
                <p>No transactions found</p>
                <p className="text-sm mt-1">
                  Start minting or transferring programmable tokens to see your history
                </p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-dark-700">
                      <th className="text-left py-3 px-4 text-sm font-semibold text-dark-300">
                        Transaction
                      </th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-dark-300">
                        Type
                      </th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-dark-300">
                        Balance Change
                      </th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-dark-300">
                        Address
                      </th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-dark-300">
                        Time
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {history.map((tx) => (
                      <tr
                        key={`${tx.txHash}-${tx.address}`}
                        className="border-b border-dark-800 hover:bg-dark-900"
                      >
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-2">
                            <a
                              href={getExplorerTxUrl(tx.txHash)}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="font-mono text-sm text-primary-500 hover:text-primary-400 flex items-center gap-1"
                            >
                              {truncateAddress(tx.txHash)}
                              <ExternalLink className="h-3 w-3" />
                            </a>
                            <button
                              onClick={() => copyToClipboard(tx.txHash, "Transaction hash")}
                              className="p-1 hover:bg-dark-700 rounded transition-colors"
                              title="Copy transaction hash"
                            >
                              <Copy className="h-3 w-3 text-dark-400 hover:text-primary-500" />
                            </button>
                          </div>
                        </td>
                        <td className="py-3 px-4">
                          <TransactionTypeBadge type={tx.transactionType} />
                        </td>
                        <td className="py-3 px-4">
                          <BalanceDiffDisplay balanceDiff={tx.balanceDiff} />
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-2">
                            <span className="font-mono text-sm text-dark-300">
                              {truncateAddress(tx.address)}
                            </span>
                            <button
                              onClick={() => copyToClipboard(tx.address, "Address")}
                              className="p-1 hover:bg-dark-700 rounded transition-colors"
                              title="Copy address"
                            >
                              <Copy className="h-3 w-3 text-dark-400 hover:text-primary-500" />
                            </button>
                          </div>
                        </td>
                        <td className="py-3 px-4 text-sm text-dark-300">
                          {formatDate(new Date(tx.timestamp * 1000))}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </PageContainer>
  );
}

// Transaction Type Badge Component
function TransactionTypeBadge({ type }: { type: TransactionType }) {
  if (!type) {
    return <Badge variant="default" size="sm">Unknown</Badge>;
  }

  const variants: Record<string, "success" | "error" | "warning" | "info"> = {
    MINT: "success",
    BURN: "error",
    TRANSFER: "info",
    REGISTER: "warning",
  };

  return (
    <Badge variant={variants[type] || "default"} size="sm">
      {type}
    </Badge>
  );
}

// Balance Diff Display Component
function BalanceDiffDisplay({ balanceDiff }: { balanceDiff: Record<string, string> }) {
  const entries = Object.entries(balanceDiff);

  if (entries.length === 0) {
    return <span className="text-dark-500 text-sm">No change</span>;
  }

  return (
    <div className="space-y-1">
      {entries.map(([unit, amount]) => {
        const isPositive = amount.startsWith('+');
        const isNegative = amount.startsWith('-');

        // Decode asset name for display
        const displayUnit = unit === 'lovelace' ? 'ADA' : unit;

        return (
          <div
            key={unit}
            className={`text-sm font-mono ${
              isPositive
                ? 'text-green-400'
                : isNegative
                ? 'text-red-400'
                : 'text-dark-300'
            }`}
          >
            {amount} {displayUnit === 'ADA' ? 'ADA' : truncateAddress(displayUnit)}
          </div>
        );
      })}
    </div>
  );
}
