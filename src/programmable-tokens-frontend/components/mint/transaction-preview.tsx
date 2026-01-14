"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  CardFooter,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/use-toast";
import { hexToString } from "@/lib/api";

interface TransactionPreviewProps {
  unsignedTxCborHex: string;
  assetName: string;
  quantity: string;
  onSuccess: (txHash: string) => void;
  onCancel: () => void;
}

export function TransactionPreview({
  unsignedTxCborHex,
  assetName,
  quantity,
  onSuccess,
  onCancel,
}: TransactionPreviewProps) {
  const { wallet } = useWallet();
  const { toast: showToast } = useToast();
  const [isSigning, setIsSigning] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSign = async () => {
    try {
      setIsSigning(true);

      // Sign the transaction using Mesh SDK
      const signedTx = await wallet.signTx(unsignedTxCborHex);

      setIsSigning(false);
      setIsSubmitting(true);

      // Submit the signed transaction
      const txHash = await wallet.submitTx(signedTx);

      showToast({
        title: "Transaction Submitted",
        description: `Transaction hash: ${txHash.substring(0, 16)}...`,
        variant: "success",
      });

      onSuccess(txHash);
    } catch (error) {
      console.error("Error signing/submitting transaction:", error);
      showToast({
        title: "Transaction Failed",
        description:
          error instanceof Error
            ? error.message
            : "Failed to sign or submit transaction",
        variant: "error",
      });
    } finally {
      setIsSigning(false);
      setIsSubmitting(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle>Review Transaction</CardTitle>
          <Badge variant="warning" size="sm">
            Unsigned
          </Badge>
        </div>
        <CardDescription>
          Review the transaction details before signing
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Transaction Details */}
        <div className="space-y-3">
          <div className="flex justify-between items-start">
            <span className="text-sm text-dark-400">Token Name:</span>
            <div className="text-right">
              <p className="text-sm font-medium text-white">{assetName}</p>
              <p className="text-xs text-dark-500 font-mono">
                {hexToString(assetName)}
              </p>
            </div>
          </div>

          <div className="flex justify-between items-center">
            <span className="text-sm text-dark-400">Quantity:</span>
            <span className="text-sm font-medium text-white">
              {Number(quantity).toLocaleString()}
            </span>
          </div>

          <div className="flex justify-between items-start">
            <span className="text-sm text-dark-400">Transaction Type:</span>
            <Badge variant="info" size="sm">
              Token Minting
            </Badge>
          </div>
        </div>

        {/* Transaction CBOR Preview */}
        <div className="mt-4 p-3 bg-dark-800 rounded-lg border border-dark-700">
          <p className="text-xs text-dark-400 mb-2">Transaction CBOR (hex):</p>
          <div className="max-h-32 overflow-y-auto scrollbar-thin">
            <code className="text-xs text-dark-300 font-mono break-all">
              {unsignedTxCborHex}
            </code>
          </div>
          <p className="text-xs text-dark-500 mt-2">
            {unsignedTxCborHex.length} characters
          </p>
        </div>

        {/* Warning */}
        <div className="mt-4 p-3 bg-orange-500/10 border border-orange-500/20 rounded-lg">
          <p className="text-xs text-orange-300">
            <strong>Note:</strong> Please review the transaction carefully
            before signing. Once submitted to the blockchain, this action cannot
            be reversed.
          </p>
        </div>
      </CardContent>

      <CardFooter className="flex gap-3">
        <Button
          variant="secondary"
          onClick={onCancel}
          disabled={isSigning || isSubmitting}
          className="w-full"
        >
          Cancel
        </Button>
        <Button
          variant="primary"
          onClick={handleSign}
          isLoading={isSigning || isSubmitting}
          disabled={isSigning || isSubmitting}
          className="w-full"
        >
          {isSigning && "Signing..."}
          {isSubmitting && "Submitting..."}
          {!isSigning && !isSubmitting && "Sign & Submit"}
        </Button>
      </CardFooter>
    </Card>
  );
}
