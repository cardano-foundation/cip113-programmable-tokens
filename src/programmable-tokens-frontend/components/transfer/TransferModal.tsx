"use client";

import { useState, useEffect } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { X, Send, CheckCircle, ExternalLink } from "lucide-react";
import { cn } from "@/lib/utils";
import { transferToken } from "@/lib/api";
import { TransferTokenRequest, ParsedAsset } from "@/types/api";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { useToast } from "@/components/ui/use-toast";
import { getExplorerTxUrl } from "@/lib/utils";

interface TransferModalProps {
  isOpen: boolean;
  onClose: () => void;
  asset: ParsedAsset;
  senderAddress: string;
}

type TransferStep = "form" | "signing" | "success";

export function TransferModal({
  isOpen,
  onClose,
  asset,
  senderAddress,
}: TransferModalProps) {
  const { wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();
  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";

  const [step, setStep] = useState<TransferStep>("form");
  const [quantity, setQuantity] = useState("");
  const [recipientAddress, setRecipientAddress] = useState("");
  const [isBuilding, setIsBuilding] = useState(false);
  const [isSigning, setIsSigning] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);

  const [errors, setErrors] = useState({
    quantity: "",
    recipientAddress: "",
  });

  // Reset state when modal opens/closes
  useEffect(() => {
    if (isOpen) {
      setStep("form");
      setQuantity("");
      setRecipientAddress("");
      setTxHash(null);
      setErrors({ quantity: "", recipientAddress: "" });
    }
  }, [isOpen]);

  // Close on escape key
  useEffect(() => {
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen && step === "form") {
        onClose();
      }
    };
    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [isOpen, onClose, step]);

  const handleSetMax = () => {
    setQuantity(asset.amount);
    setErrors((prev) => ({ ...prev, quantity: "" }));
  };

  const validateForm = (): boolean => {
    const newErrors = {
      quantity: "",
      recipientAddress: "",
    };

    if (!quantity.trim()) {
      newErrors.quantity = "Quantity is required";
    } else if (!/^\d+$/.test(quantity)) {
      newErrors.quantity = "Quantity must be a positive number";
    } else if (BigInt(quantity) <= 0) {
      newErrors.quantity = "Quantity must be greater than 0";
    } else if (BigInt(quantity) > BigInt(asset.amount)) {
      newErrors.quantity = `Quantity exceeds balance (max: ${asset.amount})`;
    }

    if (!recipientAddress.trim()) {
      newErrors.recipientAddress = "Recipient address is required";
    } else if (!recipientAddress.startsWith("addr")) {
      newErrors.recipientAddress = "Invalid Cardano address format";
    } else if (recipientAddress === senderAddress) {
      newErrors.recipientAddress = "Cannot transfer to yourself";
    }

    setErrors(newErrors);
    return !Object.values(newErrors).some((error) => error !== "");
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validateForm()) {
      return;
    }

    try {
      setIsBuilding(true);

      // Build transfer transaction
      const request: TransferTokenRequest = {
        senderAddress,
        unit: asset.unit,
        quantity,
        recipientAddress: recipientAddress.trim(),
      };

      const unsignedCborTx = await transferToken(request, selectedVersion?.txHash);

      setIsBuilding(false);
      setStep("signing");
      setIsSigning(true);

      // Sign and submit transaction
      const signedTx = await wallet.signTx(unsignedCborTx);
      const submittedTxHash = await wallet.submitTx(signedTx);

      setTxHash(submittedTxHash);
      setStep("success");

      showToast({
        title: "Transfer Successful",
        description: `Transferred ${quantity} ${asset.assetName} tokens`,
        variant: "success",
      });
    } catch (error) {
      console.error("Transfer error:", error);

      let errorMessage = "Failed to transfer tokens";
      if (error instanceof Error) {
        if (error.message.includes("User declined")) {
          errorMessage = "Transaction was cancelled";
        } else {
          errorMessage = error.message;
        }
      }

      showToast({
        title: "Transfer Failed",
        description: errorMessage,
        variant: "error",
      });

      setStep("form");
    } finally {
      setIsBuilding(false);
      setIsSigning(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/70 backdrop-blur-sm"
        onClick={step === "form" ? onClose : undefined}
      />

      {/* Modal */}
      <div className="relative w-full max-w-md mx-4 bg-dark-800 border border-dark-700 rounded-xl shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-dark-700">
          <div className="flex items-center gap-3">
            <Send className="h-5 w-5 text-primary-500" />
            <h2 className="text-lg font-semibold text-white">Transfer Tokens</h2>
          </div>
          {step === "form" && (
            <button
              onClick={onClose}
              className="p-1 hover:bg-dark-700 rounded transition-colors"
            >
              <X className="h-5 w-5 text-dark-400 hover:text-white" />
            </button>
          )}
        </div>

        {/* Content */}
        <div className="p-6">
          {step === "form" && (
            <form onSubmit={handleSubmit} className="space-y-5">
              {/* Token Info */}
              <div className="px-4 py-3 bg-dark-900 rounded-lg">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-xs text-dark-400">Token</p>
                    <p className="text-sm font-medium text-white">{asset.assetName}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-xs text-dark-400">Available</p>
                    <p className="text-sm font-bold text-accent-400">{asset.amount}</p>
                  </div>
                </div>
                <p className="mt-2 text-xs text-dark-500 truncate" title={asset.policyId}>
                  Policy: {asset.policyId}
                </p>
              </div>

              {/* Quantity */}
              <div>
                <div className="flex items-center justify-between mb-2">
                  <label className="text-sm font-medium text-white">Amount</label>
                  <button
                    type="button"
                    onClick={handleSetMax}
                    disabled={isBuilding}
                    className="text-xs text-primary-400 hover:text-primary-300 transition-colors"
                  >
                    Max
                  </button>
                </div>
                <Input
                  type="number"
                  value={quantity}
                  onChange={(e) => {
                    setQuantity(e.target.value);
                    setErrors((prev) => ({ ...prev, quantity: "" }));
                  }}
                  placeholder="Enter amount"
                  disabled={isBuilding}
                  error={errors.quantity}
                />
              </div>

              {/* Recipient Address */}
              <div>
                <Input
                  label="Recipient Address"
                  value={recipientAddress}
                  onChange={(e) => {
                    setRecipientAddress(e.target.value);
                    setErrors((prev) => ({ ...prev, recipientAddress: "" }));
                  }}
                  placeholder="addr1..."
                  disabled={isBuilding}
                  error={errors.recipientAddress}
                />
              </div>

              {/* Submit Button */}
              <div className="flex gap-3 pt-2">
                <Button
                  type="button"
                  variant="ghost"
                  className="flex-1"
                  onClick={onClose}
                  disabled={isBuilding}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  variant="primary"
                  className="flex-1"
                  isLoading={isBuilding}
                  disabled={isBuilding}
                >
                  {isBuilding ? "Building..." : "Transfer"}
                </Button>
              </div>
            </form>
          )}

          {step === "signing" && (
            <div className="flex flex-col items-center py-8">
              <div className="h-12 w-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin mb-4" />
              <p className="text-white font-medium">
                {isSigning ? "Waiting for signature..." : "Building transaction..."}
              </p>
              <p className="text-sm text-dark-400 mt-2">
                Please confirm the transaction in your wallet
              </p>
            </div>
          )}

          {step === "success" && txHash && (
            <div className="flex flex-col items-center py-6">
              <div className="w-16 h-16 rounded-full bg-green-500/10 flex items-center justify-center mb-4">
                <CheckCircle className="h-8 w-8 text-green-500" />
              </div>
              <h3 className="text-lg font-semibold text-white mb-2">
                Transfer Complete!
              </h3>
              <p className="text-sm text-dark-400 text-center mb-4">
                Successfully transferred {quantity} {asset.assetName} tokens
              </p>

              <div className="w-full px-4 py-3 bg-dark-900 rounded-lg mb-4">
                <p className="text-xs text-dark-400 mb-1">Transaction Hash</p>
                <p className="text-xs text-primary-400 font-mono break-all">
                  {txHash}
                </p>
              </div>

              <div className="flex gap-3 w-full">
                <a
                  href={getExplorerTxUrl(network, txHash)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex-1"
                >
                  <Button variant="ghost" className="w-full">
                    <ExternalLink className="h-4 w-4 mr-2" />
                    View on Explorer
                  </Button>
                </a>
                <Button
                  variant="primary"
                  className="flex-1"
                  onClick={onClose}
                >
                  Done
                </Button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
