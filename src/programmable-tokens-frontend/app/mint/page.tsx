/**
 * Token Minting Page
 *
 * Multi-step wizard for minting CIP-0113 programmable tokens.
 * Guides users through form entry, transaction preview, and success.
 *
 * ## Step Flow
 * 1. **Form**: Enter token details and select substandard
 * 2. **Preview**: Review unsigned transaction and sign with wallet
 * 3. **Success**: View confirmation and transaction hash
 *
 * ## Components Used
 * - MintForm - Token parameter input
 * - TransactionPreview - Signing and submission
 * - MintSuccess - Confirmation display
 *
 * ## Data Flow
 * 1. User fills form with token name, quantity, substandard
 * 2. Backend builds unsigned transaction
 * 3. Wallet signs transaction
 * 4. Transaction submitted to network
 * 5. Success page shows tx hash
 *
 * @module app/mint/page
 */

"use client";

import { useState } from 'react';
import dynamic from 'next/dynamic';
import { PageContainer } from '@/components/layout/page-container';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { useSubstandards } from '@/hooks/use-substandards';

/**
 * Dynamically import wallet-dependent components to prevent SSR issues.
 */
const MintForm = dynamic(
  () => import('@/components/mint/mint-form').then(mod => ({ default: mod.MintForm })),
  { ssr: false }
);

const TransactionPreview = dynamic(
  () => import('@/components/mint/transaction-preview').then(mod => ({ default: mod.TransactionPreview })),
  { ssr: false }
);

const MintSuccess = dynamic(
  () => import('@/components/mint/mint-success').then(mod => ({ default: mod.MintSuccess })),
  { ssr: false }
);

/** Wizard step states */
type MintStep = 'form' | 'preview' | 'success';

/** Transaction data passed between steps */
interface TransactionData {
  unsignedTxCborHex: string;
  assetName: string;
  quantity: string;
}

/**
 * Mint page component with multi-step wizard.
 *
 * @returns React component
 */
export default function MintPage() {
  const { substandards, isLoading, error } = useSubstandards();
  const [currentStep, setCurrentStep] = useState<MintStep>('form');
  const [transactionData, setTransactionData] = useState<TransactionData | null>(null);
  const [txHash, setTxHash] = useState<string>('');

  const handleTransactionBuilt = (unsignedTxCborHex: string, assetName: string, quantity: string) => {
    setTransactionData({ unsignedTxCborHex, assetName, quantity });
    setCurrentStep('preview');
  };

  const handleTransactionSuccess = (hash: string) => {
    setTxHash(hash);
    setCurrentStep('success');
  };

  const handleCancelPreview = () => {
    setTransactionData(null);
    setCurrentStep('form');
  };

  const handleMintAnother = () => {
    setTransactionData(null);
    setTxHash('');
    setCurrentStep('form');
  };

  return (
    <PageContainer>
      <div className="max-w-2xl mx-auto">
        {/* Page Header */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-white mb-2">
            Mint Programmable Token
          </h1>
          <p className="text-dark-300">
            Create new CIP-113 tokens with embedded validation logic
          </p>
        </div>

        {/* Loading State */}
        {isLoading && (
          <Card>
            <CardContent className="py-12 text-center">
              <div className="flex justify-center mb-4">
                <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
              </div>
              <p className="text-dark-400">Loading substandards...</p>
            </CardContent>
          </Card>
        )}

        {/* Error State */}
        {error && (
          <Card>
            <CardHeader>
              <CardTitle>Error</CardTitle>
              <CardDescription>Failed to load substandards</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="p-4 bg-red-500/10 border border-red-500/20 rounded-lg">
                <p className="text-sm text-red-300">{error}</p>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Form Step */}
        {!isLoading && !error && currentStep === 'form' && (
          <Card>
            <CardHeader>
              <CardTitle>Token Details</CardTitle>
              <CardDescription>
                Enter the details for your new token
              </CardDescription>
            </CardHeader>
            <CardContent>
              <MintForm
                substandards={substandards}
                onTransactionBuilt={handleTransactionBuilt}
              />
            </CardContent>
          </Card>
        )}

        {/* Preview Step */}
        {currentStep === 'preview' && transactionData && (
          <TransactionPreview
            unsignedTxCborHex={transactionData.unsignedTxCborHex}
            assetName={transactionData.assetName}
            quantity={transactionData.quantity}
            onSuccess={handleTransactionSuccess}
            onCancel={handleCancelPreview}
          />
        )}

        {/* Success Step */}
        {currentStep === 'success' && transactionData && (
          <MintSuccess
            txHash={txHash}
            assetName={transactionData.assetName}
            quantity={transactionData.quantity}
            onMintAnother={handleMintAnother}
          />
        )}
      </div>
    </PageContainer>
  );
}
