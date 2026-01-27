"use client";

import { useState, useEffect, useCallback, useRef } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import type { StepComponentProps, SignSubmitResult } from '@/types/registration';
import { useToast } from '@/components/ui/use-toast';

interface SignSubmitStepProps extends StepComponentProps<Record<string, unknown>, SignSubmitResult> {
  /** Unsigned transaction CBOR hex */
  unsignedCborTx: string;
  /** Policy ID of the registered token */
  policyId: string;
  /** Optional callback when signing starts */
  onSigningStart?: () => void;
}

type SigningStatus = 'idle' | 'signing' | 'submitting' | 'success' | 'error';

export function SignSubmitStep({
  onComplete,
  onError,
  onBack,
  isProcessing,
  setProcessing,
  unsignedCborTx,
  policyId,
  onSigningStart,
}: SignSubmitStepProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();
  const [status, setStatus] = useState<SigningStatus>('idle');
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [txHash, setTxHash] = useState<string>('');

  // Guards against double execution
  const hasStartedRef = useRef(false);
  const isSubmittingRef = useRef(false);

  // Store callbacks in refs to avoid dependency issues
  const onCompleteRef = useRef(onComplete);
  const onErrorRef = useRef(onError);
  const showToastRef = useRef(showToast);
  const onSigningStartRef = useRef(onSigningStart);

  // Update refs when callbacks change
  useEffect(() => {
    onCompleteRef.current = onComplete;
    onErrorRef.current = onError;
    showToastRef.current = showToast;
    onSigningStartRef.current = onSigningStart;
  }, [onComplete, onError, showToast, onSigningStart]);

  const handleSignAndSubmit = useCallback(async () => {
    // Strict guard against any double execution
    if (isSubmittingRef.current) {
      console.log('[SignSubmitStep] Already submitting, ignoring duplicate call');
      return;
    }

    if (!connected || !wallet || !unsignedCborTx) {
      onErrorRef.current('Wallet not connected or transaction not ready');
      return;
    }

    try {
      isSubmittingRef.current = true;
      setProcessing(true);
      setStatus('signing');
      setErrorMessage('');
      onSigningStartRef.current?.();

      // Sign the transaction
      const signedTx = await wallet.signTx(unsignedCborTx, true);

      setStatus('submitting');

      // Submit the transaction
      const hash = await wallet.submitTx(signedTx);

      setStatus('success');
      setTxHash(hash);

      showToastRef.current({
        title: 'Transaction Submitted',
        description: `Transaction submitted successfully`,
        variant: 'success',
      });

      // Complete the step with result
      onCompleteRef.current({
        stepId: 'sign-submit',
        data: {
          policyId,
          txHash: hash,
          unsignedCborTx,
        },
        txHash: hash,
        completedAt: Date.now(),
      });
    } catch (error) {
      setStatus('error');
      isSubmittingRef.current = false; // Allow retry on error
      const message = error instanceof Error ? error.message : 'Failed to sign or submit transaction';
      setErrorMessage(message);

      // Check for user rejection
      if (message.toLowerCase().includes('user declined') ||
          message.toLowerCase().includes('user rejected') ||
          message.toLowerCase().includes('cancelled')) {
        showToastRef.current({
          title: 'Transaction Cancelled',
          description: 'You cancelled the transaction signing',
          variant: 'default',
        });
      } else {
        showToastRef.current({
          title: 'Transaction Failed',
          description: message,
          variant: 'error',
        });
        onErrorRef.current(message);
      }
    } finally {
      setProcessing(false);
    }
  }, [connected, wallet, unsignedCborTx, policyId, setProcessing]);

  // Auto-start signing when component mounts - with strict guard
  useEffect(() => {
    // Only run once, ever
    if (hasStartedRef.current) {
      return;
    }

    if (status === 'idle' && connected && unsignedCborTx) {
      hasStartedRef.current = true;
      handleSignAndSubmit();
    }
  }, [status, connected, unsignedCborTx, handleSignAndSubmit]);

  const handleRetry = useCallback(() => {
    // Reset guards for retry
    isSubmittingRef.current = false;
    setStatus('idle');
    setErrorMessage('');
    // Don't reset hasStartedRef - we'll trigger manually
    handleSignAndSubmit();
  }, [handleSignAndSubmit]);

  const getStatusMessage = () => {
    switch (status) {
      case 'signing':
        return 'Waiting for wallet signature...';
      case 'submitting':
        return 'Submitting transaction to blockchain...';
      case 'success':
        return 'Transaction submitted successfully!';
      case 'error':
        return errorMessage || 'Transaction failed';
      default:
        return 'Preparing transaction...';
    }
  };

  const getStatusColor = () => {
    switch (status) {
      case 'success':
        return 'text-green-400';
      case 'error':
        return 'text-red-400';
      default:
        return 'text-dark-300';
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">Sign & Submit</h3>
        <p className="text-dark-300 text-sm">
          Sign the transaction with your wallet to register the token
        </p>
      </div>

      {/* Status Card */}
      <Card className="p-6 text-center space-y-4">
        {/* Spinner or Icon */}
        <div className="flex justify-center">
          {status === 'signing' || status === 'submitting' ? (
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
          ) : (
            <div className="w-12 h-12 border-4 border-dark-600 rounded-full" />
          )}
        </div>

        {/* Status Message */}
        <p className={`font-medium ${getStatusColor()}`}>
          {getStatusMessage()}
        </p>

        {/* Transaction Hash on Success */}
        {status === 'success' && txHash && (
          <div className="mt-4 p-3 bg-dark-800 rounded">
            <p className="text-xs text-dark-400 mb-1">Transaction Hash</p>
            <p className="text-sm text-primary-400 font-mono break-all">{txHash}</p>
          </div>
        )}
      </Card>

      {/* Actions */}
      <div className="flex gap-3">
        {onBack && status !== 'success' && (
          <Button
            variant="outline"
            onClick={onBack}
            disabled={isProcessing || status === 'signing' || status === 'submitting'}
          >
            Back
          </Button>
        )}

        {status === 'error' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleRetry}
            disabled={isProcessing || !connected}
          >
            Retry
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
