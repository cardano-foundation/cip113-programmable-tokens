"use client";

import { useState, useCallback, useEffect, useRef, useMemo } from 'react';
import { useWallet } from '@/hooks/use-wallet';
import { resolveTxHash } from '@/lib/utils/tx-hash';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { CopyButton } from '@/components/ui/copy-button';
import { useToast } from '@/components/ui/use-toast';
import { useProtocolVersion } from '@/contexts/protocol-version-context';
import { useCIP113 } from '@/contexts/cip113-context';
import { initBlacklist } from '@/lib/api/compliance';
import { registerToken, stringToHex } from '@/lib/api';
import { getPaymentKeyHash } from '@/lib/utils/address';
import { getExplorerTxUrl } from '@/lib/utils/format';
import { waitForTxConfirmation } from '@/lib/utils/tx-confirmation';
import type { FreezeAndSeizeRegisterRequest } from '@/types/api';
import type { StepComponentProps, TokenDetailsData } from '@/types/registration';

type CombinedStatus =
  | 'idle'
  | 'building-init'
  | 'building-reg'
  | 'preview'
  | 'signing'
  | 'submitting-init'
  | 'polling-init'
  | 'submitting-reg'
  | 'success'
  | 'error';

interface CombinedResult {
  blacklistNodePolicyId: string;
  initTxHash: string;
  tokenPolicyId: string;
  regTxHash: string;
}

const TX_POLL_INTERVAL = 10000; // 10 seconds
const TX_POLL_TIMEOUT = 300000; // 5 minutes

