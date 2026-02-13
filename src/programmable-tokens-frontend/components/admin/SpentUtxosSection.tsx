"use client";

import { useState, useEffect } from "react";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { CopyButton } from "@/components/ui/copy-button";
import { getSpentUtxos, SpentUtxoInfo, extractPkhFromAddress } from "@/lib/api/admin";
import { AlertCircle, ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";

interface SpentUtxosSectionProps {
  adminPkh: string; // Can be PKH or address - we'll extract PKH if needed
}

export function SpentUtxosSection({ adminPkh }: SpentUtxosSectionProps) {
  const [spentUtxos, setSpentUtxos] = useState<SpentUtxoInfo[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actualPkh, setActualPkh] = useState<string | null>(null);

  useEffect(() => {
    async function loadSpentUtxos() {
      try {
        setIsLoading(true);
        setError(null);
        
        // Extract PKH if adminPkh is an address
        let pkh = adminPkh;
        if (adminPkh.startsWith("addr")) {
          const extracted = await extractPkhFromAddress(adminPkh);
          if (!extracted) {
            setError("Could not extract PKH from address");
            setIsLoading(false);
            return;
          }
          pkh = extracted;
          setActualPkh(extracted);
        } else {
          setActualPkh(adminPkh);
        }
        
        const response = await getSpentUtxos(pkh);
        setSpentUtxos(response.spentUtxos);
      } catch (err) {
        console.error("Failed to load spent UTXOs:", err);
        setError(err instanceof Error ? err.message : "Failed to load spent UTXOs");
      } finally {
        setIsLoading(false);
      }
    }

    if (adminPkh) {
      loadSpentUtxos();
    }
  }, [adminPkh]);

  const truncateHash = (hash: string, length: number = 16) => {
    if (hash.length <= length * 2) return hash;
    return `${hash.slice(0, length)}...${hash.slice(-length)}`;
  };

  const formatAdaAmount = (lovelace: string | null) => {
    if (!lovelace) return "N/A";
    try {
      const ada = BigInt(lovelace) / BigInt(1_000_000);
      return `${ada.toLocaleString()} ADA`;
    } catch {
      return lovelace;
    }
  };

  const getExplorerUrl = (txHash: string) => {
    const network = process.env.NEXT_PUBLIC_NETWORK || "preview";
    return `https://${network === "mainnet" ? "" : network + "."}cardanoscan.io/transaction/${txHash}`;
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="flex items-center gap-2">
            <AlertCircle className="h-5 w-5 text-orange-400" />
            Spent UTXOs
          </CardTitle>
          <Badge variant="info" size="sm">
            {spentUtxos.length} {spentUtxos.length === 1 ? "UTXO" : "UTXOs"}
          </Badge>
        </div>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <div className="h-8 w-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
        ) : error ? (
          <div className="p-4 bg-red-500/10 border border-red-500/30 rounded-lg">
            <p className="text-red-300 text-sm">{error}</p>
          </div>
        ) : spentUtxos.length === 0 ? (
          <div className="text-center py-8">
            <p className="text-dark-400">No spent UTXOs found for this admin.</p>
            <p className="text-dark-500 text-sm mt-2">
              All UTXOs are currently unspent and available for transactions.
            </p>
            {actualPkh && (
              <p className="text-dark-600 text-xs mt-4 font-mono">
                Admin PKH: {actualPkh.slice(0, 16)}...
              </p>
            )}
          </div>
        ) : (
          <div className="space-y-4">
            <div className="p-4 bg-yellow-500/10 border border-yellow-500/30 rounded-lg">
              <p className="text-yellow-300 text-sm font-medium mb-2">
                ⚠️ Already Spent UTXOs
              </p>
              <p className="text-yellow-200/70 text-xs">
                These UTXOs have already been consumed in previous transactions and cannot be reused.
                If you see "already spent UTXO" errors, these are the UTXOs that were used.
              </p>
            </div>

            <div className="space-y-3">
              {spentUtxos.map((utxo, index) => (
                <Card key={index} className="bg-dark-800 border-dark-700">
                  <CardContent className="p-4">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div>
                        <div className="flex items-center justify-between mb-2">
                          <span className="text-xs text-dark-400">Transaction Hash</span>
                          <div className="flex items-center gap-2">
                            <CopyButton value={utxo.txHash} />
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-6 w-6 p-0"
                              onClick={() => window.open(getExplorerUrl(utxo.txHash), "_blank")}
                            >
                              <ExternalLink className="h-3 w-3" />
                            </Button>
                          </div>
                        </div>
                        <p className="text-sm font-mono text-primary-400 break-all">
                          {truncateHash(utxo.txHash)}
                        </p>
                      </div>

                      <div>
                        <span className="text-xs text-dark-400">Output Index</span>
                        <p className="text-sm text-white font-medium">{utxo.outputIndex}</p>
                      </div>

                      <div>
                        <span className="text-xs text-dark-400">Source</span>
                        <Badge variant="default" className="mt-1">
                          {utxo.source}
                        </Badge>
                      </div>

                      <div>
                        <span className="text-xs text-dark-400">Amount</span>
                        <p className="text-sm text-white">{formatAdaAmount(utxo.adaAmount)}</p>
                      </div>

                      {utxo.spentByTxHash && (
                        <div className="md:col-span-2">
                          <span className="text-xs text-dark-400">Spent By Transaction</span>
                          <div className="flex items-center gap-2 mt-1">
                            <p className="text-sm font-mono text-orange-400 break-all">
                              {truncateHash(utxo.spentByTxHash)}
                            </p>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-6 w-6 p-0"
                              onClick={() => window.open(getExplorerUrl(utxo.spentByTxHash!), "_blank")}
                            >
                              <ExternalLink className="h-3 w-3" />
                            </Button>
                          </div>
                        </div>
                      )}
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
