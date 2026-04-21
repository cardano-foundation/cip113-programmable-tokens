"use client";

import { useState } from 'react';
import { useWallet } from '@/hooks/use-wallet';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { useToast } from '@/components/ui/use-toast';
import { ArrowRight, Send } from 'lucide-react';
import { truncateAddress } from '@/lib/utils/format';

interface TransferPreviewProps {
  unsignedCborTx: string;
  unit: string;
  quantity: string;
  recipientAddress: string;
  onSuccess: (txHash: string) => void;
  onCancel: () => void;
}

import { decodeAssetNameDisplay } from '@/lib/utils/cip68';

// Helper to decode asset name from unit, stripping CIP-67 prefix if present
function getAssetNameFromUnit(unit: string): string {
  if (unit.length <= 56) return unit;
  const assetNameHex = unit.substring(56);
  if (!assetNameHex) return unit;
  return decodeAssetNameDisplay(assetNameHex);
}

export function TransferPreview({
  unsignedCborTx,
  unit,
  quantity,
  recipientAddress,
  onSuccess,
  onCancel,
}: TransferPreviewProps) {
  const { wallet } = useWallet();
  const { toast: showToast } = useToast();
  const [isSigning, setIsSigning] = useState(false);

  const handleSign = async () => {
    try {
      setIsSigning(true);

      // Sign the transaction
      const signedTx = await wallet.signTx(unsignedCborTx);

      // Submit the transaction
      const txHash = await wallet.submitTx(signedTx);

      showToast({
        title: 'Transfer Successful',
        description: `Transaction submitted: ${txHash.substring(0, 16)}...`,
        variant: 'success',
        duration: 8000,
      });

      onSuccess(txHash);
    } catch (error) {
      let errorMessage = 'Failed to sign or submit transaction';

      if (error instanceof Error) {
        errorMessage = error.message;
      }

      showToast({
        title: 'Transaction Failed',
        description: errorMessage,
        variant: 'error',
        duration: 6000,
      });

      console.error('Sign/submit error:', error);
    } finally {
      setIsSigning(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-2">
          <Send className="h-5 w-5 text-primary-500" />
          <CardTitle>Review Transfer</CardTitle>
        </div>
        <p className="text-sm text-dark-400 mt-2">
          Review the transfer details and sign the transaction
        </p>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Transfer Summary */}
        <div className="space-y-4">
          {/* Token Name */}
          <div className="flex justify-between items-start py-3 border-b border-dark-700">
            <span className="text-sm text-dark-400">Token</span>
            <div className="text-right">
              <p className="text-sm font-medium text-white">{getAssetNameFromUnit(unit)}</p>
              <p className="text-xs text-dark-500 font-mono mt-1">{truncateAddress(unit, 12, 12)}</p>
            </div>
          </div>

          {/* Quantity */}
          <div className="flex justify-between items-center py-3 border-b border-dark-700">
            <span className="text-sm text-dark-400">Quantity</span>
            <Badge variant="success" size="md">
              {quantity}
            </Badge>
          </div>

          {/* Recipient Address */}
          <div className="flex justify-between items-start py-3 border-b border-dark-700">
            <span className="text-sm text-dark-400">Recipient</span>
            <div className="text-right">
              <p className="text-sm font-mono text-white">{truncateAddress(recipientAddress)}</p>
            </div>
          </div>
        </div>

        {/* Visual Flow */}
        <div className="bg-dark-800 rounded-lg p-6">
          <div className="flex items-center justify-between">
            <div className="text-center flex-1">
              <p className="text-xs text-dark-400 mb-2">From</p>
              <Badge variant="default" size="md">Your Wallet</Badge>
            </div>
            <ArrowRight className="h-6 w-6 text-primary-500 mx-4" />
            <div className="text-center flex-1">
              <p className="text-xs text-dark-400 mb-2">To</p>
              <Badge variant="default" size="md">Recipient</Badge>
            </div>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex gap-3">
          <Button
            variant="secondary"
            onClick={onCancel}
            disabled={isSigning}
            className="flex-1"
          >
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleSign}
            isLoading={isSigning}
            disabled={isSigning}
            className="flex-1"
          >
            {isSigning ? 'Signing...' : 'Sign & Submit'}
          </Button>
        </div>

        {/* Info Note */}
        <div className="bg-primary-500/10 border border-primary-500/20 rounded-lg p-4">
          <p className="text-xs text-primary-300">
            <strong>Note:</strong> This will transfer {quantity} tokens to the recipient&apos;s programmable token address.
            The transaction will be validated by the on-chain transfer contract.
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
