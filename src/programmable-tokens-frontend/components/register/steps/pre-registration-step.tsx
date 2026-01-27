"use client";

import { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { CopyButton } from '@/components/ui/copy-button';
import { useToast } from '@/components/ui/use-toast';
import { useProtocolVersion } from '@/contexts/protocol-version-context';
import { preRegisterToken, stringToHex } from '@/lib/api';
import { getPaymentKeyHash } from '@/lib/utils/address';
import { waitForTxConfirmation } from '@/lib/utils/tx-confirmation';
import type { DummyRegisterRequest, FreezeAndSeizeRegisterRequest } from '@/types/api';
import type {
  StepComponentProps,
  TokenDetailsData,
  BlacklistInitResult,
} from '@/types/registration';

interface PreRegistrationStepResult {
  stakeAddresses: string[];
  txHash?: string;
}

interface PreRegistrationStepProps extends StepComponentProps<Record<string, unknown>, PreRegistrationStepResult> {
  flowId: string;
}

type StepPhase =
  | 'checking-prereqs'    // Initial check (for F&S: wait for blacklist init)
  | 'backend-cooldown'    // After prereq tx confirmed, 10s wait
  | 'calling-api'         // Calling pre-register API
  | 'already-registered'  // All addresses registered (no tx needed)
  | 'signing'             // Waiting for wallet signature
  | 'submitting'          // Submitting to blockchain
  | 'polling'             // Waiting for tx confirmation
  | 'post-tx-cooldown'    // 10s cooldown after tx confirmed
  | 'complete'            // Ready to proceed
  | 'error';              // Error state

const BACKEND_COOLDOWN_SECONDS = 10;
const TX_POLL_INTERVAL = 10000; // 10 seconds
const TX_POLL_TIMEOUT = 300000; // 5 minutes

export function PreRegistrationStep({
  onComplete,
  onError,
  onBack,
  isProcessing,
  setProcessing,
  wizardState,
  flowId,
}: PreRegistrationStepProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();

  // Phase management
  const [phase, setPhase] = useState<StepPhase>('checking-prereqs');
  const [errorMessage, setErrorMessage] = useState('');

  // Tx confirmation state
  const [pollAttempt, setPollAttempt] = useState(0);

  // Cooldown state
  const [cooldownRemaining, setCooldownRemaining] = useState(0);
  const cooldownIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Pre-registration result state
  const [stakeAddresses, setStakeAddresses] = useState<string[]>([]);
  const [txHash, setTxHash] = useState('');

  // Prevent double API calls
  const isCallingApiRef = useRef(false);
  const hasStartedRef = useRef(false);

  // Abort controller for tx confirmation polling
  const abortControllerRef = useRef<AbortController | null>(null);

  // Store callbacks in refs to avoid dependency issues in useEffect
  const showToastRef = useRef(showToast);

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

  // Get the blacklist init tx hash for F&S flow
  const blacklistInitTxHash = useMemo(() => {
    const initState = wizardState.stepStates['init-blacklist'];
    return initState?.result?.txHash as string | undefined;
  }, [wizardState.stepStates]);

  // Start cooldown timer
  const startCooldown = useCallback((nextPhase: StepPhase) => {
    setCooldownRemaining(BACKEND_COOLDOWN_SECONDS);

    cooldownIntervalRef.current = setInterval(() => {
      setCooldownRemaining(prev => {
        if (prev <= 1) {
          if (cooldownIntervalRef.current) {
            clearInterval(cooldownIntervalRef.current);
            cooldownIntervalRef.current = null;
          }
          setPhase(nextPhase);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  }, []);

  // Call pre-register API
  const callPreRegisterApi = useCallback(async () => {
    if (isCallingApiRef.current) return;
    if (!connected || !wallet) {
      onError('Wallet not connected');
      return;
    }

    try {
      isCallingApiRef.current = true;
      setProcessing(true);
      setPhase('calling-api');

      // Get fee payer address
      const addresses = await wallet.getUsedAddresses();
      if (!addresses?.[0]) {
        throw new Error('No wallet address found');
      }
      const feePayerAddress = addresses[0];

      // Build request based on flow type
      let request: DummyRegisterRequest | FreezeAndSeizeRegisterRequest;

      if (isFreezeAndSeize) {
        if (!blacklistInitResult?.blacklistNodePolicyId) {
          throw new Error('Blacklist not initialized');
        }
        const adminPubKeyHash = getPaymentKeyHash(feePayerAddress);
        request = {
          substandardId: 'freeze-and-seize',
          feePayerAddress,
          assetName: stringToHex(tokenDetails.assetName || ''),
          quantity: tokenDetails.quantity || '0',
          recipientAddress: tokenDetails.recipientAddress || '',
          adminPubKeyHash,
          blacklistNodePolicyId: blacklistInitResult.blacklistNodePolicyId,
        };
      } else {
        request = {
          substandardId: 'dummy',
          feePayerAddress,
          assetName: stringToHex(tokenDetails.assetName || ''),
          quantity: tokenDetails.quantity || '0',
          recipientAddress: tokenDetails.recipientAddress || '',
        };
      }

      // Call pre-register API
      const response = await preRegisterToken(request, selectedVersion?.txHash);

      if (!response.isSuccessful) {
        throw new Error(response.error || 'Pre-registration failed');
      }

      setStakeAddresses(response.metadata || []);

      // Check if transaction is needed
      if (!response.unsignedCborTx) {
        // All addresses already registered
        setPhase('already-registered');
        showToastRef.current({
          title: 'Stake Addresses Ready',
          description: 'All required stake addresses are already registered',
          variant: 'success',
        });
      } else {
        // Need to sign and submit the transaction
        setPhase('signing');
        showToastRef.current({
          title: 'Sign Transaction',
          description: 'Please sign the stake address registration transaction',
          variant: 'default',
        });

        // Sign the transaction
        const signedTx = await wallet.signTx(response.unsignedCborTx, true);

        setPhase('submitting');

        // Submit the transaction
        const hash = await wallet.submitTx(signedTx);
        setTxHash(hash);

        showToastRef.current({
          title: 'Transaction Submitted',
          description: 'Waiting for confirmation...',
          variant: 'default',
        });

        // Start polling for confirmation
        setPhase('polling');
        setPollAttempt(0);

        abortControllerRef.current = new AbortController();

        await waitForTxConfirmation(hash, {
          pollInterval: TX_POLL_INTERVAL,
          timeout: TX_POLL_TIMEOUT,
          signal: abortControllerRef.current.signal,
          onPoll: (attempt) => {
            setPollAttempt(attempt);
          },
          onConfirmed: () => {
            showToastRef.current({
              title: 'Transaction Confirmed',
              description: 'Stake addresses registered on-chain',
              variant: 'success',
            });
          },
        });

        // Start post-tx cooldown
        setPhase('post-tx-cooldown');
        startCooldown('complete');
      }
    } catch (error) {
      if (error instanceof Error && error.message === 'Aborted') {
        return; // Ignore abort errors
      }

      setPhase('error');
      const message = error instanceof Error ? error.message : 'Pre-registration failed';
      setErrorMessage(message);

      if (message.toLowerCase().includes('user declined') ||
          message.toLowerCase().includes('user rejected')) {
        showToastRef.current({
          title: 'Transaction Cancelled',
          description: 'You cancelled the transaction',
          variant: 'default',
        });
      } else {
        showToastRef.current({
          title: 'Pre-Registration Failed',
          description: message,
          variant: 'error',
        });
        onError(message);
      }
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
    startCooldown,
  ]);

  // Initial effect - check prerequisites and start the flow
  useEffect(() => {
    if (hasStartedRef.current) return;
    hasStartedRef.current = true;

    // For F&S flow, check if blacklist init tx needs confirmation
    if (isFreezeAndSeize && blacklistInitTxHash) {
      // Start by checking if blacklist tx is confirmed
      setPhase('checking-prereqs');
      abortControllerRef.current = new AbortController();

      waitForTxConfirmation(blacklistInitTxHash, {
        pollInterval: TX_POLL_INTERVAL,
        timeout: TX_POLL_TIMEOUT,
        signal: abortControllerRef.current.signal,
        onPoll: (attempt) => {
          setPollAttempt(attempt);
        },
        onConfirmed: () => {
          showToastRef.current({
            title: 'Blacklist Transaction Confirmed',
            description: 'Proceeding with stake address registration...',
            variant: 'success',
          });
          // Start backend cooldown then call API
          setPhase('backend-cooldown');
          startCooldown('calling-api');
        },
      }).catch((error) => {
        if (error.message === 'Aborted') return;
        // On timeout, proceed anyway
        showToastRef.current({
          title: 'Confirmation Check Failed',
          description: 'Proceeding with registration...',
          variant: 'warning',
        });
        setPhase('backend-cooldown');
        startCooldown('calling-api');
      });
    } else {
      // For dummy flow, go directly to API call
      setPhase('calling-api');
    }

    // Cleanup
    return () => {
      hasStartedRef.current = false;
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
        abortControllerRef.current = null;
      }
      if (cooldownIntervalRef.current) {
        clearInterval(cooldownIntervalRef.current);
        cooldownIntervalRef.current = null;
      }
    };
  }, [isFreezeAndSeize, blacklistInitTxHash, startCooldown]);

  // Effect to call API when phase changes to calling-api
  useEffect(() => {
    if (phase === 'calling-api' && !isCallingApiRef.current) {
      callPreRegisterApi();
    }
  }, [phase, callPreRegisterApi]);

  // Handle continue from already-registered state
  const handleContinue = useCallback(() => {
    onComplete({
      stepId: 'pre-registration',
      data: {
        stakeAddresses,
        txHash: txHash || undefined,
      },
      txHash: txHash || undefined,
      completedAt: Date.now(),
    });
  }, [stakeAddresses, txHash, onComplete]);

  // Effect to auto-complete when phase is complete
  useEffect(() => {
    if (phase === 'complete') {
      handleContinue();
    }
  }, [phase, handleContinue]);

  // Retry after error
  const handleRetry = useCallback(() => {
    setPhase('calling-api');
    setErrorMessage('');
  }, []);

  // Truncate stake address for display
  const truncateAddress = (addr: string) => {
    if (addr.length <= 24) return addr;
    return `${addr.slice(0, 12)}...${addr.slice(-12)}`;
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">
          Stake Address Registration
        </h3>
        <p className="text-dark-300 text-sm">
          Before registering your token, the required stake addresses must be registered on-chain.
        </p>
      </div>

      {/* Checking Prerequisites (F&S only) */}
      {phase === 'checking-prereqs' && isFreezeAndSeize && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 border-4 border-orange-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <div>
            <p className="text-orange-400 font-medium">Waiting for Blacklist Confirmation</p>
            <p className="text-dark-400 text-sm mt-2">
              Checking if blacklist initialization is confirmed on-chain...
            </p>
          </div>
          <div className="text-sm text-dark-500">
            Poll attempt: {pollAttempt} (checking every 10s)
          </div>
        </Card>
      )}

      {/* Backend Cooldown */}
      {phase === 'backend-cooldown' && (
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
              Waiting for backend to process...
            </p>
          </div>
          <div className="text-2xl font-bold text-white">
            {cooldownRemaining}s
          </div>
        </Card>
      )}

      {/* Calling API */}
      {phase === 'calling-api' && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <div>
            <p className="text-dark-300 font-medium">Checking Stake Addresses</p>
            <p className="text-dark-400 text-sm mt-2">
              Determining which addresses need to be registered...
            </p>
          </div>
        </Card>
      )}

      {/* Already Registered */}
      {phase === 'already-registered' && (
        <>
          <Card className="p-4 bg-green-500/10 border-green-500/30">
            <div className="flex items-start gap-3">
              <svg className="w-5 h-5 text-green-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
              <div>
                <p className="text-green-300 font-medium text-sm">All Stake Addresses Ready</p>
                <p className="text-green-200/70 text-sm mt-1">
                  All required stake addresses are already registered on-chain. No transaction needed.
                </p>
              </div>
            </div>
          </Card>

          {stakeAddresses.length > 0 && (
            <Card className="p-4 space-y-3">
              <h4 className="font-medium text-white text-sm">Registered Addresses</h4>
              <div className="space-y-2">
                {stakeAddresses.map((addr, index) => (
                  <div key={index} className="flex items-center justify-between p-2 bg-dark-800 rounded text-sm">
                    <div className="flex items-center gap-2">
                      <svg className="w-4 h-4 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                      </svg>
                      <span className="text-dark-300 font-mono">{truncateAddress(addr)}</span>
                    </div>
                    <CopyButton value={addr} />
                  </div>
                ))}
              </div>
            </Card>
          )}
        </>
      )}

      {/* Signing */}
      {phase === 'signing' && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <div>
            <p className="text-dark-300 font-medium">Sign Transaction</p>
            <p className="text-dark-400 text-sm mt-2">
              Please sign the transaction in your wallet...
            </p>
          </div>
        </Card>
      )}

      {/* Submitting */}
      {phase === 'submitting' && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <div>
            <p className="text-dark-300 font-medium">Submitting Transaction</p>
            <p className="text-dark-400 text-sm mt-2">
              Submitting to the blockchain...
            </p>
          </div>
        </Card>
      )}

      {/* Polling for Confirmation */}
      {phase === 'polling' && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <div>
            <p className="text-primary-400 font-medium">Waiting for Confirmation</p>
            <p className="text-dark-400 text-sm mt-2">
              Transaction submitted, waiting for on-chain confirmation...
            </p>
          </div>
          <div className="text-sm text-dark-500">
            Poll attempt: {pollAttempt} (checking every 10s)
          </div>
          {txHash && (
            <div className="p-2 bg-dark-800 rounded">
              <div className="flex items-center justify-between">
                <span className="text-xs text-dark-400">Transaction Hash</span>
                <CopyButton value={txHash} />
              </div>
              <p className="text-xs text-primary-400 font-mono mt-1 truncate">{txHash}</p>
            </div>
          )}
        </Card>
      )}

      {/* Post-TX Cooldown */}
      {phase === 'post-tx-cooldown' && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 rounded-full bg-green-500/20 flex items-center justify-center">
              <svg className="w-6 h-6 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
          </div>
          <div>
            <p className="text-green-400 font-medium">Stake Addresses Registered!</p>
            <p className="text-dark-400 text-sm mt-2">
              Waiting for backend to process...
            </p>
          </div>
          <div className="text-2xl font-bold text-white">
            {cooldownRemaining}s
          </div>
          {txHash && (
            <div className="p-2 bg-dark-800 rounded">
              <div className="flex items-center justify-between">
                <span className="text-xs text-dark-400">Transaction Hash</span>
                <CopyButton value={txHash} />
              </div>
              <p className="text-xs text-primary-400 font-mono mt-1 truncate">{txHash}</p>
            </div>
          )}
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
              <p className="text-red-400 font-medium">Pre-Registration Failed</p>
              <p className="text-red-300 text-sm mt-1">{errorMessage}</p>
            </div>
          </div>
        </Card>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        {onBack && !['complete', 'post-tx-cooldown', 'polling', 'submitting', 'signing'].includes(phase) && (
          <Button
            variant="outline"
            onClick={onBack}
            disabled={isProcessing || ['calling-api', 'checking-prereqs', 'backend-cooldown'].includes(phase)}
          >
            Back
          </Button>
        )}

        {phase === 'already-registered' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleContinue}
            disabled={isProcessing || !connected}
          >
            Continue to Registration
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

        {['checking-prereqs', 'backend-cooldown', 'calling-api', 'signing', 'submitting', 'polling', 'post-tx-cooldown'].includes(phase) && (
          <Button
            variant="primary"
            className="flex-1"
            disabled
          >
            {phase === 'checking-prereqs' && 'Checking prerequisites...'}
            {phase === 'backend-cooldown' && `Processing... (${cooldownRemaining}s)`}
            {phase === 'calling-api' && 'Checking addresses...'}
            {phase === 'signing' && 'Waiting for signature...'}
            {phase === 'submitting' && 'Submitting...'}
            {phase === 'polling' && 'Confirming...'}
            {phase === 'post-tx-cooldown' && `Processing... (${cooldownRemaining}s)`}
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
