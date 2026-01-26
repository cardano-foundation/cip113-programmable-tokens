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
import { waitForTxConfirmation } from '@/lib/utils/tx-confirmation';
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
  | 'checking-tx'      // Polling Blockfrost for tx confirmation
  | 'backend-cooldown' // Tx confirmed, waiting for backend to process
  | 'ready-to-build'   // Ready for user to click build
  | 'building'         // API call in progress
  | 'preview'          // Showing tx preview
  | 'error';           // Error state

const BACKEND_COOLDOWN_SECONDS = 10;
const TX_POLL_INTERVAL = 10000; // 10 seconds
const TX_POLL_TIMEOUT = 300000; // 5 minutes

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
  const [phase, setPhase] = useState<StepPhase>('checking-tx');
  const [errorMessage, setErrorMessage] = useState('');

  // Tx confirmation state
  const [pollAttempt, setPollAttempt] = useState(0);
  const [txConfirmed, setTxConfirmed] = useState(false);

  // Backend cooldown state
  const [cooldownRemaining, setCooldownRemaining] = useState(0);
  const cooldownIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Build result state
  const [policyId, setPolicyId] = useState('');
  const [unsignedCborTx, setUnsignedCborTx] = useState('');

  // Prevent double API calls
  const isCallingApiRef = useRef(false);
  const hasStartedPollingRef = useRef(false);

  // Abort controller for tx confirmation polling
  const abortControllerRef = useRef<AbortController | null>(null);

  // Store callbacks in refs to avoid dependency issues in useEffect
  const showToastRef = useRef(showToast);
  const startBackendCooldownRef = useRef<(() => void) | null>(null);

  // Update showToast ref when it changes
  useEffect(() => {
    showToastRef.current = showToast;
  }, [showToast]);

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

  // Get the blacklist init tx hash
  const blacklistInitTxHash = useMemo(() => {
    const initState = wizardState.stepStates['init-blacklist'];
    return initState?.result?.txHash as string | undefined;
  }, [wizardState.stepStates]);

  // Start backend cooldown after tx is confirmed
  const startBackendCooldown = useCallback(() => {
    setPhase('backend-cooldown');
    setCooldownRemaining(BACKEND_COOLDOWN_SECONDS);

    cooldownIntervalRef.current = setInterval(() => {
      setCooldownRemaining(prev => {
        if (prev <= 1) {
          if (cooldownIntervalRef.current) {
            clearInterval(cooldownIntervalRef.current);
            cooldownIntervalRef.current = null;
          }
          setPhase('ready-to-build');
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  }, []);

  // Update startBackendCooldown ref after it's defined
  useEffect(() => {
    startBackendCooldownRef.current = startBackendCooldown;
  }, [startBackendCooldown]);

  // Poll for tx confirmation (F&S flow only)
  // Using refs for callbacks to avoid re-running effect on callback changes
  useEffect(() => {
    // Only for F&S flow
    if (!isFreezeAndSeize) {
      setPhase('ready-to-build');
      return;
    }

    // Need blacklist init tx hash to poll
    if (!blacklistInitTxHash) {
      console.log('[BuildPreviewStep] No blacklist tx hash, skipping confirmation check');
      setPhase('ready-to-build');
      return;
    }

    // Don't start polling twice
    if (hasStartedPollingRef.current) {
      console.log('[BuildPreviewStep] Already started polling, skipping');
      return;
    }
    hasStartedPollingRef.current = true;

    console.log('[BuildPreviewStep] Starting tx confirmation polling for:', blacklistInitTxHash);

    // Create abort controller
    abortControllerRef.current = new AbortController();

    // Start polling
    setPhase('checking-tx');
    setPollAttempt(0);

    waitForTxConfirmation(blacklistInitTxHash, {
      pollInterval: TX_POLL_INTERVAL,
      timeout: TX_POLL_TIMEOUT,
      signal: abortControllerRef.current.signal,
      onPoll: (attempt) => {
        console.log(`[BuildPreviewStep] Poll attempt ${attempt}`);
        setPollAttempt(attempt);
      },
      onConfirmed: () => {
        console.log('[BuildPreviewStep] Tx confirmed!');
        setTxConfirmed(true);
        showToastRef.current({
          title: 'Transaction Confirmed',
          description: 'Blacklist initialization confirmed on-chain',
          variant: 'success',
        });
        // Start backend cooldown
        startBackendCooldownRef.current?.();
      },
    }).catch((error) => {
      if (error.message === 'Aborted') {
        console.log('[BuildPreviewStep] Polling was aborted');
        return; // Ignore abort errors
      }
      console.error('[BuildPreviewStep] Tx confirmation error:', error);
      // On timeout/error, proceed anyway with a warning
      showToastRef.current({
        title: 'Confirmation Check Failed',
        description: 'Could not verify transaction. Proceeding anyway...',
        variant: 'warning',
      });
      startBackendCooldownRef.current?.();
    });

    // Cleanup - reset state so effect can restart (needed for React Strict Mode)
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
      // Reset the polling guard so effect can restart after cleanup
      hasStartedPollingRef.current = false;
    };
  }, [isFreezeAndSeize, blacklistInitTxHash]); // Minimal dependencies - callbacks use refs

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
      showToast({
        title: 'Build Failed',
        description: message,
        variant: 'error',
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

      {/* Checking TX Confirmation State (F&S only) */}
      {phase === 'checking-tx' && isFreezeAndSeize && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 border-4 border-orange-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <div>
            <p className="text-orange-400 font-medium">Waiting for Transaction Confirmation</p>
            <p className="text-dark-400 text-sm mt-2">
              Checking if blacklist initialization is confirmed on-chain...
            </p>
          </div>
          <div className="text-sm text-dark-500">
            Poll attempt: {pollAttempt} (checking every 10s)
          </div>
          {blacklistInitTxHash && (
            <div className="text-xs text-dark-600 font-mono truncate px-4">
              Tx: {blacklistInitTxHash.slice(0, 20)}...
            </div>
          )}
        </Card>
      )}

      {/* Backend Cooldown State (F&S only) */}
      {phase === 'backend-cooldown' && isFreezeAndSeize && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 rounded-full bg-green-500/20 flex items-center justify-center">
              <svg className="w-6 h-6 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
          </div>
          <div>
            <p className="text-green-400 font-medium">Transaction Confirmed!</p>
            <p className="text-dark-400 text-sm mt-2">
              Waiting for backend to process the transaction...
            </p>
          </div>
          <div className="text-2xl font-bold text-white">
            {cooldownRemaining}s
          </div>
        </Card>
      )}

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
            disabled={isProcessing || phase === 'building' || phase === 'checking-tx' || phase === 'backend-cooldown'}
          >
            Back
          </Button>
        )}

        {phase === 'checking-tx' && (
          <Button
            variant="primary"
            className="flex-1"
            disabled
          >
            Checking confirmation...
          </Button>
        )}

        {phase === 'backend-cooldown' && (
          <Button
            variant="primary"
            className="flex-1"
            disabled
          >
            Processing... ({cooldownRemaining}s)
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
