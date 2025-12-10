"use client";

import { useRouter } from 'next/navigation';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { getExplorerTxUrl } from '@/lib/utils/format';

interface RegistrationSuccessProps {
  txHash: string;
  policyId: string;
  substandardId: string;
  issueContractName: string;
  tokenName: string;
  quantity: string;
}

export function RegistrationSuccess({
  txHash,
  policyId,
  substandardId,
  issueContractName,
  tokenName,
  quantity,
}: RegistrationSuccessProps) {
  const router = useRouter();
  const explorerUrl = getExplorerTxUrl(txHash);

  const handleCopyPolicyId = () => {
    navigator.clipboard.writeText(policyId);
  };

  const handleCopyTxHash = () => {
    navigator.clipboard.writeText(txHash);
  };

  const handleMintTokens = () => {
    // Navigate to mint page with pre-selected substandard and issue contract
    router.push(`/mint?substandard=${substandardId}&issueContract=${issueContractName}`);
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle>Registration Successful!</CardTitle>
          <Badge variant="success" size="sm">
            Confirmed
          </Badge>
        </div>
        <CardDescription>
          Your programmable token policy has been registered on-chain
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
          <div className="flex justify-between items-start">
            <span className="text-sm text-dark-400">Policy ID:</span>
            <div className="text-right flex-1 ml-4">
              <code className="text-xs text-primary-400 font-mono break-all">
                {policyId}
              </code>
            </div>
          </div>

          <div className="flex justify-between items-start">
            <span className="text-sm text-dark-400">Transaction:</span>
            <div className="text-right flex-1 ml-4">
              <code className="text-xs text-primary-400 font-mono break-all">
                {txHash}
              </code>
            </div>
          </div>

          <div className="flex justify-between items-center">
            <span className="text-sm text-dark-400">Token Name:</span>
            <span className="text-sm font-medium text-white">
              {tokenName}
            </span>
          </div>

          <div className="flex justify-between items-center">
            <span className="text-sm text-dark-400">Quantity:</span>
            <span className="text-sm font-medium text-white">
              {quantity}
            </span>
          </div>

          <div className="flex justify-between items-center">
            <span className="text-sm text-dark-400">Substandard:</span>
            <span className="text-sm font-medium text-white">
              {substandardId}
            </span>
          </div>

          <div className="flex justify-between items-center">
            <span className="text-sm text-dark-400">Issue Contract:</span>
            <span className="text-sm font-medium text-white">
              {issueContractName}
            </span>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex gap-2 pt-4">
          <Button
            variant="secondary"
            size="sm"
            onClick={handleCopyPolicyId}
            className="flex-1"
          >
            Copy Policy ID
          </Button>
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
          onClick={handleMintTokens}
          className="w-full"
        >
          Mint Tokens →
        </Button>
      </CardFooter>
    </Card>
  );
}
