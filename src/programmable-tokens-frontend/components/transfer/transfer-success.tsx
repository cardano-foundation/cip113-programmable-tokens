"use client";

import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { CheckCircle2, ExternalLink } from 'lucide-react';
import { truncateAddress, getExplorerTxUrl } from '@/lib/utils/format';

interface TransferSuccessProps {
  txHash: string;
  unit: string;
  quantity: string;
  recipientAddress: string;
}

// Helper to decode asset name from unit
function getAssetNameFromUnit(unit: string): string {
  if (unit.length <= 56) return unit;
  const assetNameHex = unit.substring(56);
  if (!assetNameHex) return unit;

  try {
    const decoded = Buffer.from(assetNameHex, 'hex').toString('utf8');
    return decoded || assetNameHex;
  } catch {
    return assetNameHex;
  }
}

export function TransferSuccess({
  txHash,
  unit,
  quantity,
  recipientAddress,
}: TransferSuccessProps) {
  const explorerUrl = getExplorerTxUrl(txHash);

  return (
    <Card>
      <CardContent className="py-12">
        <div className="text-center space-y-6">
          {/* Success Icon */}
          <div className="flex justify-center">
            <div className="w-16 h-16 bg-primary-500/20 rounded-full flex items-center justify-center">
              <CheckCircle2 className="h-8 w-8 text-primary-500" />
            </div>
          </div>

          {/* Success Message */}
          <div>
            <h2 className="text-2xl font-bold text-white mb-2">
              Transfer Successful!
            </h2>
            <p className="text-dark-300">
              Your tokens have been transferred successfully
            </p>
          </div>

          {/* Transfer Details */}
          <div className="bg-dark-800 rounded-lg p-6 space-y-4 text-left">
            <div className="flex justify-between items-start">
              <span className="text-sm text-dark-400">Transaction Hash</span>
              <div className="text-right">
                <p className="text-sm font-mono text-white break-all">
                  {truncateAddress(txHash, 12, 12)}
                </p>
              </div>
            </div>

            <div className="flex justify-between items-center border-t border-dark-700 pt-4">
              <span className="text-sm text-dark-400">Quantity Transferred</span>
              <Badge variant="success" size="md">
                {quantity}
              </Badge>
            </div>

            <div className="flex justify-between items-start border-t border-dark-700 pt-4">
              <span className="text-sm text-dark-400">Recipient</span>
              <p className="text-sm font-mono text-white">
                {truncateAddress(recipientAddress)}
              </p>
            </div>

            <div className="flex justify-between items-start border-t border-dark-700 pt-4">
              <span className="text-sm text-dark-400">Token</span>
              <div className="text-right">
                <p className="text-sm font-medium text-white">{getAssetNameFromUnit(unit)}</p>
                <p className="text-xs text-dark-500 font-mono mt-1">{truncateAddress(unit, 12, 12)}</p>
              </div>
            </div>
          </div>

          {/* Action Buttons */}
          <div className="flex flex-col sm:flex-row gap-3">
            <Button
              variant="secondary"
              className="flex-1"
              onClick={() => window.location.href = '/transfer'}
            >
              Transfer More Tokens
            </Button>
            <Button
              variant="primary"
              className="flex-1"
              onClick={() => window.open(explorerUrl, '_blank')}
            >
              View on Explorer
              <ExternalLink className="ml-2 h-4 w-4" />
            </Button>
          </div>

          {/* Info Note */}
          <div className="bg-primary-500/10 border border-primary-500/20 rounded-lg p-4">
            <p className="text-xs text-primary-300 text-left">
              <strong>What&apos;s Next?</strong><br />
              The tokens have been transferred to the recipient&apos;s programmable token address.
              The transfer was validated by the on-chain transfer contract according to CIP-113.
            </p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
