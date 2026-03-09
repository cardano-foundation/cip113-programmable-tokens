"use client";

import { useState, useCallback, useEffect, useRef, useMemo } from 'react';
import { useWallet } from '@meshsdk/react';
import { resolveTxHash } from '@meshsdk/core';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { CopyButton } from '@/components/ui/copy-button';
import { useToast } from '@/components/ui/use-toast';
import { useProtocolVersion } from '@/contexts/protocol-version-context';
import { initGovernance } from '@/lib/api/compliance';
import { registerToken, stringToHex } from '@/lib/api';
import { getPaymentKeyHash } from '@/lib/utils/address';
import { getExplorerTxUrl } from '@/lib/utils/format';
import { waitForTxConfirmation } from '@/lib/utils/tx-confirmation';
import type { WhitelistMultiAdminRegisterRequest } from '@/types/api';
import type { StepComponentProps, TokenDetailsData } from '@/types/registration';

type CombinedStatus =
  | 'idle'
  | 'building-init'
  | 'building-reg'
  | 'preview'
  | 'signing'
  | 'submitting-init'
  | 'polling-init'
  | 'submitting-add-admin'
  | 'polling-add-admin'
  | 'submitting-reg'
  | 'success'
  | 'error';

interface CombinedResult {
  managerSigsPolicyId: string;
  managerListPolicyId: string;
  whitelistPolicyId: string;
  initTxHash: string;
  tokenPolicyId: string;
  regTxHash: string;
}

const TX_POLL_INTERVAL = 10000;
const TX_POLL_TIMEOUT = 300000;

