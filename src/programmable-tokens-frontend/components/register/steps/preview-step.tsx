"use client";

import { useMemo } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { CopyButton } from '@/components/ui/copy-button';
import type { StepComponentProps, PreviewStepData, TokenDetailsData } from '@/types/registration';

interface PreviewStepProps extends StepComponentProps<PreviewStepData, PreviewStepData> {
  /** Unsigned transaction CBOR hex to display */
  unsignedCborTx?: string;
  /** Policy ID of the token being registered */
  policyId?: string;
}

export function PreviewStep({
  stepData,
  onComplete,
  onBack,
  isProcessing,
  wizardState,
  unsignedCborTx,
  policyId,
}: PreviewStepProps) {
  const { connected } = useWallet();

  // Get token details from wizard state
  const tokenDetails = useMemo(() => {
    const detailsState = wizardState.stepStates['token-details'];
    return (detailsState?.data || {}) as Partial<TokenDetailsData>;
  }, [wizardState.stepStates]);

  const handleConfirm = () => {
    onComplete({
      stepId: 'preview',
      data: { confirmed: true },
      completedAt: Date.now(),
    });
  };

  const truncateAddress = (addr: string | undefined) => {
    if (!addr) return 'Your wallet address';
    return `${addr.slice(0, 12)}...${addr.slice(-8)}`;
  };

  const truncateHex = (hex: string | undefined) => {
    if (!hex) return '';
    if (hex.length <= 32) return hex;
    return `${hex.slice(0, 16)}...${hex.slice(-16)}`;
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">Review Transaction</h3>
        <p className="text-dark-300 text-sm">
          Review the details before signing and submitting
        </p>
      </div>

      {/* Token Details Card */}
      <Card className="p-4 space-y-3">
        <h4 className="font-medium text-white">Token Details</h4>

        <div className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <span className="text-dark-400">Token Name</span>
            <p className="text-white font-medium">{tokenDetails.assetName || '-'}</p>
          </div>
          <div>
            <span className="text-dark-400">Initial Supply</span>
            <p className="text-white font-medium">
              {tokenDetails.quantity ? BigInt(tokenDetails.quantity).toLocaleString() : '-'}
            </p>
          </div>
          <div className="col-span-2">
            <span className="text-dark-400">Recipient</span>
            <p className="text-white font-medium">{truncateAddress(tokenDetails.recipientAddress)}</p>
          </div>
        </div>
      </Card>

      {/* Policy ID Card */}
      {policyId && (
        <Card className="p-4 space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="font-medium text-white">Policy ID</h4>
            <CopyButton value={policyId} />
          </div>
          <p className="text-sm text-primary-400 font-mono break-all">{policyId}</p>
        </Card>
      )}

      {/* Transaction CBOR Card */}
      {unsignedCborTx && (
        <Card className="p-4 space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="font-medium text-white">Transaction CBOR</h4>
            <CopyButton value={unsignedCborTx} />
          </div>
          <div className="p-3 bg-dark-800 rounded border border-dark-700 overflow-hidden">
            <p className="text-xs text-dark-400 font-mono truncate">
              {truncateHex(unsignedCborTx)}
            </p>
          </div>
          <p className="text-xs text-dark-500">
            {unsignedCborTx.length.toLocaleString()} characters
          </p>
        </Card>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        {onBack && (
          <Button
            variant="outline"
            onClick={onBack}
            disabled={isProcessing}
          >
            Back
          </Button>
        )}
        <Button
          variant="primary"
          className="flex-1"
          onClick={handleConfirm}
          disabled={isProcessing || !connected}
        >
          Sign & Submit
        </Button>
      </div>

      {!connected && (
        <p className="text-sm text-center text-dark-400">
          Connect your wallet to continue
        </p>
      )}
    </div>
  );
}