export function CombinedBuildSignSubmitStep({
  onComplete,
  onError,
  onBack,
  isProcessing,
  setProcessing,
  wizardState,
}: StepComponentProps<Record<string, unknown>, CombinedResult>) {
  const { connected, wallet, rawApi } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();
  const { buildFESRegistration, registerTokenCallback, available: sdkAvailable } = useCIP113();
  const [useSDK, setUseSDK] = useState(sdkAvailable);

  const [status, setStatus] = useState<CombinedStatus>('idle');
  const [errorMessage, setErrorMessage] = useState('');
  const [pollAttempt, setPollAttempt] = useState(0);

  // Transaction state
  const [blacklistNodePolicyId, setBlacklistNodePolicyId] = useState('');
  const [initUnsignedCbor, setInitUnsignedCbor] = useState('');
  const [regUnsignedCbor, setRegUnsignedCbor] = useState('');
  const [tokenPolicyId, setTokenPolicyId] = useState('');
  const [initTxHash, setInitTxHash] = useState('');
  const [regTxHash, setRegTxHash] = useState('');
  // Derived from unsigned CBOR at build time (for preview display)
  const [derivedInitTxHash, setDerivedInitTxHash] = useState('');
  const [derivedRegTxHash, setDerivedRegTxHash] = useState('');

  // Signed transactions (kept for retry after polling)
  const [signedInitTx, setSignedInitTx] = useState('');
  const [signedRegTx, setSignedRegTx] = useState('');

  // Refs
  const abortControllerRef = useRef<AbortController | null>(null);
  const showToastRef = useRef(showToast);

  useEffect(() => { showToastRef.current = showToast; }, [showToast]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
        abortControllerRef.current = null;
      }
    };
  }, []);

  // Get token details from previous step
  const tokenDetails = useMemo(() => {
    const detailsState = wizardState.stepStates['token-details'];
    return (detailsState?.data || {}) as Partial<TokenDetailsData>;
  }, [wizardState.stepStates]);

  // ---- BUILD BOTH TRANSACTIONS ----
  const handleBuild = useCallback(async () => {
    if (!connected || !wallet) {
      onError('Wallet not connected');
      return;
    }
    if (!tokenDetails.assetName || !tokenDetails.quantity) {
      onError('Token details missing');
      return;
    }

    try {
      setProcessing(true);
      setErrorMessage('');

      // Get wallet address
      const addresses = await wallet.getUsedAddresses();
      if (!addresses?.[0]) throw new Error('No wallet address found');
      const adminAddress = addresses[0];

      if (useSDK) {
        // ===== SDK PATH: Build both txs client-side =====
        setStatus('building-init');
        showToastRef.current({
          title: 'Building with CIP-113 SDK',
          description: 'Building blacklist init + registration...',
          variant: 'default',
        });

        const sdkResult = await buildFESRegistration({
          adminAddress,
          assetName: tokenDetails.assetName,
          quantity: tokenDetails.quantity,
          recipientAddress: tokenDetails.recipientAddress,
          rawWalletApi: rawApi,
        });

        setBlacklistNodePolicyId(sdkResult.blacklistNodePolicyId);
        setInitUnsignedCbor(sdkResult.initCbor);
        setDerivedInitTxHash(await resolveTxHash(sdkResult.initCbor));

        setStatus('building-reg');
        setTokenPolicyId(sdkResult.tokenPolicyId);
        setRegUnsignedCbor(sdkResult.regCbor);
        setDerivedRegTxHash(await resolveTxHash(sdkResult.regCbor));
      } else {
        // ===== BACKEND PATH: Build via Java API =====

        // --- Step 1: Build init tx ---
        setStatus('building-init');
        showToastRef.current({
          title: 'Building Transactions',
          description: 'Building blacklist initialization...',
          variant: 'default',
        });

        const initResponse = await initBlacklist(
          {
            substandardId: 'freeze-and-seize',
            adminAddress,
            feePayerAddress: adminAddress,
            assetName: stringToHex(tokenDetails.assetName),
          },
          selectedVersion?.txHash
        );
        setBlacklistNodePolicyId(initResponse.policyId);
        setInitUnsignedCbor(initResponse.unsignedCborTx);
        setDerivedInitTxHash(await resolveTxHash(initResponse.unsignedCborTx));

        // --- Step 2: Build registration tx with chaining (send full init CBOR) ---
        setStatus('building-reg');
        showToastRef.current({
          title: 'Building Transactions',
          description: 'Building registration transaction...',
          variant: 'default',
        });

        const adminPubKeyHash = getPaymentKeyHash(adminAddress);
        const regRequest: FreezeAndSeizeRegisterRequest = {
          substandardId: 'freeze-and-seize',
          feePayerAddress: adminAddress,
          assetName: stringToHex(tokenDetails.assetName),
          quantity: tokenDetails.quantity,
          recipientAddress: tokenDetails.recipientAddress || '',
          adminPubKeyHash,
          blacklistNodePolicyId: initResponse.policyId,
          chainingTransactionCborHex: initResponse.unsignedCborTx,
        };

        const regResponse = await registerToken(regRequest, selectedVersion?.txHash);
        setTokenPolicyId(regResponse.policyId);
        setRegUnsignedCbor(regResponse.unsignedCborTx);
        setDerivedRegTxHash(await resolveTxHash(regResponse.unsignedCborTx));
      }

      // --- Show preview ---
      setStatus('preview');
      showToastRef.current({
        title: 'Transactions Built',
        description: 'Review and sign both transactions',
        variant: 'success',
      });
    } catch (error) {
      setStatus('error');
      const message = error instanceof Error ? error.message : 'Failed to build transactions';
      setErrorMessage(message);
      showToastRef.current({
        title: 'Build Failed',
        description: message,
        variant: 'error',
      });
      onError(message);
    } finally {
      setProcessing(false);
    }
  }, [connected, wallet, tokenDetails, selectedVersion, onError, setProcessing, useSDK, buildFESRegistration]);

  // ---- SIGN BOTH & SUBMIT SEQUENTIALLY ----
  const handleSignAndSubmit = useCallback(async () => {
    if (!connected || !wallet) {
      onError('Wallet not connected');
      return;
    }

    try {
      setProcessing(true);
      setErrorMessage('');

      // --- Sign both txs ---
      setStatus('signing');
      showToastRef.current({
        title: 'Sign Transactions',
        description: 'Please sign both transactions in your wallet',
        variant: 'default',
      });

      // Sign both txs — try batch first, fall back to sequential (two popups)
      let signedTxs: string[];
      try {
        signedTxs = await wallet.signTxs([initUnsignedCbor, regUnsignedCbor], true);
      } catch (err) {
        console.warn("[CIP-113] signTxs failed, falling back to sequential signTx:", (err as Error)?.message);
        const signed1 = await wallet.signTx(initUnsignedCbor, true);
        const signed2 = await wallet.signTx(regUnsignedCbor, true);
        signedTxs = [signed1, signed2];
      }

      setSignedInitTx(signedTxs[0]);
      setSignedRegTx(signedTxs[1]);

      // --- Submit init tx ---
      setStatus('submitting-init');
      showToastRef.current({
        title: 'Submitting',
        description: 'Submitting blacklist initialization...',
        variant: 'default',
      });

      const hash1 = await wallet.submitTx(signedTxs[0]);
      setInitTxHash(hash1);

      // --- Poll for init tx confirmation ---
      setStatus('polling-init');
      setPollAttempt(0);
      showToastRef.current({
        title: 'Waiting for Confirmation',
        description: 'Waiting for init transaction to be confirmed on-chain...',
        variant: 'default',
      });

      abortControllerRef.current = new AbortController();

      await waitForTxConfirmation(hash1, {
        pollInterval: TX_POLL_INTERVAL,
        timeout: TX_POLL_TIMEOUT,
        signal: abortControllerRef.current.signal,
        onPoll: (attempt) => setPollAttempt(attempt),
        onConfirmed: () => {
          showToastRef.current({
            title: 'Init Confirmed',
            description: 'Blacklist initialized. Submitting registration...',
            variant: 'success',
          });
        },
      });

      // --- Submit registration tx ---
      setStatus('submitting-reg');
      showToastRef.current({
        title: 'Submitting',
        description: 'Submitting token registration...',
        variant: 'default',
      });

      const hash2 = await wallet.submitTx(signedTxs[1]);
      setRegTxHash(hash2);

      // --- Success ---
      setStatus('success');
      showToastRef.current({
        title: 'Registration Complete!',
        description: 'Both transactions submitted successfully',
        variant: 'success',
      });

      // Register token in backend DB (callback for SDK-built registrations)
      if (useSDK && tokenPolicyId) {
        try {
          const addresses = await wallet.getUsedAddresses();
          const adminAddr = addresses?.[0] ?? '';
          await registerTokenCallback({
            policyId: tokenPolicyId,
            substandardId: 'freeze-and-seize',
            assetName: stringToHex(tokenDetails.assetName || ''),
            issuerAdminPkh: adminAddr ? getPaymentKeyHash(adminAddr) : '',
            blacklistNodePolicyId,
          });
          console.log('[CIP-113] Token registered in backend DB');
        } catch (e) {
          console.warn('[CIP-113] Failed to register token in backend DB:', e);
        }
      }

      // Complete the wizard step
      onComplete({
        stepId: 'combined-build-sign',
        data: {
          blacklistNodePolicyId,
          initTxHash: hash1,
          tokenPolicyId,
          regTxHash: hash2,
        },
        txHash: hash2,
        completedAt: Date.now(),
      });
    } catch (error) {
      if (error instanceof Error && error.message === 'Aborted') return;

      setStatus('error');
      const message = error instanceof Error ? error.message : 'Failed to sign or submit';
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
          title: 'Submission Failed',
          description: message,
          variant: 'error',
        });
        onError(message);
      }
    } finally {
      setProcessing(false);
    }
  }, [
    connected, wallet, initUnsignedCbor, regUnsignedCbor,
    blacklistNodePolicyId, tokenPolicyId,
    onComplete, onError, setProcessing,
  ]);

  // ---- RETRY: If init was submitted but reg failed, try submitting reg again ----
  const handleRetryRegSubmit = useCallback(async () => {
    if (!connected || !wallet || !signedRegTx) return;

    try {
      setProcessing(true);
      setErrorMessage('');

      // Re-poll init tx first (might still be pending)
      if (initTxHash) {
        setStatus('polling-init');
        setPollAttempt(0);

        abortControllerRef.current = new AbortController();
        await waitForTxConfirmation(initTxHash, {
          pollInterval: TX_POLL_INTERVAL,
          timeout: TX_POLL_TIMEOUT,
          signal: abortControllerRef.current.signal,
          onPoll: (attempt) => setPollAttempt(attempt),
        });
      }

      setStatus('submitting-reg');
      const hash2 = await wallet.submitTx(signedRegTx);
      setRegTxHash(hash2);

      setStatus('success');
      showToastRef.current({
        title: 'Registration Complete!',
        description: 'Registration transaction submitted successfully',
        variant: 'success',
      });

      onComplete({
        stepId: 'combined-build-sign',
        data: {
          blacklistNodePolicyId,
          initTxHash,
          tokenPolicyId,
          regTxHash: hash2,
        },
        txHash: hash2,
        completedAt: Date.now(),
      });
    } catch (error) {
      if (error instanceof Error && error.message === 'Aborted') return;
      setStatus('error');
      const message = error instanceof Error ? error.message : 'Failed to submit registration';
      setErrorMessage(message);
      onError(message);
    } finally {
      setProcessing(false);
    }
  }, [connected, wallet, signedRegTx, initTxHash, blacklistNodePolicyId, tokenPolicyId, onComplete, onError, setProcessing]);

  // Full retry from scratch
  const handleFullRetry = useCallback(() => {
    setStatus('idle');
    setErrorMessage('');
    setBlacklistNodePolicyId('');
    setInitUnsignedCbor('');
    setRegUnsignedCbor('');
    setTokenPolicyId('');
    setInitTxHash('');
    setRegTxHash('');
    setSignedInitTx('');
    setSignedRegTx('');
    setDerivedInitTxHash('');
    setDerivedRegTxHash('');
  }, []);

  // Can we retry just the reg submission?
  const canRetryRegSubmit = status === 'error' && initTxHash && signedRegTx;

  const ExplorerLink = ({ txHash: hash }: { txHash: string }) => (
    <a
      href={getExplorerTxUrl(hash)}
      target="_blank"
      rel="noopener noreferrer"
      className="text-dark-400 hover:text-primary-400 transition-colors"
      title="View on cexplorer"
    >
      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
      </svg>
    </a>
  );

  const TxHashRow = ({ label, hash, color = 'text-primary-400' }: { label: string; hash: string; color?: string }) => (
    <div className="p-3 bg-dark-800 rounded">
      <div className="flex items-center justify-between mb-1">
        <span className="text-xs text-dark-400">{label}</span>
        <div className="flex items-center gap-1.5">
          <CopyButton value={hash} />
          <ExplorerLink txHash={hash} />
        </div>
      </div>
      <p className={`text-sm ${color} font-mono break-all`}>{hash}</p>
    </div>
  );

  const getStatusMessage = () => {
    switch (status) {
      case 'building-init': return 'Building blacklist initialization...';
      case 'building-reg': return 'Building registration transaction...';
      case 'preview': return 'Review both transactions before signing';
      case 'signing': return 'Waiting for wallet signature...';
      case 'submitting-init': return 'Submitting blacklist initialization...';
      case 'polling-init': return 'Waiting for init tx confirmation...';
      case 'submitting-reg': return 'Submitting token registration...';
      case 'success': return 'Registration complete!';
      case 'error': return errorMessage || 'Operation failed';
      default: return 'Ready to build and register';
    }
  };

  const isBuilding = status === 'building-init' || status === 'building-reg';
  const isSubmitting = status === 'submitting-init' || status === 'polling-init' || status === 'submitting-reg';
  const isActive = isBuilding || status === 'signing' || isSubmitting;

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">
          {status === 'preview' ? 'Review & Sign' : 'Build & Register'}
        </h3>
        <p className="text-dark-300 text-sm">
          {status === 'idle'
            ? 'Build both transactions, sign them together, and submit sequentially.'
            : status === 'preview'
            ? 'Review the details below, then sign both transactions.'
            : 'Processing your registration...'}
        </p>
      </div>

      {/* Idle state: show summary + build button */}
      {status === 'idle' && (
        <>
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
                <p className="text-white font-medium capitalize">Freeze & Seize</p>
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

          {/* SDK / Backend toggle */}
          <Card className="p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-sm text-dark-300">Transaction Builder</span>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setUseSDK(false)}
                  className={`px-3 py-1 rounded text-xs font-medium transition-colors ${
                    !useSDK ? 'bg-primary-500 text-white' : 'bg-dark-700 text-dark-400 hover:text-white'
                  }`}
                >
                  Backend (Java)
                </button>
                <button
                  onClick={() => setUseSDK(true)}
                  disabled={!sdkAvailable}
                  className={`px-3 py-1 rounded text-xs font-medium transition-colors ${
                    useSDK ? 'bg-primary-500 text-white' : 'bg-dark-700 text-dark-400 hover:text-white'
                  } ${!sdkAvailable ? 'opacity-50 cursor-not-allowed' : ''}`}
                >
                  SDK (Evolution)
                </button>
              </div>
            </div>
            <p className="text-xs text-dark-500">
              {useSDK
                ? 'Building transactions client-side with CIP-113 SDK + Evolution SDK'
                : 'Building transactions server-side with Java backend'}
            </p>
          </Card>

          <Card className="p-4 bg-blue-500/10 border-blue-500/30">
            <div className="flex items-start gap-3">
              <svg className="w-5 h-5 text-blue-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <div>
                <p className="text-blue-300 font-medium text-sm">Combined Registration</p>
                <p className="text-blue-200/70 text-sm mt-1">
                  This will build the blacklist init and token registration transactions together,
                  then sign them in a single wallet interaction.
                </p>
              </div>
            </div>
          </Card>
        </>
      )}

      {/* Building / Signing / Submitting spinner */}
      {isActive && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <p className="text-dark-300 font-medium">{getStatusMessage()}</p>
          {status === 'polling-init' && (
            <div className="text-sm text-dark-500">
              Poll attempt: {pollAttempt} (checking every 10s)
            </div>
          )}
        </Card>
      )}

      {/* Preview state */}
      {status === 'preview' && (
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
            </div>
          </Card>

          <Card className="p-4 space-y-2">
            <div className="flex items-center justify-between">
              <h4 className="font-medium text-white">Token Policy ID</h4>
              <CopyButton value={tokenPolicyId} />
            </div>
            <p className="text-sm text-primary-400 font-mono break-all">{tokenPolicyId}</p>
          </Card>

          <Card className="p-4 space-y-2">
            <div className="flex items-center justify-between">
              <h4 className="font-medium text-white">Blacklist Node Policy ID</h4>
              <CopyButton value={blacklistNodePolicyId} />
            </div>
            <p className="text-sm text-orange-400 font-mono break-all">{blacklistNodePolicyId}</p>
          </Card>

          <Card className="p-4 space-y-3">
            <h4 className="font-medium text-white">Transactions</h4>
            <div className="space-y-2">
              {derivedInitTxHash && (
                <TxHashRow label="1. Blacklist Init Tx Hash" hash={derivedInitTxHash} />
              )}
              {derivedRegTxHash && (
                <TxHashRow label="2. Registration Tx Hash" hash={derivedRegTxHash} />
              )}
            </div>
          </Card>

          {/* CBOR Debug: Init Tx */}
          {initUnsignedCbor && (
            <Card className="p-4 space-y-2">
              <div className="flex items-center justify-between">
                <h4 className="font-medium text-white text-sm">Init Tx CBOR ({useSDK ? 'SDK' : 'Backend'})</h4>
                <CopyButton value={initUnsignedCbor} />
              </div>
              <p className="text-xs text-dark-500 font-mono break-all max-h-24 overflow-y-auto">
                {initUnsignedCbor}
              </p>
            </Card>
          )}

          {/* CBOR Debug: Reg Tx */}
          {regUnsignedCbor && (
            <Card className="p-4 space-y-2">
              <div className="flex items-center justify-between">
                <h4 className="font-medium text-white text-sm">Reg Tx CBOR ({useSDK ? 'SDK' : 'Backend'})</h4>
                <CopyButton value={regUnsignedCbor} />
              </div>
              <p className="text-xs text-dark-500 font-mono break-all max-h-24 overflow-y-auto">
                {regUnsignedCbor}
              </p>
            </Card>
          )}
        </>
      )}

      {/* Success state */}
      {status === 'success' && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 rounded-full bg-green-500/20 flex items-center justify-center">
              <svg className="w-6 h-6 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
          </div>
          <p className="text-green-400 font-medium">Registration Complete!</p>
          <div className="mt-4 space-y-3 text-left">
            <div className="p-3 bg-dark-800 rounded">
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs text-dark-400">Token Policy ID</span>
                <CopyButton value={tokenPolicyId} />
              </div>
              <p className="text-sm text-primary-400 font-mono break-all">{tokenPolicyId}</p>
            </div>
            <div className="p-3 bg-dark-800 rounded">
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs text-dark-400">Blacklist Node Policy ID</span>
                <CopyButton value={blacklistNodePolicyId} />
              </div>
              <p className="text-sm text-orange-400 font-mono break-all">{blacklistNodePolicyId}</p>
            </div>
            {initTxHash && (
              <TxHashRow label="Init Tx Hash" hash={initTxHash} />
            )}
            {regTxHash && (
              <TxHashRow label="Registration Tx Hash" hash={regTxHash} />
            )}
          </div>
        </Card>
      )}

      {/* Error state */}
      {status === 'error' && (
        <Card className="p-4 bg-red-500/10 border-red-500/30">
          <div className="flex items-start gap-3">
            <svg className="w-5 h-5 text-red-400 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <div>
              <p className="text-red-400 font-medium">Operation Failed</p>
              <p className="text-red-300 text-sm mt-1">{errorMessage}</p>
            </div>
          </div>
        </Card>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        {onBack && status !== 'success' && !isActive && (
          <Button
            variant="outline"
            onClick={onBack}
            disabled={isProcessing}
          >
            Back
          </Button>
        )}

        {status === 'idle' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleBuild}
            disabled={isProcessing || !connected}
          >
            Build Registration
          </Button>
        )}

        {status === 'preview' && (
          <Button
            variant="primary"
            className="flex-1"
            onClick={handleSignAndSubmit}
            disabled={isProcessing || !connected}
          >
            Sign & Submit
          </Button>
        )}

        {status === 'error' && (
          <div className="flex gap-2 flex-1">
            {canRetryRegSubmit && (
              <Button
                variant="primary"
                className="flex-1"
                onClick={handleRetryRegSubmit}
                disabled={isProcessing || !connected}
              >
                Retry Registration Submit
              </Button>
            )}
            <Button
              variant={canRetryRegSubmit ? 'outline' : 'primary'}
              className="flex-1"
              onClick={handleFullRetry}
              disabled={isProcessing}
            >
              Rebuild From Scratch
            </Button>
          </div>
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
