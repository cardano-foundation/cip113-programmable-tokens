"use client";

import { useState, useCallback } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { CopyButton } from '@/components/ui/copy-button';
import { useToast } from '@/components/ui/use-toast';
import { useProtocolVersion } from '@/contexts/protocol-version-context';
import { initBlacklist } from '@/lib/api/compliance';
import type { StepComponentProps, BlacklistInitResult, TokenDetailsData } from '@/types/registration';

interface InitBlacklistStepProps extends StepComponentProps<Record<string, unknown>, BlacklistInitResult> {}

type InitStatus = 'idle' | 'building' | 'signing' | 'submitting' | 'success' | 'error';

export function InitBlacklistStep({
  onComplete,
  onError,
  onBack,
  isProcessing,
  setProcessing,
  wizardState,
}: InitBlacklistStepProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();

  const [status, setStatus] = useState<InitStatus>('idle');
  const [errorMessage, setErrorMessage] = useState('');
  const [blacklistNodePolicyId, setBlacklistNodePolicyId] = useState('');
  const [txHash, setTxHash] = useState('');

  // Get token details from previous step
  const tokenDetails = wizardState.stepStates['token-details']?.data as Partial<TokenDetailsData> | undefined;

  const handleInitBlacklist = useCallback(async () => {
    if (!connected || !wallet) {
      onError('Wallet not connected');
      return;
    }

    try {
      setProcessing(true);
      setStatus('building');
      setErrorMessage('');

      // Get wallet address for admin
      const addresses = await wallet.getUsedAddresses();
      if (!addresses?.[0]) {
        throw new Error('No wallet address found');
      }
      const adminAddress = addresses[0];

      showToast({
        title: 'Building Transaction',
        description: 'Preparing blacklist initialization...',
        variant: 'default',
      });

      // Call the blacklist init API with substandardId
      // The blacklist is initialized before the token is registered,
      // so we pass the substandard ID instead of a policy ID
      const response = await initBlacklist(
        {
          substandardId: 'freeze-and-seize',
          adminAddress,
          feePayerAddress: adminAddress, // Same wallet pays for tx and manages blacklist
        },
        selectedVersion?.txHash
      );

      // Backend returns 'policyId' for the blacklist node
      setBlacklistNodePolicyId(response.policyId);

      setStatus('signing');
      showToast({
        title: 'Sign Transaction',
        description: 'Please sign the blacklist initialization transaction',
        variant: 'default',
      });

      // Sign the transaction
      const signedTx = await wallet.signTx(response.unsignedCborTx, true);

      setStatus('submitting');

      // Submit the transaction
      const hash = await wallet.submitTx(signedTx);
      setTxHash(hash);

      setStatus('success');
      showToast({
        title: 'Blacklist Initialized',
        description: 'Blacklist node created successfully',
        variant: 'success',
      });

      // Complete the step with the blacklist node policy ID
      onComplete({
        stepId: 'init-blacklist',
        data: {
          blacklistNodePolicyId: response.policyId,
          txHash: hash,
        },
        txHash: hash,
        completedAt: Date.now(),
      });
    } catch (error) {
      setStatus('error');
      const message = error instanceof Error ? error.message : 'Failed to initialize blacklist';
      setErrorMessage(message);

      if (message.toLowerCase().includes('user declined') ||
          message.toLowerCase().includes('user rejected')) {
        showToast({
          title: 'Transaction Cancelled',
          description: 'You cancelled the transaction',
          variant: 'default',
        });
      } else {
        showToast({
          title: 'Initialization Failed',
          description: message,
          variant: 'error',
        });
        onError(message);
      }
    } finally {
      setProcessing(false);
    }
  }, [connected, wallet, selectedVersion, onComplete, onError, setProcessing, showToast]);

  const getStatusMessage = () => {
    switch (status) {
      case 'building':
        return 'Building blacklist initialization transaction...';
      case 'signing':
        return 'Waiting for wallet signature...';
      case 'submitting':
        return 'Submitting transaction to blockchain...';
      case 'success':
        return 'Blacklist initialized successfully!';
      case 'error':
        return errorMessage || 'Initialization failed';
      default:
        return 'Ready to initialize blacklist';
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">Initialize Blacklist</h3>
        <p className="text-dark-300 text-sm">
          The freeze-and-seize substandard requires a blacklist to track frozen addresses.
          This step creates the blacklist node on-chain.
        </p>
      </div>

      {/* Info Card */}
      <Card className="p-4 bg-orange-500/10 border-orange-500/30">
        <div className="flex items-start gap-3">
          <svg className="w-5 h-5 text-orange-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div>
            <p className="text-orange-300 font-medium text-sm">Compliance Feature</p>
            <p className="text-orange-200/70 text-sm mt-1">
              This will create a blacklist node that allows you to freeze addresses and seize tokens from frozen addresses.
            </p>
          </div>
        </div>
      </Card>

      {/* Token Details Summary */}
      {tokenDetails && (
        <Card className="p-4 space-y-2">
          <h4 className="font-medium text-white text-sm">Token Summary</h4>
          <div className="grid grid-cols-2 gap-2 text-sm">
            <div>
              <span className="text-dark-400">Token Name</span>
              <p className="text-white">{tokenDetails.assetName || '-'}</p>
            </div>
            <div>
              <span className="text-dark-400">Initial Supply</span>
              <p className="text-white">
                {tokenDetails.quantity ? BigInt(tokenDetails.quantity).toLocaleString() : '-'}
              </p>
            </div>
          </div>
        </Card>
      )}

      {/* Status Display */}
      {status !== 'idle' && (
        <Card className="p-6 text-center space-y-4">
          {/* Spinner or Icon */}
          <div className="flex justify-center">
            {status === 'building' || status === 'signing' || status === 'submitting' ? (
              <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
            ) : status === 'success' ? (
              <div className="w-12 h-12 rounded-full bg-green-500/20 flex items-center justify-center">
                <svg className="w-6 h-6 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              </div>
            ) : status === 'error' ? (
              <div className="w-12 h-12 rounded-full bg-red-500/20 flex items-center justify-center">
                <svg className="w-6 h-6 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </div>
            ) : null}
          </div>

          {/* Status Message */}
          <p className={`font-medium ${
            status === 'success' ? 'text-green-400' :
            status === 'error' ? 'text-red-400' :
            'text-dark-300'
          }`}>
            {getStatusMessage()}
          </p>

          {/* Success Details */}
          {status === 'success' && blacklistNodePolicyId && (
            <div className="mt-4 space-y-3">
              <div className="p-3 bg-dark-800 rounded text-left">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-xs text-dark-400">Blacklist Node Policy ID</span>
                  <CopyButton value={blacklistNodePolicyId} />
                </div>
                <p className="text-sm text-orange-400 font-mono break-all">{blacklistNodePolicyId}</p>
              </div>

              {txHash && (
                <div className="p-3 bg-dark-800 rounded text-left">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs text-dark-400">Transaction Hash</span>
                    <CopyButton value={txHash} />
                  </div>
                  <p className="text-sm text-primary-400 font-mono break-all">{txHash}</p>
                </div>
              )}
            </div>
          )}
        </Card>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        {onBack && status !== 'success' && (
          <Button
            variant="outline"
            onClick={onBack}
            disabled={isProcessing || ['building', 'signing', 'submitting'].includes(status)}
          >
            Back
          </Button>
        )}

        {status === 'idle' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleInitBlacklist}
            disabled={isProcessing || !connected}
          >
            Initialize Blacklist
          </Button>
        )}

        {status === 'error' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleInitBlacklist}
            disabled={isProcessing || !connected}
          >
            Retry
          </Button>
        )}

        {status === 'success' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={() => {
              // Already completed via onComplete, this is just for UX
            }}
            disabled
          >
            Continuing...
          </Button>
        )}
      </div>

      {!connected && (
        <p className="text-sm text-center text-dark-400">
          Connect your wallet to continue
        </p>
      )}
    </div>
  );
}
