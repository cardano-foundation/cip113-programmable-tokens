"use client";

import { useMemo } from 'react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { CopyButton } from '@/components/ui/copy-button';
import { useRegistrationWizard } from '@/contexts/registration-wizard-context';

interface ResultItem {
  stepId: string;
  stepTitle: string;
  data: Array<{
    label: string;
    value: string;
    type: 'hash' | 'policyId' | 'address' | 'text';
  }>;
  txHash?: string;
  completedAt: number;
}

export function IntermediateResultsPanel() {
  const { state, currentFlow } = useRegistrationWizard();

  // Collect results from completed steps
  const results = useMemo<ResultItem[]>(() => {
    if (!currentFlow) return [];

    const items: ResultItem[] = [];

    currentFlow.steps.forEach((step) => {
      const stepState = state.stepStates[step.id];
      if (stepState?.status !== 'completed' || !stepState.result) return;

      const result = stepState.result;
      const dataItems: ResultItem['data'] = [];

      // Extract known result fields
      if (result.data && typeof result.data === 'object') {
        const data = result.data as Record<string, unknown>;

        // Blacklist Node Policy ID (from init-blacklist step)
        if (data.blacklistNodePolicyId) {
          dataItems.push({
            label: 'Blacklist Node Policy ID',
            value: String(data.blacklistNodePolicyId),
            type: 'policyId',
          });
        }

        // Policy ID (from sign-submit step)
        if (data.policyId) {
          dataItems.push({
            label: 'Token Policy ID',
            value: String(data.policyId),
            type: 'policyId',
          });
        }

        // Asset Name (from token-details step)
        if (data.assetName) {
          dataItems.push({
            label: 'Token Name',
            value: String(data.assetName),
            type: 'text',
          });
        }

        // Quantity (from token-details step)
        if (data.quantity) {
          dataItems.push({
            label: 'Quantity',
            value: BigInt(String(data.quantity)).toLocaleString(),
            type: 'text',
          });
        }
      }

      // Only add if there are data items or txHash
      if (dataItems.length > 0 || result.txHash) {
        items.push({
          stepId: step.id,
          stepTitle: step.title,
          data: dataItems,
          txHash: result.txHash,
          completedAt: result.completedAt,
        });
      }
    });

    return items;
  }, [currentFlow, state.stepStates]);

  // Don't show if no results
  if (results.length === 0) {
    return null;
  }

  const truncateValue = (value: string, type: ResultItem['data'][0]['type']) => {
    if (type === 'text') return value;
    if (value.length <= 20) return value;
    return `${value.slice(0, 10)}...${value.slice(-10)}`;
  };

  const getExplorerUrl = (hash: string) => {
    return `https://preview.cardanoscan.io/transaction/${hash}`;
  };

  return (
    <Card className="sticky top-4">
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Progress</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {results.map((result) => (
          <div
            key={result.stepId}
            className="pb-4 border-b border-dark-700 last:border-0 last:pb-0"
          >
            {/* Step Header */}
            <div className="flex items-center gap-2 mb-2">
              <div className="w-5 h-5 rounded-full bg-primary-500/20 flex items-center justify-center">
                <svg className="w-3 h-3 text-primary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <span className="text-sm font-medium text-white">{result.stepTitle}</span>
            </div>

            {/* Data Items */}
            <div className="ml-7 space-y-2">
              {result.data.map((item, index) => (
                <div key={index} className="space-y-0.5">
                  <span className="text-xs text-dark-400">{item.label}</span>
                  <div className="flex items-center gap-2">
                    <span
                      className={`text-xs font-mono ${
                        item.type === 'policyId'
                          ? 'text-primary-400'
                          : item.type === 'hash'
                          ? 'text-orange-400'
                          : 'text-white'
                      }`}
                      title={item.value}
                    >
                      {truncateValue(item.value, item.type)}
                    </span>
                    {item.type !== 'text' && (
                      <CopyButton value={item.value} size="sm" />
                    )}
                  </div>
                </div>
              ))}

              {/* Transaction Hash */}
              {result.txHash && (
                <div className="space-y-0.5">
                  <span className="text-xs text-dark-400">Transaction</span>
                  <div className="flex items-center gap-2">
                    <a
                      href={getExplorerUrl(result.txHash)}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-xs font-mono text-orange-400 hover:text-orange-300 underline"
                      title={result.txHash}
                    >
                      {truncateValue(result.txHash, 'hash')}
                    </a>
                    <CopyButton value={result.txHash} size="sm" />
                  </div>
                </div>
              )}

              {/* Timestamp */}
              <div className="text-xs text-dark-500">
                {new Date(result.completedAt).toLocaleTimeString()}
              </div>
            </div>
          </div>
        ))}

        {/* Resume Hint */}
        <div className="pt-2 border-t border-dark-700">
          <p className="text-xs text-dark-500">
            Your progress is saved. If you close this page, you can resume later.
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
