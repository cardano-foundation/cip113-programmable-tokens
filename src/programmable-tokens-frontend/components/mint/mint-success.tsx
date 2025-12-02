/**
 * Mint Success Component
 *
 * Displays a success confirmation after a token minting transaction
 * is successfully submitted to the Cardano network. Shows transaction
 * details and provides actions for viewing on explorer or minting more.
 *
 * ## Displayed Information
 * - Transaction hash (with copy button)
 * - Asset name that was minted
 * - Quantity minted
 * - Link to block explorer
 *
 * ## Actions
 * - Copy transaction hash to clipboard
 * - View transaction on CardanoScan
 * - Mint another token (reset form)
 *
 * @module components/mint/mint-success
 */

"use client";

import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

/**
 * Props for the MintSuccess component.
 */
interface MintSuccessProps {
  /** Transaction hash of the confirmed minting transaction */
  txHash: string;
  /** Asset name that was minted (hex-encoded) */
  assetName: string;
  /** Quantity that was minted (as string) */
  quantity: string;
  /** Callback to reset form and mint another token */
  onMintAnother: () => void;
}

/**
 * Success confirmation display after minting.
 *
 * Shown after a minting transaction is successfully submitted.
 * Provides transaction details and navigation options.
 *
 * @param props - Component props
 * @returns React component
 *
 * @example
 * ```tsx
 * <MintSuccess
 *   txHash="abc123..."
 *   assetName="4d79546f6b656e"
 *   quantity="1000000"
 *   onMintAnother={() => setStep('form')}
 * />
 * ```
 */
export function MintSuccess({
  txHash,
  assetName,
  quantity,
  onMintAnother,
}: MintSuccessProps) {
  const explorerUrl = `https://cardanoscan.io/transaction/${txHash}`;

  const handleCopyTxHash = () => {
    navigator.clipboard.writeText(txHash);
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle>Minting Successful!</CardTitle>
          <Badge variant="success" size="sm">
            Confirmed
          </Badge>
        </div>
        <CardDescription>
          Your tokens have been successfully minted
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Success Icon */}
        <div className="flex justify-center py-4">
          <div className="w-16 h-16 bg-primary-500/20 rounded-full flex items-center justify-center">
            <svg
              className="w-8 h-8 text-primary-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M5 13l4 4L19 7"
              />
            </svg>
          </div>
        </div>

        {/* Transaction Details */}
        <div className="space-y-3">
          <div className="flex justify-between items-center">
            <span className="text-sm text-dark-400">Token Name:</span>
            <span className="text-sm font-medium text-white">{assetName}</span>
          </div>

          <div className="flex justify-between items-center">
            <span className="text-sm text-dark-400">Quantity:</span>
            <span className="text-sm font-medium text-white">
              {Number(quantity).toLocaleString()}
            </span>
          </div>

          <div className="flex justify-between items-start">
            <span className="text-sm text-dark-400">Transaction:</span>
            <div className="text-right flex-1 ml-4">
              <code className="text-xs text-primary-400 font-mono break-all">
                {txHash}
              </code>
            </div>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex gap-2 pt-4">
          <Button
            variant="secondary"
            size="sm"
            onClick={handleCopyTxHash}
            className="flex-1"
          >
            Copy TX Hash
          </Button>
          <Button
            variant="secondary"
            size="sm"
            onClick={() => window.open(explorerUrl, '_blank')}
            className="flex-1"
          >
            View on Explorer
          </Button>
        </div>
      </CardContent>

      <CardFooter>
        <Button
          variant="primary"
          onClick={onMintAnother}
          className="w-full"
        >
          Mint Another Token
        </Button>
      </CardFooter>
    </Card>
  );
}
