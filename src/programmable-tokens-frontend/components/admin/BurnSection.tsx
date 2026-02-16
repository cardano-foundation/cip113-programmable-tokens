"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Flame, Loader2, ExternalLink, AlertTriangle } from "lucide-react";
import { UtxoInfo } from "@/types/api";
import { AdminTokenInfo, getUtxosForBurning } from "@/lib/api/admin";
import { AdminTokenSelector } from "./AdminTokenSelector";
import { burnToken } from "@/lib/api/minting";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { useToast } from "@/components/ui/use-toast";

interface BurnSectionProps {
  adminTokens: AdminTokenInfo[];
  feePayerAddress: string;
}

type Step = "form" | "signing" | "success";

export function BurnSection({ adminTokens, feePayerAddress }: BurnSectionProps) {
  const { wallet } = useWallet();
  const { selectedVersion } = useProtocolVersion();
  const { toast: showToast } = useToast();

  const [selectedToken, setSelectedToken] = useState<AdminTokenInfo | null>(null);
  const [targetAddress, setTargetAddress] = useState("");
  const [utxos, setUtxos] = useState<UtxoInfo[]>([]);
  const [burnAmounts, setBurnAmounts] = useState<Record<string, string>>({});
  const [isLoadingUtxos, setIsLoadingUtxos] = useState(false);
  const [isBurning, setIsBurning] = useState<string | null>(null); // UTxO key being burned
  const [step, setStep] = useState<Step>("form");
  const [txHash, setTxHash] = useState<string | null>(null);

  const [errors, setErrors] = useState({
    token: "",
    address: "",
    amount: "",
  });

  // Filter tokens to ISSUER_ADMIN only
  const issuerTokens = adminTokens.filter(t => t.roles.includes("ISSUER_ADMIN"));

  const handleFetchUtxos = async () => {
    if (!selectedToken || !targetAddress) {
      setErrors({
        ...errors,
        token: !selectedToken ? "Please select a token" : "",
        address: !targetAddress ? "Please enter an address" : "",
      });
      return;
    }

    setIsLoadingUtxos(true);
    setErrors({ token: "", address: "", amount: "" });

    try {
      const response = await getUtxosForBurning(
        targetAddress,
        selectedToken.policyId,
        selectedToken.assetName
      );

      setUtxos(response.utxos);

      if (response.utxos.length === 0) {
        showToast({
          title: "No UTxOs Found",
          description: "No UTxOs found containing this token at the address",
          variant: "default",
        });
      }

    } catch (error) {
      console.error("Failed to fetch UTxOs:", error);
      showToast({
        title: "Error",
        description: "Failed to fetch UTxOs",
        variant: "error",
      });
      setErrors({ ...errors, address: "Failed to fetch UTxOs" });
    } finally {
      setIsLoadingUtxos(false);
    }
  };

  const isFes = selectedToken?.substandardId === "freeze-and-seize";

  const handleBurnUtxo = async (utxo: UtxoInfo) => {
    if (!selectedToken) return;

    const utxoKey = `${utxo.txHash}#${utxo.outputIndex}`;
    // FES always wipes the full UTxO amount; other substandards use user-entered amount
    const burnAmount = isFes ? utxo.tokenAmount : burnAmounts[utxoKey];

    // Validate burn amount (skip for FES since it's always the full amount)
    if (!isFes) {
      if (!burnAmount || parseFloat(burnAmount) <= 0) {
        showToast({
          title: "Invalid Amount",
          description: "Please enter a valid burn amount",
          variant: "error",
        });
        return;
      }

      if (parseFloat(burnAmount) > parseFloat(utxo.tokenAmount)) {
        showToast({
          title: "Invalid Amount",
          description: "Burn amount exceeds available amount",
          variant: "error",
        });
        return;
      }
    }

    setIsBurning(utxoKey);
    setStep("signing");

    try {
      // Build burn transaction
      const unsignedTx = await burnToken({
        feePayerAddress,
        tokenPolicyId: selectedToken.policyId,
        assetName: selectedToken.assetName,
        quantity: burnAmount,
        utxoTxHash: utxo.txHash,
        utxoOutputIndex: utxo.outputIndex,
      }, selectedVersion?.txHash);

      // Sign & submit
      const signedTx = await wallet.signTx(unsignedTx);
      const submittedTxHash = await wallet.submitTx(signedTx);

      setTxHash(submittedTxHash);
      setStep("success");
      showToast({
        title: "Burn Successful",
        description: "Tokens burned successfully!",
        variant: "success",
      });

      // Refresh UTxO list
      await handleFetchUtxos();

    } catch (error) {
      console.error("Burn failed:", error);
      showToast({
        title: "Burn Failed",
        description: error instanceof Error ? error.message : "Burn failed",
        variant: "error",
      });
      setStep("form");
    } finally {
      setIsBurning(null);
    }
  };

  const handleReset = () => {
    setStep("form");
    setTxHash(null);
    setUtxos([]);
    setBurnAmounts({});
    setTargetAddress("");
  };

  if (step === "success" && txHash) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-green-400">
            <Flame className="h-6 w-6" />
            Burn Successful
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="p-4 bg-green-900/20 border border-green-600/30 rounded-lg">
            <p className="text-sm text-green-200 mb-2">Transaction Hash:</p>
            <div className="flex items-center gap-2">
              <code className="text-xs text-green-400 break-all">{txHash}</code>
              <a
                href={`https://preprod.cardanoscan.io/transaction/${txHash}`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-400 hover:text-primary-300"
              >
                <ExternalLink className="h-4 w-4" />
              </a>
            </div>
          </div>

          <Button onClick={handleReset} variant="primary" className="w-full">
            Burn More Tokens
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Flame className="h-5 w-5 text-orange-400" />
          Burn Tokens
        </CardTitle>
        <p className="text-sm text-dark-300 mt-1">
          Burn programmable tokens from specific UTxOs (requires ISSUER_ADMIN role)
        </p>
      </CardHeader>

      <CardContent className="space-y-6">
        {/* Warning Banner */}
        <div className="p-4 bg-yellow-900/20 border border-yellow-600/30 rounded-lg flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 text-yellow-500 flex-shrink-0 mt-0.5" />
          <div className="text-sm text-yellow-200">
            <p className="font-semibold">Irreversible Action</p>
            <p>Burning tokens permanently reduces the total supply. This action cannot be undone.</p>
          </div>
        </div>

        {/* Step 1: Token Selection */}
        <div>
          <label className="block text-sm font-medium text-dark-300 mb-2">
            1. Select Token
          </label>
          <AdminTokenSelector
            tokens={issuerTokens}
            selectedToken={selectedToken}
            onSelect={setSelectedToken}
          />
          {errors.token && (
            <p className="text-sm text-red-400 mt-1">{errors.token}</p>
          )}
        </div>

        {/* Step 2: Target Address */}
        <div>
          <label className="block text-sm font-medium text-dark-300 mb-2">
            2. Target Address (containing tokens to burn)
          </label>
          <input
            type="text"
            value={targetAddress}
            onChange={(e) => setTargetAddress(e.target.value)}
            placeholder="addr_test1..."
            className="w-full px-4 py-2 bg-dark-900 border border-dark-700 rounded-lg text-white
              placeholder:text-dark-500 focus:outline-none focus:ring-2 focus:ring-primary-500"
            disabled={!selectedToken}
          />
          {errors.address && (
            <p className="text-sm text-red-400 mt-1">{errors.address}</p>
          )}
        </div>

        {/* Fetch UTxOs Button */}
        <Button
          onClick={handleFetchUtxos}
          variant="secondary"
          disabled={!selectedToken || !targetAddress || isLoadingUtxos}
          className="w-full"
        >
          {isLoadingUtxos ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin mr-2" />
              Loading UTxOs...
            </>
          ) : (
            "Fetch UTxOs"
          )}
        </Button>

        {/* Step 3: UTxO List */}
        {utxos.length > 0 && (
          <div>
            <label className="block text-sm font-medium text-dark-300 mb-2">
              3. Select UTxO to Burn
            </label>
            <div className="space-y-3">
              {utxos.map((utxo) => {
                const utxoKey = `${utxo.txHash}#${utxo.outputIndex}`;
                const isBurningThis = isBurning === utxoKey;

                return (
                  <div
                    key={utxoKey}
                    className="p-4 bg-dark-900 border border-dark-700 rounded-lg space-y-3"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex-1 min-w-0">
                        <p className="text-xs text-dark-400 mb-1">UTxO Reference:</p>
                        <code className="text-xs text-primary-400 break-all">
                          {utxo.txHash.substring(0, 16)}...#{utxo.outputIndex}
                        </code>
                      </div>
                      <div className="ml-4 text-right">
                        <p className="text-xs text-dark-400">Available:</p>
                        <p className="text-sm font-bold text-white">{utxo.tokenAmount}</p>
                      </div>
                    </div>

                    <div className="space-y-2">
                      <div className="flex gap-2">
                        {isFes ? (
                          /* FES: full-amount wipe indicator (no partial burns allowed) */
                          <div className="flex-1 px-3 py-2 bg-dark-800 border border-dark-700 rounded
                            text-sm text-orange-300 flex items-center">
                            Will wipe: <span className="font-bold ml-1">{utxo.tokenAmount}</span> tokens
                          </div>
                        ) : (
                          /* Other substandards: partial amount input with Half/Max buttons */
                          <div className="flex-1 relative">
                            <input
                              type="number"
                              placeholder="Amount to burn"
                              value={burnAmounts[utxoKey] || ""}
                              onChange={(e) => setBurnAmounts({
                                ...burnAmounts,
                                [utxoKey]: e.target.value
                              })}
                              className="w-full px-3 py-2 bg-dark-800 border border-dark-700 rounded
                                text-white text-sm focus:outline-none focus:ring-2 focus:ring-orange-500"
                              disabled={step === "signing"}
                            />
                            <div className="absolute right-2 top-1/2 -translate-y-1/2 flex gap-1">
                              <button
                                type="button"
                                onClick={() => {
                                  const halfAmount = (parseFloat(utxo.tokenAmount) / 2).toString();
                                  setBurnAmounts({
                                    ...burnAmounts,
                                    [utxoKey]: halfAmount
                                  });
                                }}
                                disabled={step === "signing"}
                                className="px-2 py-0.5 text-xs font-medium bg-dark-700 hover:bg-dark-600
                                  text-primary-400 rounded border border-dark-600 hover:border-primary-500
                                  transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                              >
                                HALF
                              </button>
                              <button
                                type="button"
                                onClick={() => {
                                  setBurnAmounts({
                                    ...burnAmounts,
                                    [utxoKey]: utxo.tokenAmount
                                  });
                                }}
                                disabled={step === "signing"}
                                className="px-2 py-0.5 text-xs font-medium bg-dark-700 hover:bg-dark-600
                                  text-primary-400 rounded border border-dark-600 hover:border-primary-500
                                  transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                              >
                                MAX
                              </button>
                            </div>
                          </div>
                        )}
                        <Button
                          onClick={() => handleBurnUtxo(utxo)}
                          variant="danger"
                          size="sm"
                          disabled={step === "signing" || (!isFes && !burnAmounts[utxoKey])}
                          className="flex items-center gap-2"
                        >
                          {isBurningThis ? (
                            <>
                              <Loader2 className="h-4 w-4 animate-spin" />
                              {isFes ? "Wiping..." : "Burning..."}
                            </>
                          ) : (
                            <>
                              <Flame className="h-4 w-4" />
                              {isFes ? "Wipe" : "Burn"}
                            </>
                          )}
                        </Button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
