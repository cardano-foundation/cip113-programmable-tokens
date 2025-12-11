/**
 * Blueprint Info Card Component
 *
 * Displays information about the loaded Plutus blueprint including
 * validator list, script hashes, and metadata.
 *
 * @module components/deploy/blueprint-info-card
 */

"use client";

import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ChevronDown, ChevronUp, FileCode, Copy, Check } from 'lucide-react';
import { ProtocolBlueprint } from '@/types/api';
import { useToast } from '@/components/ui/use-toast';

/**
 * Props for BlueprintInfoCard component.
 */
interface BlueprintInfoCardProps {
  /** The Plutus blueprint data */
  blueprint: ProtocolBlueprint | null;
  /** Loading state */
  isLoading?: boolean;
}

/**
 * Truncate a hex string for display.
 */
function truncateHash(hash: string, chars: number = 8): string {
  if (hash.length <= chars * 2) return hash;
  return `${hash.slice(0, chars)}...${hash.slice(-chars)}`;
}

/**
 * Validator item in the list.
 */
function ValidatorItem({
  title,
  hash,
}: {
  title: string;
  hash: string;
}) {
  const { toast } = useToast();
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(hash);
      setCopied(true);
      toast({
        title: 'Copied!',
        description: 'Hash copied to clipboard',
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

  // Extract validator type from title (e.g., "registry_mint.registry_mint.mint" -> "mint")
  const parts = title.split('.');
  const validatorType = parts[parts.length - 1] || 'unknown';
  const validatorName = parts[0] || title;

  return (
    <div className="flex items-center justify-between p-3 rounded-lg bg-dark-800/50 hover:bg-dark-700/50 transition-colors">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-white font-medium truncate">{validatorName}</span>
          <Badge variant="info" className="text-xs">
            {validatorType}
          </Badge>
        </div>
        <p className="text-xs text-dark-400 font-mono mt-1">{truncateHash(hash, 12)}</p>
      </div>
      <Button
        variant="ghost"
        size="sm"
        onClick={handleCopy}
        className="ml-2 text-dark-400 hover:text-white"
      >
        {copied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
      </Button>
    </div>
  );
}

/**
 * Blueprint information card showing validators and metadata.
 *
 * @param props - Component props
 * @returns React component
 *
 * @example
 * ```tsx
 * <BlueprintInfoCard blueprint={blueprint} />
 * ```
 */
export function BlueprintInfoCard({ blueprint, isLoading = false }: BlueprintInfoCardProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Plutus Blueprint</CardTitle>
          <CardDescription>Loading validator information...</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex justify-center py-8">
            <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </div>
        </CardContent>
      </Card>
    );
  }

  if (!blueprint) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Plutus Blueprint</CardTitle>
          <CardDescription>Blueprint not available</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="p-4 bg-yellow-500/10 border border-yellow-500/20 rounded-lg">
            <p className="text-sm text-yellow-300">
              The Plutus blueprint could not be loaded. This may indicate that
              the protocol has not been deployed or the backend is not properly configured.
            </p>
          </div>
        </CardContent>
      </Card>
    );
  }

  const validators = blueprint.validators || [];
  const displayValidators = isExpanded ? validators : validators.slice(0, 5);

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <FileCode className="w-5 h-5" />
              {blueprint.preamble?.title || 'Plutus Blueprint'}
            </CardTitle>
            <CardDescription>
              {blueprint.preamble?.description || 'CIP-0113 protocol validators'}
            </CardDescription>
          </div>
          {blueprint.preamble?.version && (
            <Badge variant="info">v{blueprint.preamble.version}</Badge>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {/* Stats */}
        <div className="grid grid-cols-2 gap-4 mb-4">
          <div className="p-3 rounded-lg bg-dark-800/50">
            <p className="text-2xl font-bold text-primary-400">{validators.length}</p>
            <p className="text-sm text-dark-400">Total Validators</p>
          </div>
          <div className="p-3 rounded-lg bg-dark-800/50">
            <p className="text-2xl font-bold text-primary-400">
              {new Set(validators.map(v => v.title.split('.')[0])).size}
            </p>
            <p className="text-sm text-dark-400">Unique Scripts</p>
          </div>
        </div>

        {/* Validator List */}
        <div className="space-y-2">
          {displayValidators.map((validator) => (
            <ValidatorItem
              key={validator.hash}
              title={validator.title}
              hash={validator.hash}
            />
          ))}
        </div>

        {/* Expand/Collapse Button */}
        {validators.length > 5 && (
          <Button
            variant="ghost"
            className="w-full mt-2"
            onClick={() => setIsExpanded(!isExpanded)}
          >
            {isExpanded ? (
              <>
                <ChevronUp className="w-4 h-4 mr-2" />
                Show Less
              </>
            ) : (
              <>
                <ChevronDown className="w-4 h-4 mr-2" />
                Show All ({validators.length - 5} more)
              </>
            )}
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
