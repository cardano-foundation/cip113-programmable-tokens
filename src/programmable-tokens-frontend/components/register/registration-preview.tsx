"use client";

import { useState } from 'react';
import { useWallet } from '@/hooks/use-wallet';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useToast } from '@/components/ui/use-toast';

interface RegistrationPreviewProps {
  unsignedCborTx: string;
  policyId: string;
  tokenName: string;
  quantity: string;
  recipientAddress?: string;
  onSuccess: (txHash: string) => void;
  onCancel: () => void;
}

export function RegistrationPreview({
  unsignedCborTx,
  policyId,
  tokenName,
  quantity,
  recipientAddress,
  onSuccess,
  onCancel,
}: RegistrationPreviewProps) {
  const { wallet } = useWallet();
  const { toast: showToast } = useToast();
  const [isSigning, setIsSigning] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSign = async () => {
    try {
      setIsSigning(true);

      // Sign the transaction using Mesh SDK
      const signedTx = await wallet.signTx(unsignedCborTx, false);

      setIsSigning(false);
      setIsSubmitting(true);

      // Submit the signed transaction
      const txHash = await wallet.submitTx(signedTx);

      showToast({
        title: 'Registration Submitted',
        description: `Transaction hash: ${txHash.substring(0, 16)}...`,
        variant: 'success',
      });

      onSuccess(txHash);
    } catch (error) {
      console.error('Error signing/submitting transaction:', error);
      showToast({
        title: 'Transaction Failed',
        description: error instanceof Error ? error.message : 'Failed to sign or submit transaction',
        variant: 'error',
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
          <CardTitle>Review Registration</CardTitle>
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
            <span className="text-sm text-dark-400">Policy ID:</span>
            <div className="text-right max-w-md">
              <p className="text-sm font-medium text-white font-mono break-all">
                {policyId}
              </p>
            </div>
          </div>

          <div className="flex justify-between items-start">
            <span className="text-sm text-dark-400">Token Name:</span>
            <p className="text-sm font-medium text-white">
              {tokenName}
            </p>
          </div>

          <div className="flex justify-between items-start">
            <span className="text-sm text-dark-400">Quantity:</span>
            <p className="text-sm font-medium text-white">
              {quantity}
            </p>
          </div>

          {recipientAddress && (
            <div className="flex justify-between items-start">
              <span className="text-sm text-dark-400">Recipient:</span>
              <div className="text-right max-w-md">
                <p className="text-sm font-medium text-white font-mono break-all">
                  {recipientAddress}
                </p>
              </div>
            </div>
          )}

          <div className="flex justify-between items-start">
            <span className="text-sm text-dark-400">Transaction Type:</span>
            <Badge variant="info" size="sm">
              Token Registration
            </Badge>
          </div>
        </div>

        {/* Transaction CBOR Preview */}
        <div className="mt-4 p-3 bg-dark-800 rounded-lg border border-dark-700">
          <p className="text-xs text-dark-400 mb-2">Transaction CBOR (hex):</p>
          <div className="max-h-32 overflow-y-auto scrollbar-thin">
            <code className="text-xs text-dark-300 font-mono break-all">
              {unsignedCborTx}
            </code>
          </div>
          <p className="text-xs text-dark-500 mt-2">
            {unsignedCborTx.length} characters
          </p>
        </div>

        {/* Warning */}
        <div className="mt-4 p-3 bg-orange-500/10 border border-orange-500/20 rounded-lg">
          <p className="text-xs text-orange-300">
            <strong>Note:</strong> This transaction registers your programmable token policy on-chain.
            Once submitted, you can mint tokens using this policy.
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
          {isSigning && 'Signing...'}
          {isSubmitting && 'Submitting...'}
          {!isSigning && !isSubmitting && 'Sign & Submit'}
        </Button>
      </CardFooter>
    </Card>
  );
}
