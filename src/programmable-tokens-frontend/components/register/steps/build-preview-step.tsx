"use client";

import { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { CopyButton } from '@/components/ui/copy-button';
import { useToast } from '@/components/ui/use-toast';
import { useProtocolVersion } from '@/contexts/protocol-version-context';
import { registerToken, stringToHex } from '@/lib/api';
import { getPaymentKeyHash } from '@/lib/utils/address';
import type { DummyRegisterRequest, FreezeAndSeizeRegisterRequest } from '@/types/api';
import type {
  StepComponentProps,
  TokenDetailsData,
  BlacklistInitResult,
} from '@/types/registration';

interface BuildPreviewStepResult {
  policyId: string;
  unsignedCborTx: string;
}

interface BuildPreviewStepProps extends StepComponentProps<Record<string, unknown>, BuildPreviewStepResult> {
  flowId: string;
}

type StepPhase =
  | 'ready-to-build'   // Ready for user to click build
  | 'building'         // API call in progress
  | 'preview'          // Showing tx preview
  | 'error';           // Error state

export function BuildPreviewStep({
  onComplete,
  onError,
  onBack,
  isProcessing,
  setProcessing,
  wizardState,
  flowId,
}: BuildPreviewStepProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();

  // Phase management
  const [phase, setPhase] = useState<StepPhase>('ready-to-build');
  const [errorMessage, setErrorMessage] = useState('');

  // Build result state
  const [policyId, setPolicyId] = useState('');
  const [unsignedCborTx, setUnsignedCborTx] = useState('');

  // Prevent double API calls
  const isCallingApiRef = useRef(false);
  const hasStartedPollingRef = useRef(false);

  // Abort controller ref (kept for cleanup compatibility)
  const abortControllerRef = useRef<AbortController | null>(null);
  const cooldownIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Get token details from wizard state
  const tokenDetails = useMemo(() => {
    const detailsState = wizardState.stepStates['token-details'];
    return (detailsState?.data || {}) as Partial<TokenDetailsData>;
  }, [wizardState.stepStates]);

  // Get blacklist init result for F&S flow
  const blacklistInitResult = useMemo(() => {
    const initState = wizardState.stepStates['init-blacklist'];
    return initState?.result?.data as BlacklistInitResult | undefined;
  }, [wizardState.stepStates]);

  // Check if this is F&S flow
  const isFreezeAndSeize = flowId === 'freeze-and-seize';

  // Check if pre-registration step was completed (means we can skip blacklist tx polling)
  const preRegistrationCompleted = useMemo(() => {
    const preRegState = wizardState.stepStates['pre-registration'];
    return preRegState?.status === 'completed';
  }, [wizardState.stepStates]);

  // Check if we're coming back from a failed sign-submit step (UTXO error)
  const signSubmitError = useMemo(() => {
    const signSubmitState = wizardState.stepStates['sign-submit'];
    if (signSubmitState?.status === 'error') {
      const error = signSubmitState.error || '';
      const isUtxoError = error.toLowerCase().includes('utxo') || 
                         error.toLowerCase().includes('already been spent') ||
                         error.toLowerCase().includes('badinputsutxo');
      return isUtxoError;
    }
    return false;
  }, [wizardState.stepStates]);

  // Initialize phase - skip polling if pre-registration was completed
  // The pre-registration step already handles tx confirmation and cooldown
  useEffect(() => {
    // If coming back from UTXO error, reset and rebuild
    if (signSubmitError) {
      console.log('[BuildPreviewStep] Detected UTXO error from sign-submit step, resetting to rebuild');
      setPhase('ready-to-build');
      setPolicyId('');
      setUnsignedCborTx('');
      setErrorMessage('');
      return;
    }

    // If pre-registration was completed, go directly to ready-to-build
    if (preRegistrationCompleted) {
      console.log('[BuildPreviewStep] Pre-registration completed, skipping tx polling');
      setPhase('ready-to-build');
      return;
    }

    // For non-F&S flow without pre-registration, go to ready-to-build
    if (!isFreezeAndSeize) {
      setPhase('ready-to-build');
      return;
    }

    // Legacy flow: F&S without pre-registration step (shouldn't happen with new flow)
    // Go to ready-to-build as a fallback
    console.log('[BuildPreviewStep] Fallback: going to ready-to-build');
    setPhase('ready-to-build');

    // Cleanup
    return () => {
      console.log('[BuildPreviewStep] Cleanup running');
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
        abortControllerRef.current = null;
      }
      if (cooldownIntervalRef.current) {
        clearInterval(cooldownIntervalRef.current);
        cooldownIntervalRef.current = null;
      }
      hasStartedPollingRef.current = false;
    };
  }, [isFreezeAndSeize, preRegistrationCompleted, signSubmitError]);

  // Build transaction - only called on button click
  const handleBuildAndContinue = useCallback(async () => {
    // Prevent double calls
    if (isCallingApiRef.current) {
      return;
    }

    if (!connected || !wallet) {
      onError('Wallet not connected');
      return;
    }

    if (!tokenDetails.assetName || !tokenDetails.quantity) {
      onError('Token details missing');
      return;
    }

    if (isFreezeAndSeize && !blacklistInitResult?.blacklistNodePolicyId) {
      onError('Blacklist not initialized');
      return;
    }

    try {
      isCallingApiRef.current = true;
      setProcessing(true);
      setPhase('building');
      setErrorMessage('');

      // Get fee payer address
      const addresses = await wallet.getUsedAddresses();
      if (!addresses?.[0]) {
        throw new Error('No wallet address found');
      }
      const feePayerAddress = addresses[0];

      showToast({
        title: 'Building Transaction',
        description: 'Preparing registration transaction...',
        variant: 'default',
      });

      // Build request based on flow type
      let request: DummyRegisterRequest | FreezeAndSeizeRegisterRequest;

      if (isFreezeAndSeize) {
        const adminPubKeyHash = getPaymentKeyHash(feePayerAddress);
        request = {
          substandardId: 'freeze-and-seize',
          feePayerAddress,
          assetName: stringToHex(tokenDetails.assetName),
          quantity: tokenDetails.quantity,
          recipientAddress: tokenDetails.recipientAddress || '',
          adminPubKeyHash,
          blacklistNodePolicyId: blacklistInitResult!.blacklistNodePolicyId,
        };
      } else {
        request = {
          substandardId: 'dummy',
          feePayerAddress,
          assetName: stringToHex(tokenDetails.assetName),
          quantity: tokenDetails.quantity,
          recipientAddress: tokenDetails.recipientAddress || '',
        };
      }

      // Call backend to build registration transaction
      const response = await registerToken(request, selectedVersion?.txHash);

      setPolicyId(response.policyId);
      setUnsignedCborTx(response.unsignedCborTx);
      setPhase('preview');

      showToast({
        title: 'Transaction Built',
        description: 'Ready to sign and submit',
        variant: 'success',
      });
    } catch (error) {
      setPhase('error');
      const message = error instanceof Error ? error.message : 'Failed to build transaction';
      setErrorMessage(message);
      
      // Check if this is a "token already exists" error
      const isTokenExistsError = message.toLowerCase().includes('already exists') || 
                                 message.toLowerCase().includes('already been registered');
      
      // Check if this is a "Directory UTXO spent" error - backend will retry automatically,
      // but we should show a helpful message
      const isUtxoSpentError = message.toLowerCase().includes('directory utxo') ||
                                message.toLowerCase().includes('registry may have been updated') ||
                                message.toLowerCase().includes('already been spent');
      
      showToast({
        title: isTokenExistsError ? 'Token Already Exists' : 
               isUtxoSpentError ? 'Registry Updated' : 'Build Failed',
        description: isUtxoSpentError 
          ? 'The registry was updated. The backend will automatically retry. Please try building again.'
          : message,
        variant: isUtxoSpentError ? 'default' : 'error',
      });
      onError(message);
    } finally {
      setProcessing(false);
      isCallingApiRef.current = false;
    }
  }, [
    connected,
    wallet,
    tokenDetails,
    isFreezeAndSeize,
    blacklistInitResult,
    selectedVersion,
    onError,
    setProcessing,
    showToast,
  ]);

  // Complete step and move to sign-submit
  const handleComplete = useCallback(() => {
    if (!policyId || !unsignedCborTx) return;

    onComplete({
      stepId: 'build-preview',
      data: {
        policyId,
        unsignedCborTx,
      },
      completedAt: Date.now(),
    });
  }, [policyId, unsignedCborTx, onComplete]);

  // Retry after error
  const handleRetry = useCallback(() => {
    setPhase('ready-to-build');
    setErrorMessage('');
    setPolicyId('');
    setUnsignedCborTx('');
  }, []);

  const truncateHex = (hex: string) => {
    if (hex.length <= 32) return hex;
    return `${hex.slice(0, 16)}...${hex.slice(-16)}`;
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">
          {phase === 'preview' ? 'Review & Sign' : 'Complete Registration'}
        </h3>
        <p className="text-dark-300 text-sm">
          {phase === 'preview'
            ? 'Review the registration details and sign to complete'
            : 'Build and sign the registration transaction'}
        </p>
      </div>

      {/* Ready to Build State */}
      {phase === 'ready-to-build' && (
        <>
          {/* Token Details Summary */}
          <Card className="p-4 space-y-3">
            <h4 className="font-medium text-white">Registration Summary</h4>
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
              <div>
                <span className="text-dark-400">Substandard</span>
                <p className="text-white font-medium capitalize">{flowId}</p>
              </div>
              {tokenDetails.recipientAddress && (
                <div className="col-span-2">
                  <span className="text-dark-400">Recipient</span>
                  <p className="text-white font-medium text-sm truncate">
                    {tokenDetails.recipientAddress}
                  </p>
                </div>
              )}
            </div>
          </Card>

          {/* Blacklist Node (F&S only) */}
          {isFreezeAndSeize && blacklistInitResult?.blacklistNodePolicyId && (
            <Card className="p-4 space-y-2">
              <div className="flex items-center justify-between">
                <h4 className="font-medium text-white">Blacklist Node Policy ID</h4>
                <CopyButton value={blacklistInitResult.blacklistNodePolicyId} />
              </div>
              <p className="text-sm text-orange-400 font-mono break-all">
                {blacklistInitResult.blacklistNodePolicyId}
              </p>
              <p className="text-xs text-dark-500">
                This will be linked to your programmable token
              </p>
            </Card>
          )}

          <Card className="p-4 bg-blue-500/10 border-blue-500/30">
            <div className="flex items-start gap-3">
              <svg className="w-5 h-5 text-blue-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <div>
                <p className="text-blue-300 font-medium text-sm">Ready to Register</p>
                <p className="text-blue-200/70 text-sm mt-1">
                  Click the button below to build and sign your token registration transaction.
                </p>
              </div>
            </div>
          </Card>
        </>
      )}

      {/* Building State */}
      {phase === 'building' && (
        <Card className="p-6 text-center">
          <div className="flex justify-center mb-4">
            <div className="w-10 h-10 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <p className="text-dark-300">Building registration transaction...</p>
        </Card>
      )}

      {/* Error State */}
      {phase === 'error' && (
        <Card className="p-4 bg-red-500/10 border-red-500/30">
          <div className="flex items-start gap-3">
            <svg className="w-5 h-5 text-red-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div>
              <p className="text-red-400 font-medium">Failed to build transaction</p>
              <p className="text-red-300 text-sm mt-1">{errorMessage}</p>
            </div>
          </div>
        </Card>
      )}

      {/* Preview State - Show Transaction Details */}
      {phase === 'preview' && (
        <>
          <Card className="p-4 space-y-3">
            <h4 className="font-medium text-white">Token Details</h4>
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div>
                <span className="text-dark-400">Token Name</span>
                <p className="text-white font-medium">{tokenDetails.assetName}</p>
              </div>
              <div>
                <span className="text-dark-400">Initial Supply</span>
                <p className="text-white font-medium">
                  {BigInt(tokenDetails.quantity || '0').toLocaleString()}
                </p>
              </div>
              <div>
                <span className="text-dark-400">Substandard</span>
                <p className="text-white font-medium capitalize">{flowId}</p>
              </div>
            </div>
          </Card>

          <Card className="p-4 space-y-2">
            <div className="flex items-center justify-between">
              <h4 className="font-medium text-white">Token Policy ID</h4>
              <CopyButton value={policyId} />
            </div>
            <p className="text-sm text-primary-400 font-mono break-all">{policyId}</p>
          </Card>

          {isFreezeAndSeize && blacklistInitResult?.blacklistNodePolicyId && (
            <Card className="p-4 space-y-2">
              <div className="flex items-center justify-between">
                <h4 className="font-medium text-white">Blacklist Node</h4>
                <CopyButton value={blacklistInitResult.blacklistNodePolicyId} />
              </div>
              <p className="text-sm text-orange-400 font-mono break-all">
                {blacklistInitResult.blacklistNodePolicyId}
              </p>
            </Card>
          )}

          <Card className="p-4 space-y-2">
            <div className="flex items-center justify-between">
              <h4 className="font-medium text-white">Transaction</h4>
              <CopyButton value={unsignedCborTx} />
            </div>
            <div className="p-3 bg-dark-800 rounded border border-dark-700">
              <p className="text-xs text-dark-400 font-mono">
                {truncateHex(unsignedCborTx)}
              </p>
            </div>
            <p className="text-xs text-dark-500">
              {unsignedCborTx.length.toLocaleString()} characters
            </p>
          </Card>
        </>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        {onBack && phase !== 'preview' && (
          <Button
            variant="outline"
            onClick={onBack}
            disabled={isProcessing || phase === 'building'}
          >
            Back
          </Button>
        )}

        {phase === 'ready-to-build' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleBuildAndContinue}
            disabled={isProcessing || !connected}
          >
            Build Registration Transaction
          </Button>
        )}

        {phase === 'preview' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleComplete}
            disabled={isProcessing || !connected}
          >
            Sign & Complete Registration
          </Button>
        )}

        {phase === 'error' && (
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