export function WhitelistCombinedBuildSignSubmitStep({
  onComplete,
  onError,
  onBack,
  isProcessing,
  setProcessing,
  wizardState,
}: StepComponentProps<Record<string, unknown>, CombinedResult>) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();

  const [status, setStatus] = useState<CombinedStatus>('idle');
  const [errorMessage, setErrorMessage] = useState('');
  const [pollAttempt, setPollAttempt] = useState(0);

  // Transaction state
  const [managerSigsPolicyId, setManagerSigsPolicyId] = useState('');
  const [managerListPolicyId, setManagerListPolicyId] = useState('');
  const [whitelistPolicyId, setWhitelistPolicyId] = useState('');
  const [initUnsignedCbor, setInitUnsignedCbor] = useState('');
  const [addAdminUnsignedCbor, setAddAdminUnsignedCbor] = useState('');
  const [regUnsignedCbor, setRegUnsignedCbor] = useState('');
  const [tokenPolicyId, setTokenPolicyId] = useState('');
  const [initTxHash, setInitTxHash] = useState('');
  const [addAdminTxHash, setAddAdminTxHash] = useState('');
  const [regTxHash, setRegTxHash] = useState('');
  const [derivedInitTxHash, setDerivedInitTxHash] = useState('');
  const [derivedAddAdminTxHash, setDerivedAddAdminTxHash] = useState('');
  const [derivedRegTxHash, setDerivedRegTxHash] = useState('');
  const [signedInitTx, setSignedInitTx] = useState('');
  const [signedAddAdminTx, setSignedAddAdminTx] = useState('');
  const [signedRegTx, setSignedRegTx] = useState('');

  const abortControllerRef = useRef<AbortController | null>(null);
  const showToastRef = useRef(showToast);

  useEffect(() => { showToastRef.current = showToast; }, [showToast]);

  useEffect(() => {
    return () => {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
        abortControllerRef.current = null;
      }
    };
  }, []);

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

      const addresses = await wallet.getUsedAddresses();
      if (!addresses?.[0]) throw new Error('No wallet address found');
      const adminAddress = addresses[0];

      // --- Step 1: Build governance + whitelist init tx ---
      setStatus('building-init');
      showToastRef.current({
        title: 'Building Transactions',
        description: 'Building governance & whitelist initialization...',
        variant: 'default',
      });

      const initResponse = await initGovernance(
        {
          adminAddress,
          bootstrapTxHash: '',
          bootstrapOutputIndex: 0,
        },
        'whitelist-send-receive-multiadmin',
        selectedVersion?.txHash
      );

      setManagerSigsPolicyId(initResponse.managerSigsPolicyId);
      setManagerListPolicyId(initResponse.managerListPolicyId);
      setWhitelistPolicyId(initResponse.whitelistPolicyId);
      setInitUnsignedCbor(initResponse.unsignedCborTx);
      setDerivedInitTxHash(resolveTxHash(initResponse.unsignedCborTx));

      // Store add-admin tx if returned (auto-adds super-admin as whitelist manager)
      const hasAddAdminTx = !!initResponse.addAdminUnsignedCborTx;
      if (hasAddAdminTx) {
        setAddAdminUnsignedCbor(initResponse.addAdminUnsignedCborTx!);
        setDerivedAddAdminTxHash(resolveTxHash(initResponse.addAdminUnsignedCborTx!));
      }

      // --- Step 2: Build registration tx with chaining ---
      // Chain from the add-admin tx if available, otherwise from init tx
      setStatus('building-reg');
      showToastRef.current({
        title: 'Building Transactions',
        description: 'Building registration transaction...',
        variant: 'default',
      });

      const chainingTx = hasAddAdminTx
        ? initResponse.addAdminUnsignedCborTx!
        : initResponse.unsignedCborTx;

      const adminPubKeyHash = getPaymentKeyHash(adminAddress);
      const regRequest: WhitelistMultiAdminRegisterRequest = {
        substandardId: 'whitelist-send-receive-multiadmin',
        feePayerAddress: adminAddress,
        assetName: stringToHex(tokenDetails.assetName),
        quantity: tokenDetails.quantity,
        recipientAddress: tokenDetails.recipientAddress || '',
        adminPubKeyHash,
        whitelistPolicyId: initResponse.whitelistPolicyId,
        managerListPolicyId: initResponse.managerListPolicyId,
        managerSigsPolicyId: initResponse.managerSigsPolicyId,
        chainingTransactionCborHex: chainingTx,
      };

      const regResponse = await registerToken(regRequest, selectedVersion?.txHash);
      setTokenPolicyId(regResponse.policyId);
      setRegUnsignedCbor(regResponse.unsignedCborTx);
      setDerivedRegTxHash(resolveTxHash(regResponse.unsignedCborTx));

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
  }, [connected, wallet, tokenDetails, selectedVersion, onError, setProcessing]);

  // ---- SIGN BOTH & SUBMIT SEQUENTIALLY ----
  const handleSignAndSubmit = useCallback(async () => {
    if (!connected || !wallet) {
      onError('Wallet not connected');
      return;
    }

    try {
      setProcessing(true);
      setErrorMessage('');

      setStatus('signing');

      // Build list of txs to sign: init + (optional add-admin) + registration
      const txsToSign = [initUnsignedCbor];
      if (addAdminUnsignedCbor) txsToSign.push(addAdminUnsignedCbor);
      txsToSign.push(regUnsignedCbor);

      showToastRef.current({
        title: 'Sign Transactions',
        description: `Please sign ${txsToSign.length} transactions in your wallet`,
        variant: 'default',
      });

      let signedTxs: string[];
      try {
        signedTxs = await wallet.signTxs(txsToSign, true);
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err);
        if (errMsg.includes('signTxs') || errMsg.includes('not a function') || errMsg.includes('not supported')) {
          signedTxs = [];
          for (const tx of txsToSign) {
            signedTxs.push(await wallet.signTx(tx, true));
          }
        } else {
          throw err;
        }
      }

      // Map signed txs back to their roles
      let txIdx = 0;
      const signedInit = signedTxs[txIdx++];
      const signedAddAdmin = addAdminUnsignedCbor ? signedTxs[txIdx++] : '';
      const signedReg = signedTxs[txIdx];

      setSignedInitTx(signedInit);
      if (signedAddAdmin) setSignedAddAdminTx(signedAddAdmin);
      setSignedRegTx(signedReg);

      // Submit init tx
      setStatus('submitting-init');
      showToastRef.current({
        title: 'Submitting',
        description: 'Submitting governance & whitelist initialization...',
        variant: 'default',
      });

      const hash1 = await wallet.submitTx(signedInit);
      setInitTxHash(hash1);

      // Poll for init tx confirmation
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
            description: addAdminUnsignedCbor
              ? 'Governance initialized. Adding admin to manager list...'
              : 'Governance initialized. Submitting registration...',
            variant: 'success',
          });
        },
      });

      // Submit add-admin tx (if present)
      if (signedAddAdmin) {
        setStatus('submitting-add-admin');
        showToastRef.current({
          title: 'Submitting',
          description: 'Adding admin to manager list...',
          variant: 'default',
        });

        const addAdminHash = await wallet.submitTx(signedAddAdmin);
        setAddAdminTxHash(addAdminHash);

        // Poll for add-admin tx confirmation
        setStatus('polling-add-admin');
        setPollAttempt(0);
        abortControllerRef.current = new AbortController();

        await waitForTxConfirmation(addAdminHash, {
          pollInterval: TX_POLL_INTERVAL,
          timeout: TX_POLL_TIMEOUT,
          signal: abortControllerRef.current.signal,
          onPoll: (attempt) => setPollAttempt(attempt),
          onConfirmed: () => {
            showToastRef.current({
              title: 'Admin Added',
              description: 'Admin added to manager list. Submitting registration...',
              variant: 'success',
            });
          },
        });
      }

      // Submit registration tx
      setStatus('submitting-reg');
      showToastRef.current({
        title: 'Submitting',
        description: 'Submitting token registration...',
        variant: 'default',
      });

      const hash2 = await wallet.submitTx(signedReg);
      setRegTxHash(hash2);

      setStatus('success');
      showToastRef.current({
        title: 'Registration Complete!',
        description: 'Both transactions submitted successfully',
        variant: 'success',
      });

      onComplete({
        stepId: 'combined-build-sign',
        data: {
          managerSigsPolicyId,
          managerListPolicyId,
          whitelistPolicyId,
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
    connected, wallet, initUnsignedCbor, addAdminUnsignedCbor, regUnsignedCbor,
    managerSigsPolicyId, managerListPolicyId, whitelistPolicyId, tokenPolicyId,
    onComplete, onError, setProcessing,
  ]);

  // Retry registration submission only
  const handleRetryRegSubmit = useCallback(async () => {
    if (!connected || !wallet || !signedRegTx) return;

    try {
      setProcessing(true);
      setErrorMessage('');

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
          managerSigsPolicyId,
          managerListPolicyId,
          whitelistPolicyId,
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
  }, [connected, wallet, signedRegTx, initTxHash, managerSigsPolicyId, managerListPolicyId, whitelistPolicyId, tokenPolicyId, onComplete, onError, setProcessing]);

  const handleFullRetry = useCallback(() => {
    setStatus('idle');
    setErrorMessage('');
    setManagerSigsPolicyId('');
    setManagerListPolicyId('');
    setWhitelistPolicyId('');
    setInitUnsignedCbor('');
    setAddAdminUnsignedCbor('');
    setRegUnsignedCbor('');
    setTokenPolicyId('');
    setInitTxHash('');
    setAddAdminTxHash('');
    setRegTxHash('');
    setSignedInitTx('');
    setSignedAddAdminTx('');
    setSignedRegTx('');
    setDerivedInitTxHash('');
    setDerivedAddAdminTxHash('');
    setDerivedRegTxHash('');
  }, []);

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

  const PolicyIdRow = ({ label, value, color = 'text-primary-400' }: { label: string; value: string; color?: string }) => (
    <div className="p-3 bg-dark-800 rounded">
      <div className="flex items-center justify-between mb-1">
        <span className="text-xs text-dark-400">{label}</span>
        <CopyButton value={value} />
      </div>
      <p className={`text-sm ${color} font-mono break-all`}>{value}</p>
    </div>
  );

  const getStatusMessage = () => {
    switch (status) {
      case 'building-init': return 'Building governance & whitelist initialization...';
      case 'building-reg': return 'Building registration transaction...';
      case 'preview': return 'Review both transactions before signing';
      case 'signing': return 'Waiting for wallet signature...';
      case 'submitting-init': return 'Submitting initialization...';
      case 'polling-init': return 'Waiting for init tx confirmation...';
      case 'submitting-add-admin': return 'Adding admin to manager list...';
      case 'polling-add-admin': return 'Waiting for add-admin tx confirmation...';
      case 'submitting-reg': return 'Submitting token registration...';
      case 'success': return 'Registration complete!';
      case 'error': return errorMessage || 'Operation failed';
      default: return 'Ready to build and register';
    }
  };

  const isBuilding = status === 'building-init' || status === 'building-reg';
  const isSubmitting = status === 'submitting-init' || status === 'polling-init' || status === 'submitting-add-admin' || status === 'polling-add-admin' || status === 'submitting-reg';
  const isActive = isBuilding || status === 'signing' || isSubmitting;

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">
          {status === 'preview' ? 'Review & Sign' : 'Build & Register'}
        </h3>
        <p className="text-dark-300 text-sm">
          {status === 'idle'
            ? 'Build governance init and token registration transactions together.'
            : status === 'preview'
            ? 'Review the details below, then sign both transactions.'
            : 'Processing your registration...'}
        </p>
      </div>

      {/* Idle state */}
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
                <p className="text-white font-medium capitalize">Whitelist Multi-Admin</p>
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

          <Card className="p-4 bg-blue-500/10 border-blue-500/30">
            <div className="flex items-start gap-3">
              <svg className="w-5 h-5 text-blue-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <div>
                <p className="text-blue-300 font-medium text-sm">Combined Registration</p>
                <p className="text-blue-200/70 text-sm mt-1">
                  This will initialize the manager hierarchy and whitelist, add you as a whitelist manager,
                  then register your token. Three transactions will be built, signed together, and submitted sequentially.
                </p>
              </div>
            </div>
          </Card>
        </>
      )}

      {/* Active spinner */}
      {isActive && (
        <Card className="p-6 text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
          <p className="text-dark-300 font-medium">{getStatusMessage()}</p>
          {(status === 'polling-init' || status === 'polling-add-admin') && (
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

          <Card className="p-4 space-y-3">
            <h4 className="font-medium text-white">Policy IDs</h4>
            <div className="space-y-2">
              <PolicyIdRow label="Token Policy ID" value={tokenPolicyId} />
              <PolicyIdRow label="Whitelist Policy ID" value={whitelistPolicyId} color="text-green-400" />
              <PolicyIdRow label="Manager List Policy ID" value={managerListPolicyId} color="text-orange-400" />
              <PolicyIdRow label="Manager Sigs Policy ID" value={managerSigsPolicyId} color="text-yellow-400" />
            </div>
          </Card>

          <Card className="p-4 space-y-3">
            <h4 className="font-medium text-white">Transactions</h4>
            <div className="space-y-2">
              {derivedInitTxHash && (
                <TxHashRow label="1. Governance & Whitelist Init Tx" hash={derivedInitTxHash} />
              )}
              {derivedAddAdminTxHash && (
                <TxHashRow label="2. Add Admin to Manager List Tx" hash={derivedAddAdminTxHash} />
              )}
              {derivedRegTxHash && (
                <TxHashRow label={derivedAddAdminTxHash ? "3. Registration Tx" : "2. Registration Tx"} hash={derivedRegTxHash} />
              )}
            </div>
          </Card>
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
            <PolicyIdRow label="Token Policy ID" value={tokenPolicyId} />
            <PolicyIdRow label="Whitelist Policy ID" value={whitelistPolicyId} color="text-green-400" />
            <PolicyIdRow label="Manager List Policy ID" value={managerListPolicyId} color="text-orange-400" />
            {initTxHash && <TxHashRow label="Init Tx Hash" hash={initTxHash} />}
            {addAdminTxHash && <TxHashRow label="Add Admin Tx Hash" hash={addAdminTxHash} />}
            {regTxHash && <TxHashRow label="Registration Tx Hash" hash={regTxHash} />}
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
