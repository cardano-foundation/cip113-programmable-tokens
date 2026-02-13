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
  console.log(txHash,"txhash");
  // Guards against double execution
  const hasStartedRef = useRef(false);
  const isSubmittingRef = useRef(false);
  const isGoingBackRef = useRef(false); // Track if we're going back to rebuild

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

  // Reset going back flag when unsignedCborTx changes (new transaction built)
  useEffect(() => {
    if (unsignedCborTx) {
      isGoingBackRef.current = false;
      hasStartedRef.current = false; // Allow auto-start for new transaction
    }
  }, [unsignedCborTx]);

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
      console.log('[SignSubmitStep] Signed transaction:', signedTx);
      console.log('[SignSubmitStep] Signed transaction type:', typeof signedTx);
      console.log('[SignSubmitStep] Signed transaction keys:', signedTx ? Object.keys(signedTx) : 'null/undefined');

      setStatus('submitting');

      // Submit the transaction
      let hash: string;
      try {
        hash = await wallet.submitTx(signedTx);
        console.log('[SignSubmitStep] Transaction hash from submitTx:', hash);
      } catch (submitError) {
        // Some wallets throw errors even when transaction is submitted
        // Try to extract hash from error message or signed transaction
        console.error('[SignSubmitStep] submitTx threw error:', submitError);
        console.error('[SignSubmitStep] Error type:', typeof submitError);
        console.error('[SignSubmitStep] Error instanceof Error:', submitError instanceof Error);
        if (submitError && typeof submitError === 'object') {
          console.error('[SignSubmitStep] Error object keys:', Object.keys(submitError));
          console.error('[SignSubmitStep] Full error object:', JSON.stringify(submitError, null, 2));
        }
        
        // Try to extract transaction hash from error message
        const errorMessage = submitError instanceof Error ? submitError.message : String(submitError);
        console.log('[SignSubmitStep] Error message:', errorMessage);
        const hashMatch = errorMessage.match(/[0-9a-fA-F]{64}/); // 64 char hex string (transaction hash)
        
        if (hashMatch) {
          hash = hashMatch[0];
          console.log('[SignSubmitStep] Extracted transaction hash from error message:', hash);
          // Continue with success flow
        } else {
          // Try to extract from signed transaction CBOR (if available)
          // For Lace wallet, sometimes the hash is in the error object
          if (submitError && typeof submitError === 'object') {
            console.log('[SignSubmitStep] Checking error object for hash property...');
            if ('hash' in submitError) {
              hash = String(submitError.hash);
              console.log('[SignSubmitStep] Extracted transaction hash from error object:', hash);
              // Continue with success flow
            } else if ('txHash' in submitError) {
              hash = String(submitError.txHash);
              console.log('[SignSubmitStep] Extracted transaction hash from error.txHash:', hash);
              // Continue with success flow
            } else {
              console.log('[SignSubmitStep] No hash found in error object, checking signedTx...');
              // Check if signedTx has a hash property
              if (signedTx && typeof signedTx === 'object' && 'hash' in signedTx) {
                hash = String((signedTx as any).hash);
                console.log('[SignSubmitStep] Extracted transaction hash from signedTx:', hash);
                // Continue with success flow
              } else {
                // No hash found, show error with manual proceed option
                console.warn('[SignSubmitStep] Could not extract hash, showing error to user');
                throw submitError;
              }
            }
          } else {
            // No hash found, show error with manual proceed option
            console.warn('[SignSubmitStep] Error is not an object, cannot extract hash');
            throw submitError;
          }
        }
      }

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
        
        // Enhanced error logging
        console.error('[SignSubmitStep] Transaction error:', error);
        if (error instanceof Error) {
          console.error('[SignSubmitStep] Error name:', error.name);
          console.error('[SignSubmitStep] Error message:', error.message);
          console.error('[SignSubmitStep] Error stack:', error.stack);
        }
        
        const message = error instanceof Error ? error.message : 'Failed to sign or submit transaction';
        
        // Check for BadInputsUTxO error (UTXO already spent)
        const errorInfo = error && typeof error === 'object' && 'info' in error ? String(error.info) : '';
        const errorInfoLower = errorInfo.toLowerCase();
        const messageLower = message.toLowerCase();
        
        // Try to parse JSON from error info if it contains JSON
        let parsedErrorInfo = '';
        try {
          // Extract JSON from error info if it's embedded in a string (multiline match)
          const jsonMatch = errorInfo.match(/\{[\s\S]*\}/);
          if (jsonMatch) {
            const parsed = JSON.parse(jsonMatch[0]);
            parsedErrorInfo = JSON.stringify(parsed).toLowerCase();
          }
        } catch (e) {
          // Ignore parse errors
        }
        
        const isBadInputsError = errorInfoLower.includes('badinputsutxo') || 
                                 errorInfoLower.includes('translationlogicmissinginput') ||
                                 errorInfoLower.includes('missinginput') ||
                                 errorInfoLower.includes('badinput') ||
                                 parsedErrorInfo.includes('badinputsutxo') ||
                                 parsedErrorInfo.includes('translationlogicmissinginput') ||
                                 parsedErrorInfo.includes('missinginput') ||
                                 messageLower.includes('badinputsutxo') ||
                                 messageLower.includes('missinginput') ||
                                 (messageLower.includes('utxo') && (messageLower.includes('spent') || messageLower.includes('missing')));
        
        if (isBadInputsError) {
          const badInputsMessage = 'Transaction failed: One or more UTXOs have already been spent. This usually happens when:\n' +
            '1. The transaction was already submitted\n' +
            '2. Another transaction spent the same UTXOs\n' +
            '3. The transaction took too long to sign\n\n' +
            'Please try again - the system will fetch fresh UTXOs.';
          setErrorMessage(badInputsMessage);
          showToastRef.current({
            title: 'UTXO Already Spent',
            description: 'The transaction references UTXOs that have already been spent. Please try again.',
            variant: 'error',
          });
          onErrorRef.current(badInputsMessage);
        } else {
          setErrorMessage(message);

          // Check for user rejection
          if (message.toLowerCase().includes('user declined') ||
              message.toLowerCase().includes('user rejected') ||
              message.toLowerCase().includes('cancelled') ||
              message.toLowerCase().includes('user cancel')) {
            showToastRef.current({
              title: 'Transaction Cancelled',
              description: 'You cancelled the transaction signing',
              variant: 'default',
            });
          } else {
            // Check if transaction might have been submitted despite error
            // Some wallets return errors even when transaction is submitted
            const mightBeSubmitted = message.toLowerCase().includes('submitted') ||
                                     message.toLowerCase().includes('already') ||
                                     message.toLowerCase().includes('duplicate');
            
            if (mightBeSubmitted) {
              showToastRef.current({
                title: 'Transaction May Have Been Submitted',
                description: 'The transaction might have been submitted. Please check the blockchain explorer.',
                variant: 'default',
              });
            } else {
              showToastRef.current({
                title: 'Transaction Failed',
                description: message || 'Failed to sign or submit transaction. Check console for details.',
                variant: 'error',
              });
              onErrorRef.current(message);
            }
          }
        }
      } finally {
        setProcessing(false);
      }
  }, [connected, wallet, unsignedCborTx, policyId, setProcessing]);

  // Auto-start signing when component mounts - with strict guard
  useEffect(() => {
    // Don't auto-start if we're going back to rebuild
    if (isGoingBackRef.current) {
      return;
    }

    // Only run once, ever
    if (hasStartedRef.current) {
      return;
    }

    // Don't auto-start if we're in error state (user should click retry)
    if (status === 'error') {
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
    
    // Check current error message to determine if we need to rebuild
    const currentError = errorMessage.toLowerCase();
    const isUtxoError = currentError.includes('utxo') || 
                        currentError.includes('already been spent') ||
                        currentError.includes('badinputsutxo') ||
                        currentError.includes('missinginput') ||
                        currentError.includes('translationlogicmissinginput');
    
    if (isUtxoError) {
      // UTXO error - need to rebuild transaction with fresh UTXOs
      // Set flag to prevent auto-start when going back (do this FIRST)
      isGoingBackRef.current = true;
      hasStartedRef.current = true; // Keep this true to prevent auto-start
      
      showToastRef.current({
        title: 'Rebuilding Transaction',
        description: 'Going back to rebuild transaction with fresh UTXOs',
        variant: 'default',
      });
      // Reset state
      setStatus('idle');
      setErrorMessage('');
      // Go back to rebuild transaction
      if (onBack) {
        // Small delay to ensure state is updated before navigation
        setTimeout(() => {
          onBack();
        }, 100);
      } else {
        // If no onBack, show error and suggest manual rebuild
        isGoingBackRef.current = false; // Reset if we can't go back
        setErrorMessage('Please go back to rebuild the transaction. UTXOs have been spent.');
        showToastRef.current({
          title: 'Manual Rebuild Required',
          description: 'Please use the Back button to rebuild the transaction',
          variant: 'error',
        });
      }
    } else {
      // For other errors, reset and retry the same transaction
      hasStartedRef.current = false; // Allow retry for non-UTXO errors
      isGoingBackRef.current = false; // Not going back
      setStatus('idle');
      setErrorMessage('');
      handleSignAndSubmit();
    }
  }, [handleSignAndSubmit, errorMessage, onBack]);

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

      {/* Error Details with Manual Proceed Option */}
      {status === 'error' && errorMessage && (
        <Card className="p-6 bg-red-500/10 border-2 border-red-500/50">
          <div className="space-y-4">
            <div>
              <p className="text-sm text-red-400 mb-2">
                <strong>Error:</strong> {errorMessage}
              </p>
              {errorMessage.includes('UTXO') || errorMessage.includes('already been spent') ? (
                <div className="mt-3 p-3 bg-yellow-500/10 border border-yellow-500/50 rounded-lg">
                  <p className="text-xs text-yellow-300 mb-2">
                    <strong>💡 Solution:</strong> This error usually means the UTXOs used in the transaction have been spent. 
                    This can happen if:
                  </p>
                  <ul className="text-xs text-yellow-200/70 list-disc list-inside space-y-1 mb-3">
                    <li>The transaction was already submitted</li>
                    <li>Another transaction spent the same UTXOs</li>
                    <li>The transaction took too long to sign</li>
                  </ul>
                  <p className="text-xs text-yellow-300">
                    <strong>Next steps:</strong> Click &quot;Retry&quot; below to rebuild the transaction with fresh UTXOs, 
                    or go back to rebuild the transaction from scratch.
                  </p>
                </div>
              ) : (
                <p className="text-xs text-dark-400">
                  If you signed the transaction in your wallet, it may have been submitted successfully even though an error was shown.
                </p>
              )}
            </div>
            
            {/* Only offer manual proceed when this is NOT a UTXO-already-spent error.
                For UTXO errors the user should rebuild the transaction instead. */}
            {!(errorMessage.includes('UTXO') || errorMessage.includes('already been spent')) && (
              <div className="p-4 bg-blue-500/10 border border-blue-500/50 rounded-lg">
                <p className="text-sm text-blue-300 font-medium mb-3">
                  Transaction was signed? Proceed manually:
                </p>
                <p className="text-xs text-blue-200/70 mb-4">
                  If you confirmed the transaction in your wallet, you can proceed even if the app shows an error. 
                  You can find the transaction hash in your wallet&apos;s transaction history or on Cardanoscan.
                </p>
                <div className="flex flex-col gap-3">
                  <Button
                    variant="primary"
                    className="w-full"
                    onClick={() => {
                      showToastRef.current({
                        title: 'Proceeding Manually',
                        description: 'Make sure the transaction is confirmed on-chain before proceeding',
                        variant: 'default',
                      });
                      // Complete with placeholder - the transaction should be verified on-chain
                      const placeholderHash = 'manual-proceed-' + Date.now();
                      onCompleteRef.current({
                        stepId: 'sign-submit',
                        data: {
                          policyId,
                          txHash: placeholderHash,
                          unsignedCborTx,
                        },
                        txHash: placeholderHash,
                        completedAt: Date.now(),
                      });
                    }}
                  >
                    ✓ Proceed Manually (Transaction Signed)
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => {
                      window.open('https://preview.cardanoscan.io/', '_blank');
                    }}
                  >
                    Open Cardanoscan Explorer
                  </Button>
                </div>
              </div>
            )}
          </div>
        </Card>
      )}

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
