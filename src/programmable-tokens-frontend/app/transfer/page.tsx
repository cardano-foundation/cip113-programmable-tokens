"use client";

import { useState, useEffect, useCallback } from 'react';
import dynamic from 'next/dynamic';
import { PageContainer } from '@/components/layout/page-container';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { useToast } from '@/components/ui/use-toast';
import { ArrowRight, Wallet, Send, AlertCircle, ExternalLink } from 'lucide-react';
import { apiGet } from '@/lib/api/client';
import { validateCardanoAddress, validateQuantity } from '@/lib/utils/validation';

// Dynamically import wallet-dependent components
const WalletInfoDynamic = dynamic(
  () => import('@/components/wallet').then((mod) => ({ default: mod.WalletInfo })),
  { ssr: false }
);

interface TokenBalance {
  unit: string;
  policyId: string;
  assetName: string;
  assetNameReadable: string;
  amount: string;
}

interface TransferStep {
  step: 'select' | 'form' | 'preview' | 'success';
}

export default function TransferPage() {
  const { toast } = useToast();
  const [currentStep, setCurrentStep] = useState<TransferStep['step']>('select');
  const [tokens, setTokens] = useState<TokenBalance[]>([]);
  const [isLoadingTokens, setIsLoadingTokens] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form state
  const [selectedToken, setSelectedToken] = useState<TokenBalance | null>(null);
  const [recipientAddress, setRecipientAddress] = useState('');
  const [amount, setAmount] = useState('');
  const [addressError, setAddressError] = useState<string | null>(null);
  const [amountError, setAmountError] = useState<string | null>(null);

  // Transaction state
  const [txHash, setTxHash] = useState<string>('');

  // Hex to readable string
  const hexToString = (hex: string): string => {
    try {
      const bytes = new Uint8Array(hex.match(/.{1,2}/g)?.map(byte => parseInt(byte, 16)) || []);
      return new TextDecoder().decode(bytes);
    } catch {
      return hex;
    }
  };

  // Parse unit to extract policyId and assetName
  const parseUnit = (unit: string): { policyId: string; assetName: string } => {
    if (unit === 'lovelace') {
      return { policyId: '', assetName: 'lovelace' };
    }
    // Unit format: policyId + assetNameHex (56 char policyId + assetName)
    const policyId = unit.slice(0, 56);
    const assetName = unit.slice(56);
    return { policyId, assetName };
  };

  // Fetch programmable tokens for connected wallet
  const fetchTokens = useCallback(async (address: string) => {
    setIsLoadingTokens(true);
    setError(null);
    try {
      const balances = await apiGet<Record<string, string>>(`/balances/programmable-only/${address}`);

      const tokenList: TokenBalance[] = Object.entries(balances)
        .filter(([unit]) => unit !== 'lovelace')
        .map(([unit, amount]) => {
          const { policyId, assetName } = parseUnit(unit);
          return {
            unit,
            policyId,
            assetName,
            assetNameReadable: hexToString(assetName),
            amount,
          };
        });

      setTokens(tokenList);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch tokens');
      toast({
        title: 'Error',
        description: 'Failed to load programmable tokens',
        variant: 'error',
      });
    } finally {
      setIsLoadingTokens(false);
    }
  }, [toast]);

  // Validate recipient address
  const handleAddressChange = (value: string) => {
    setRecipientAddress(value);
    if (value) {
      const validation = validateCardanoAddress(value);
      setAddressError(validation.valid ? null : validation.error || 'Invalid address');
    } else {
      setAddressError(null);
    }
  };

  // Validate amount
  const handleAmountChange = (value: string) => {
    setAmount(value);
    if (value && selectedToken) {
      const validation = validateQuantity(value);
      if (!validation.valid) {
        setAmountError(validation.error || 'Invalid amount');
      } else if (BigInt(value) > BigInt(selectedToken.amount)) {
        setAmountError('Amount exceeds available balance');
      } else {
        setAmountError(null);
      }
    } else {
      setAmountError(null);
    }
  };

  // Handle token selection
  const handleSelectToken = (token: TokenBalance) => {
    setSelectedToken(token);
    setCurrentStep('form');
    setAmount('');
    setRecipientAddress('');
    setAddressError(null);
    setAmountError(null);
  };

  // Can proceed to preview?
  const canProceed = selectedToken &&
    recipientAddress &&
    !addressError &&
    amount &&
    !amountError;

  // Handle transfer preview
  const handlePreview = () => {
    if (canProceed) {
      setCurrentStep('preview');
    }
  };

  // Handle transfer execution (placeholder - needs backend endpoint)
  const handleTransfer = async () => {
    toast({
      title: 'Transfer Not Implemented',
      description: 'Transfer transaction building requires backend /api/v1/transfer endpoint',
      variant: 'default',
    });
    // When implemented:
    // 1. POST to /api/v1/transfer endpoint
    // 2. Sign with wallet
    // 3. Submit transaction
    // 4. Set txHash and move to success step
  };

  // Reset form
  const handleReset = () => {
    setSelectedToken(null);
    setRecipientAddress('');
    setAmount('');
    setAddressError(null);
    setAmountError(null);
    setTxHash('');
    setCurrentStep('select');
  };

  return (
    <PageContainer>
      <div className="max-w-2xl mx-auto">
        {/* Page Header */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-white mb-2">
            Transfer Programmable Tokens
          </h1>
          <p className="text-dark-300">
            Transfer CIP-113 tokens with automatic validation against protocol rules
          </p>
        </div>

        {/* Wallet Connection */}
        <div className="mb-8">
          <WalletInfoDynamic />
        </div>

        {/* Step: Token Selection */}
        {currentStep === 'select' && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Wallet className="h-5 w-5 text-primary-500" />
                Select Token
              </CardTitle>
              <CardDescription>
                Choose a programmable token to transfer
              </CardDescription>
            </CardHeader>
            <CardContent>
              {isLoadingTokens ? (
                <div className="flex justify-center py-8">
                  <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
                </div>
              ) : error ? (
                <div className="p-4 bg-red-500/10 border border-red-500/20 rounded-lg">
                  <p className="text-sm text-red-300">{error}</p>
                </div>
              ) : tokens.length === 0 ? (
                <div className="text-center py-8">
                  <AlertCircle className="h-12 w-12 text-dark-400 mx-auto mb-4" />
                  <p className="text-dark-400 mb-4">No programmable tokens found</p>
                  <p className="text-sm text-dark-500">
                    Connect your wallet and ensure you have programmable tokens at your address.
                    <br />
                    You can mint tokens from the{' '}
                    <a href="/mint" className="text-primary-500 hover:underline">Mint page</a>.
                  </p>
                  <Button
                    variant="ghost"
                    className="mt-4"
                    onClick={() => {
                      // Trigger wallet info to provide address for fetching
                      toast({
                        title: 'Connect Wallet',
                        description: 'Please connect your wallet to view tokens',
                      });
                    }}
                  >
                    Refresh
                  </Button>
                </div>
              ) : (
                <div className="space-y-3">
                  {tokens.map((token) => (
                    <button
                      key={token.unit}
                      onClick={() => handleSelectToken(token)}
                      className="w-full p-4 text-left bg-dark-900 hover:bg-dark-800 border border-dark-700 rounded-lg transition-colors"
                    >
                      <div className="flex items-center justify-between">
                        <div>
                          <p className="font-semibold text-white">{token.assetNameReadable}</p>
                          <p className="text-xs text-dark-400 font-mono truncate max-w-[300px]">
                            {token.policyId}
                          </p>
                        </div>
                        <div className="text-right">
                          <Badge variant="success">{token.amount}</Badge>
                          <ArrowRight className="h-4 w-4 text-dark-400 inline-block ml-2" />
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        )}

        {/* Step: Transfer Form */}
        {currentStep === 'form' && selectedToken && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Send className="h-5 w-5 text-primary-500" />
                Transfer Details
              </CardTitle>
              <CardDescription>
                Transferring: <span className="font-semibold">{selectedToken.assetNameReadable}</span>
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              {/* Token Info */}
              <div className="p-4 bg-dark-900 rounded-lg">
                <div className="flex justify-between items-center">
                  <span className="text-dark-400">Available Balance</span>
                  <span className="font-semibold text-white">{selectedToken.amount}</span>
                </div>
                <div className="mt-2">
                  <span className="text-xs text-dark-500 font-mono">{selectedToken.policyId}</span>
                </div>
              </div>

              {/* Recipient Address */}
              <div>
                <label className="block text-sm font-medium text-dark-300 mb-2">
                  Recipient Address
                </label>
                <Input
                  placeholder="addr_test1..."
                  value={recipientAddress}
                  onChange={(e) => handleAddressChange(e.target.value)}
                  className={addressError ? 'border-red-500' : ''}
                />
                {addressError && (
                  <p className="text-sm text-red-400 mt-1">{addressError}</p>
                )}
              </div>

              {/* Amount */}
              <div>
                <label className="block text-sm font-medium text-dark-300 mb-2">
                  Amount
                </label>
                <div className="flex gap-2">
                  <Input
                    type="text"
                    placeholder="0"
                    value={amount}
                    onChange={(e) => handleAmountChange(e.target.value)}
                    className={amountError ? 'border-red-500' : ''}
                  />
                  <Button
                    variant="ghost"
                    onClick={() => handleAmountChange(selectedToken.amount)}
                  >
                    Max
                  </Button>
                </div>
                {amountError && (
                  <p className="text-sm text-red-400 mt-1">{amountError}</p>
                )}
              </div>

              {/* Actions */}
              <div className="flex gap-4">
                <Button variant="ghost" onClick={handleReset} className="flex-1">
                  Cancel
                </Button>
                <Button
                  onClick={handlePreview}
                  disabled={!canProceed}
                  className="flex-1"
                >
                  Preview Transfer
                </Button>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Step: Preview */}
        {currentStep === 'preview' && selectedToken && (
          <Card>
            <CardHeader>
              <CardTitle>Confirm Transfer</CardTitle>
              <CardDescription>
                Review the transfer details before signing
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="space-y-4">
                <div className="flex justify-between py-2 border-b border-dark-700">
                  <span className="text-dark-400">Token</span>
                  <span className="font-semibold text-white">{selectedToken.assetNameReadable}</span>
                </div>
                <div className="flex justify-between py-2 border-b border-dark-700">
                  <span className="text-dark-400">Amount</span>
                  <span className="font-semibold text-white">{amount}</span>
                </div>
                <div className="py-2 border-b border-dark-700">
                  <span className="text-dark-400 block mb-1">Recipient</span>
                  <span className="text-sm font-mono text-white break-all">{recipientAddress}</span>
                </div>
                <div className="flex justify-between py-2">
                  <span className="text-dark-400">Policy ID</span>
                  <span className="text-xs font-mono text-dark-300 truncate max-w-[200px]">
                    {selectedToken.policyId}
                  </span>
                </div>
              </div>

              <div className="p-4 bg-yellow-500/10 border border-yellow-500/20 rounded-lg">
                <p className="text-sm text-yellow-300">
                  <AlertCircle className="h-4 w-4 inline-block mr-2" />
                  Transfer validation will be performed according to the token&apos;s transfer logic rules.
                </p>
              </div>

              <div className="flex gap-4">
                <Button variant="ghost" onClick={() => setCurrentStep('form')} className="flex-1">
                  Back
                </Button>
                <Button onClick={handleTransfer} className="flex-1">
                  Sign & Transfer
                </Button>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Step: Success */}
        {currentStep === 'success' && (
          <Card>
            <CardContent className="py-12 text-center">
              <div className="w-16 h-16 bg-green-500/20 rounded-full flex items-center justify-center mx-auto mb-6">
                <Send className="h-8 w-8 text-green-500" />
              </div>
              <h2 className="text-2xl font-bold text-white mb-2">Transfer Successful!</h2>
              <p className="text-dark-400 mb-6">Your tokens have been transferred.</p>

              {txHash && (
                <div className="mb-6">
                  <p className="text-sm text-dark-400 mb-2">Transaction Hash</p>
                  <a
                    href={`https://preview.cardanoscan.io/transaction/${txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm font-mono text-primary-500 hover:underline inline-flex items-center gap-1"
                  >
                    {txHash.slice(0, 16)}...{txHash.slice(-16)}
                    <ExternalLink className="h-3 w-3" />
                  </a>
                </div>
              )}

              <Button onClick={handleReset}>Transfer More Tokens</Button>
            </CardContent>
          </Card>
        )}
      </div>
    </PageContainer>
  );
}
