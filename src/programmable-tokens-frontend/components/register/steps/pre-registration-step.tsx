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
  | 'ready-to-start'      // Ready for user to start pre-registration
  | 'calling-api'         // Calling pre-register API
  | 'preview'             // Showing transaction preview before signing
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
  const [allowManualProceed, setAllowManualProceed] = useState(false);

  // Cooldown state
  const [cooldownRemaining, setCooldownRemaining] = useState(0);
  const cooldownIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Pre-registration result state
  const [stakeAddresses, setStakeAddresses] = useState<string[]>([]);
  const [txHash, setTxHash] = useState('');
  const [unsignedCborTx, setUnsignedCborTx] = useState('');

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

      // Call pre-register API with timeout handling
      console.log('[PreRegister] Calling API with request:', request);
      
      let response: Awaited<ReturnType<typeof preRegisterToken>>;
      try {
        response = await preRegisterToken(request, selectedVersion?.txHash);
        console.log('[PreRegister] API Response received:', response);
      } catch (apiError) {
        console.error('[PreRegister] API call failed:', apiError);
        throw new Error(apiError instanceof Error ? apiError.message : 'Failed to call pre-register API');
      }

      // Handle both possible response formats
      const isSuccessful = response?.isSuccessful ?? (response as any)?.successful ?? false;
      const unsignedCborTx = response?.unsignedCborTx ?? (response as any)?.unsignedCborTx ?? null;
      const metadata = response?.metadata ?? (response as any)?.metadata ?? [];
      const error = response?.error ?? (response as any)?.error ?? null;

      console.log('[PreRegister] Parsed response:', { isSuccessful, hasUnsignedTx: !!unsignedCborTx, metadataCount: Array.isArray(metadata) ? metadata.length : 0, error });

      if (!isSuccessful) {
        throw new Error(error || 'Pre-registration failed');
      }

      // Store stake addresses from metadata (these are the registered addresses returned by backend)
      const stakeAddrs = Array.isArray(metadata) ? metadata : [];
      setStakeAddresses(stakeAddrs);

      // Check if transaction is needed
      if (!unsignedCborTx) {
        // All addresses already registered
        setPhase('already-registered');
        showToastRef.current({
          title: 'Stake Addresses Ready',
          description: 'All required stake addresses are already registered',
          variant: 'success',
        });
      } else {
        // Store the unsigned transaction and show preview
        setUnsignedCborTx(unsignedCborTx);
        setPhase('preview');
        showToastRef.current({
          title: 'Transaction Ready',
          description: 'Review the transaction before signing',
          variant: 'default',
        });
      }
    } catch (error) {
      if (error instanceof Error && error.message === 'Aborted') {
        return; // Ignore abort errors
      }

      setPhase('error');
      const message = error instanceof Error ? error.message : 'Pre-registration failed';
      setErrorMessage(message);

      if (message.toLowerCase().includes('user declined') ||
          message.toLowerCase().includes('user rejected') ||
          message.toLowerCase().includes('cancelled')) {
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
          // After 3 attempts (30 seconds), allow manual proceed if transaction is confirmed on explorer
          if (attempt >= 3) {
            setAllowManualProceed(true);
          }
        },
        onConfirmed: () => {
          showToastRef.current({
            title: 'Blacklist Transaction Confirmed',
            description: 'Ready to proceed with stake address registration',
            variant: 'success',
          });
          // Start backend cooldown then wait for user action
          setPhase('backend-cooldown');
          startCooldown('ready-to-start');
        },
      }).catch((error) => {
        if (error.message === 'Aborted') return;
        // On timeout, let user decide to proceed
        showToastRef.current({
          title: 'Confirmation Check Failed',
          description: 'You can still proceed with registration',
          variant: 'warning',
        });
        setAllowManualProceed(true);
        setPhase('ready-to-start');
      });
    } else {
      // For dummy flow, wait for user to start
      setPhase('ready-to-start');
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

  // Manual handler to start pre-registration (user clicks button)
  const handleStartPreRegistration = useCallback(() => {
    setPhase('calling-api');
    callPreRegisterApi();
  }, [callPreRegisterApi]);

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

  // Handler to proceed from preview to signing
  const handleProceedToSign = useCallback(async () => {
    if (!unsignedCborTx || !wallet) {
      onError('Transaction or wallet not available');
      return;
    }

    try {
      setProcessing(true);
      setPhase('signing');
      showToastRef.current({
        title: 'Sign Transaction',
        description: 'Please sign the stake address registration transaction',
        variant: 'default',
      });

      // Sign the transaction
      const signedTx = await wallet.signTx(unsignedCborTx, true);

      setPhase('submitting');

      // Submit the transaction
      const hash = await wallet.submitTx(signedTx);
      setTxHash(hash); // Store hash immediately so it's available in UI

      showToastRef.current({
        title: 'Transaction Submitted',
        description: 'Waiting for confirmation...',
        variant: 'default',
      });

      // Keep submitting phase visible for 2 seconds so user can see hash and use buttons
      await new Promise(resolve => setTimeout(resolve, 2000));

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
    } catch (walletError) {
      // Handle wallet-specific errors (signing/submitting)
      if (walletError instanceof Error) {
        const walletMessage = walletError.message.toLowerCase();
        const errorInfo = walletError.info || '';
        
        // Check if stake addresses are already registered
        if (errorInfo.includes('StakeKeyRegisteredDELEG') || 
            errorInfo.includes('stakekeyregistered') ||
            walletMessage.includes('stakekeyregistered')) {
          // Stake addresses are already registered - treat as success
          // The stake addresses should already be stored from the API response metadata
          showToastRef.current({
            title: 'Stake Addresses Already Registered',
            description: 'The required stake addresses are already registered on-chain. You can proceed.',
            variant: 'success',
          });
          setPhase('already-registered');
          // Stake addresses are already set from API response, no need to clear them
          setProcessing(false);
          return;
        }
        
        if (walletMessage.includes('user declined') || 
            walletMessage.includes('user rejected') ||
            walletMessage.includes('user cancelled') ||
            walletMessage.includes('cancelled')) {
          setPhase('preview'); // Go back to preview instead of error
          setErrorMessage('Transaction signing was cancelled. You can try again.');
          showToastRef.current({
            title: 'Transaction Cancelled',
            description: 'You cancelled the transaction signing',
            variant: 'default',
          });
          return;
        }
      }
      // Re-throw wallet errors to be caught by outer catch
      throw walletError;
    } finally {
      setProcessing(false);
    }
  }, [unsignedCborTx, wallet, onError, setProcessing, startCooldown]);

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
          {blacklistInitTxHash && (
            <div className="mt-6 p-5 bg-blue-500/10 border-2 border-blue-500/50 rounded-lg">
              <p className="text-blue-300 font-medium mb-2">
                Transaction confirmed on explorer? Proceed manually:
              </p>
              <p className="text-blue-200/70 text-xs mb-4">
                If you see the transaction on Cardanoscan, you can skip the automatic confirmation check.
              </p>
              <div className="flex gap-3 justify-center flex-wrap">
                <Button
                  onClick={() => {
                    if (abortControllerRef.current) {
                      abortControllerRef.current.abort();
                    }
                    showToastRef.current({
                      title: 'Proceeding Manually',
                      description: 'Skipping confirmation check',
                      variant: 'default',
                    });
                    setPhase('backend-cooldown');
                    startCooldown('ready-to-start');
                  }}
                  className="bg-blue-500 hover:bg-blue-600 text-white font-medium px-6 py-2"
                >
                  ✓ Proceed Manually
                </Button>
                <Button
                  onClick={() => {
                    const explorerUrl = `https://preview.cardanoscan.io/transaction/${blacklistInitTxHash}`;
                    window.open(explorerUrl, '_blank');
                  }}
                  variant="outline"
                  className="bg-gray-500/20 border-gray-500/50 text-gray-300 hover:bg-gray-500/30"
                >
                  View on Explorer
                </Button>
              </div>
            </div>
          )}
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

      {/* Ready to Start */}
      {phase === 'ready-to-start' && (
        <Card className="p-4 bg-blue-500/10 border-blue-500/30">
          <div className="flex items-start gap-3">
            <svg className="w-5 h-5 text-blue-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div>
              <p className="text-blue-300 font-medium text-sm">Ready to Register Stake Addresses</p>
              <p className="text-blue-200/70 text-sm mt-1">
                {isFreezeAndSeize
                  ? 'Blacklist initialization complete. Click below to register required stake addresses.'
                  : 'Click below to check and register required stake addresses.'}
              </p>
            </div>
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
          {errorMessage && (
            <div className="mt-4 p-4 bg-red-500/10 border border-red-500/30 rounded-lg">
              <p className="text-red-300 text-sm">{errorMessage}</p>
            </div>
          )}
          <div className="mt-4 p-4 bg-blue-500/10 border border-blue-500/30 rounded-lg">
            <p className="text-blue-300 text-xs mb-3">
              If the API call seems stuck, you can try refreshing the page or check the browser console for errors.
            </p>
            <Button
              onClick={() => {
                if (abortControllerRef.current) {
                  abortControllerRef.current.abort();
                }
                setPhase('error');
                setErrorMessage('API call was cancelled. Please try again.');
              }}
              variant="outline"
              className="bg-gray-500/20 border-gray-500/50 text-gray-300 hover:bg-gray-500/30 text-sm"
            >
              Cancel & Retry
            </Button>
          </div>
        </Card>
      )}

      {/* Preview Transaction */}
      {phase === 'preview' && unsignedCborTx && (
        <Card className="p-6 space-y-4">
          <div className="flex items-start gap-3">
            <svg className="w-5 h-5 text-primary-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <div className="flex-1">
              <h3 className="text-white font-medium mb-2">Transaction Preview</h3>
              <p className="text-dark-400 text-sm mb-4">
                Review the transaction details before signing. The transaction will register the required stake addresses on-chain.
              </p>
              
              {stakeAddresses.length > 0 && (
                <div className="mb-4">
                  <p className="text-dark-300 text-sm font-medium mb-2">Stake Addresses to Register:</p>
                  <div className="space-y-2">
                    {stakeAddresses.map((addr, index) => (
                      <div key={index} className="flex items-center justify-between p-2 bg-dark-800 rounded text-sm">
                        <span className="text-dark-300 font-mono">{truncateAddress(addr)}</span>
                        <CopyButton value={addr} />
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <div className="p-3 bg-dark-800 rounded border border-dark-700">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs text-dark-400">Unsigned Transaction (CBOR)</span>
                  <CopyButton value={unsignedCborTx} />
                </div>
                <p className="text-xs text-primary-400 font-mono break-all">{unsignedCborTx.substring(0, 100)}...</p>
                <p className="text-xs text-dark-500 mt-1">Full transaction: {unsignedCborTx.length} characters</p>
              </div>

              {errorMessage && (
                <div className="mt-4 p-3 bg-red-500/10 border border-red-500/30 rounded-lg">
                  <p className="text-red-300 text-sm">{errorMessage}</p>
                </div>
              )}
            </div>
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
          {txHash && (
            <>
              <div className="mt-4 p-3 bg-dark-800 rounded border border-dark-700">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs text-dark-400">Transaction Hash</span>
                  <CopyButton value={txHash} />
                </div>
                <p className="text-xs text-primary-400 font-mono mt-1 truncate">{txHash}</p>
              </div>
              <div className="mt-4 p-4 bg-blue-500/10 border border-blue-500/30 rounded-lg">
                <p className="text-blue-300 text-xs mb-3">
                  Transaction submitted! You can view it on the explorer or proceed manually once confirmed.
                </p>
                <div className="flex gap-3 justify-center flex-wrap">
                  <Button
                    onClick={() => {
                      const explorerUrl = `https://preview.cardanoscan.io/transaction/${txHash}`;
                      window.open(explorerUrl, '_blank');
                    }}
                    variant="outline"
                    className="bg-blue-500/20 border-blue-500/50 text-blue-300 hover:bg-blue-500/30"
                  >
                    View on Explorer
                  </Button>
                  <Button
                    onClick={() => {
                      showToastRef.current({
                        title: 'Proceeding Manually',
                        description: 'Skipping automatic confirmation check',
                        variant: 'default',
                      });
                      setPhase('polling');
                      setPollAttempt(0);
                      abortControllerRef.current = new AbortController();
                      // Start polling but allow manual proceed
                      waitForTxConfirmation(txHash, {
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
                          setPhase('post-tx-cooldown');
                          startCooldown('complete');
                        },
                      }).catch(() => {
                        // Ignore errors, user can proceed manually
                      });
                    }}
                    className="bg-blue-500 hover:bg-blue-600 text-white font-medium px-6 py-2"
                  >
                    ✓ Proceed Manually
                  </Button>
                </div>
              </div>
            </>
          )}
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
            <>
              <div className="p-2 bg-dark-800 rounded">
                <div className="flex items-center justify-between">
                  <span className="text-xs text-dark-400">Transaction Hash</span>
                  <CopyButton value={txHash} />
                </div>
                <p className="text-xs text-primary-400 font-mono mt-1 truncate">{txHash}</p>
              </div>
              <div className="mt-4 p-5 bg-blue-500/10 border-2 border-blue-500/50 rounded-lg">
                <p className="text-blue-300 font-medium mb-2">
                  Transaction confirmed on explorer? Proceed manually:
                </p>
                <p className="text-blue-200/70 text-xs mb-4">
                  If you see the transaction on Cardanoscan, you can skip the automatic confirmation check.
                </p>
                <div className="flex gap-3 justify-center flex-wrap">
                  <Button
                    onClick={() => {
                      if (abortControllerRef.current) {
                        abortControllerRef.current.abort();
                      }
                      showToastRef.current({
                        title: 'Proceeding Manually',
                        description: 'Skipping confirmation check',
                        variant: 'default',
                      });
                      setPhase('post-tx-cooldown');
                      startCooldown('complete');
                    }}
                    className="bg-blue-500 hover:bg-blue-600 text-white font-medium px-6 py-2"
                  >
                    ✓ Proceed Manually
                  </Button>
                  <Button
                    onClick={() => {
                      const explorerUrl = `https://preview.cardanoscan.io/transaction/${txHash}`;
                      window.open(explorerUrl, '_blank');
                    }}
                    variant="outline"
                    className="bg-gray-500/20 border-gray-500/50 text-gray-300 hover:bg-gray-500/30"
                  >
                    View on Explorer
                  </Button>
                </div>
              </div>
            </>
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
        {onBack && !['complete', 'post-tx-cooldown', 'polling', 'submitting', 'signing', 'preview'].includes(phase) && (
          <Button
            variant="outline"
            onClick={onBack}
            disabled={isProcessing || ['calling-api', 'checking-prereqs', 'backend-cooldown'].includes(phase)}
          >
            Back
          </Button>
        )}

        {phase === 'ready-to-start' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleStartPreRegistration}
            disabled={isProcessing || !connected}
          >
            Register Stake Addresses
          </Button>
        )}

        {phase === 'preview' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleProceedToSign}
            disabled={isProcessing || !unsignedCborTx}
          >
            Sign & Submit Transaction
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
