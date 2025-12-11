/**
 * Bootstrap Params Card Component
 *
 * Displays the protocol bootstrap parameters including UTxO references,
 * script hashes, and network-specific deployment information.
 *
 * @module components/deploy/bootstrap-params-card
 */

"use client";

import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Copy, Check, ExternalLink, Database, Hash, LinkIcon } from 'lucide-react';
import { ProtocolBootstrapParams } from '@/lib/api/protocol';
import { useToast } from '@/components/ui/use-toast';

/**
 * Props for BootstrapParamsCard component.
 */
interface BootstrapParamsCardProps {
  /** Bootstrap parameters data */
  params: ProtocolBootstrapParams | null;
  /** Loading state */
  isLoading?: boolean;
  /** Current network (for explorer links) */
  network?: 'mainnet' | 'preprod' | 'preview';
}

/**
 * Get explorer URL for a transaction.
 */
function getExplorerUrl(txHash: string, network: string = 'preview'): string {
  const baseUrls: Record<string, string> = {
    mainnet: 'https://cardanoscan.io/transaction',
    preprod: 'https://preprod.cardanoscan.io/transaction',
    preview: 'https://preview.cardanoscan.io/transaction',
  };
  return `${baseUrls[network] || baseUrls.preview}/${txHash}`;
}

/**
 * Truncate a hex string for display.
 */
function truncateHash(hash: string, chars: number = 8): string {
  if (hash.length <= chars * 2) return hash;
  return `${hash.slice(0, chars)}...${hash.slice(-chars)}`;
}

/**
 * Parameter display item with copy functionality.
 */
function ParamItem({
  icon: Icon,
  label,
  value,
  detail,
  link,
}: {
  icon: React.ElementType;
  label: string;
  value: string;
  detail?: string;
  link?: string;
}) {
  const { toast } = useToast();
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      toast({
        title: 'Copied!',
        description: 'Value copied to clipboard',
      });
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast({
        title: 'Failed to copy',
        description: 'Could not copy to clipboard',
        variant: 'error',
      });
    }
  };

  return (
    <div className="p-3 rounded-lg bg-dark-800/50">
      <div className="flex items-center gap-2 mb-1">
        <Icon className="w-4 h-4 text-primary-400" />
        <span className="text-sm text-dark-400">{label}</span>
      </div>
      <div className="flex items-center justify-between gap-2">
        <div className="flex-1 min-w-0">
          <p className="text-white font-mono text-sm truncate" title={value}>
            {truncateHash(value, 16)}
          </p>
          {detail && (
            <p className="text-xs text-dark-500 mt-0.5">{detail}</p>
          )}
        </div>
        <div className="flex items-center gap-1">
          <Button
            variant="ghost"
            size="sm"
            onClick={handleCopy}
            className="text-dark-400 hover:text-white h-8 w-8 p-0"
          >
            {copied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
          </Button>
          {link && (
            <a
              href={link}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center text-dark-400 hover:text-white h-8 w-8 rounded-lg hover:bg-dark-800 transition-colors"
            >
              <ExternalLink className="w-4 h-4" />
            </a>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * UTxO reference display.
 */
function UtxoRefItem({
  label,
  txHash,
  outputIndex,
  network,
}: {
  label: string;
  txHash: string;
  outputIndex: number;
  network?: string;
}) {
  return (
    <ParamItem
      icon={LinkIcon}
      label={label}
      value={`${txHash}#${outputIndex}`}
      detail={`Output Index: ${outputIndex}`}
      link={getExplorerUrl(txHash, network)}
    />
  );
}

/**
 * Bootstrap parameters card showing deployment configuration.
 *
 * @param props - Component props
 * @returns React component
 *
 * @example
 * ```tsx
 * <BootstrapParamsCard
 *   params={bootstrapParams}
 *   network="preview"
 * />
 * ```
 */
export function BootstrapParamsCard({
  params,
  isLoading = false,
  network = 'preview',
}: BootstrapParamsCardProps) {
  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Bootstrap Parameters</CardTitle>
          <CardDescription>Loading deployment configuration...</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex justify-center py-8">
            <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
        </CardContent>
      </Card>
    );
  }

  if (!params) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Bootstrap Parameters</CardTitle>
          <CardDescription>Deployment configuration not available</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="p-4 bg-yellow-500/10 border border-yellow-500/20 rounded-lg">
            <p className="text-sm text-yellow-300">
              Bootstrap parameters could not be loaded. The protocol may not be deployed
              on this network yet.
            </p>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Database className="w-5 h-5" />
              Bootstrap Parameters
            </CardTitle>
            <CardDescription>
              Protocol deployment configuration
            </CardDescription>
          </div>
          <Badge variant="info" className="capitalize">
            {network}
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Script Hashes Section */}
        <div>
          <h4 className="text-sm font-medium text-dark-300 mb-2">Script Hashes</h4>
          <div className="space-y-2">
            <ParamItem
              icon={Hash}
              label="Programmable Logic Base"
              value={params.programmableLogicBaseParams.scriptHash}
            />
            <ParamItem
              icon={Hash}
              label="Protocol Params"
              value={params.protocolParams.scriptHash}
            />
            <ParamItem
              icon={Hash}
              label="Issuance Script"
              value={params.directoryMintParams.issuanceScriptHash}
            />
          </div>
        </div>

        {/* UTxO References Section */}
        <div>
          <h4 className="text-sm font-medium text-dark-300 mb-2">Reference UTxOs</h4>
          <div className="space-y-2">
            <UtxoRefItem
              label="Protocol Params UTxO"
              txHash={params.protocolParamsUtxo.txHash}
              outputIndex={params.protocolParamsUtxo.outputIndex}
              network={network}
            />
            <UtxoRefItem
              label="Directory UTxO"
              txHash={params.directoryUtxo.txHash}
              outputIndex={params.directoryUtxo.outputIndex}
              network={network}
            />
            <UtxoRefItem
              label="Issuance UTxO"
              txHash={params.issuanceUtxo.txHash}
              outputIndex={params.issuanceUtxo.outputIndex}
              network={network}
            />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
