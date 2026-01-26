"use client";

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { getAllFlows } from '@/lib/registration/flow-registry';
import type { StepComponentProps, SubstandardSelectionData, RegistrationFlow } from '@/types/registration';

interface SelectSubstandardStepProps extends StepComponentProps<SubstandardSelectionData, SubstandardSelectionData> {}

export function SelectSubstandardStep({
  stepData,
  onDataChange,
  onComplete,
  isProcessing,
}: SelectSubstandardStepProps) {
  const [flows, setFlows] = useState<RegistrationFlow[]>([]);
  const [selectedId, setSelectedId] = useState<string>(stepData.substandardId || '');

  useEffect(() => {
    // Get available flows on mount
    setFlows(getAllFlows());
  }, []);

  const handleSelect = (flowId: string) => {
    setSelectedId(flowId);
    onDataChange({ substandardId: flowId });
  };

  const handleContinue = () => {
    if (!selectedId) return;

    onComplete({
      stepId: 'select-substandard',
      data: { substandardId: selectedId },
      completedAt: Date.now(),
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">Select Token Type</h3>
        <p className="text-dark-300 text-sm">
          Choose the substandard that defines your token&apos;s compliance rules
        </p>
      </div>

      <div className="space-y-3">
        {flows.map((flow) => (
          <Card
            key={flow.id}
            className={`p-4 cursor-pointer transition-all ${
              selectedId === flow.id
                ? 'border-primary-500 bg-primary-500/10'
                : 'border-dark-600 hover:border-dark-500'
            }`}
            onClick={() => handleSelect(flow.id)}
          >
            <div className="flex items-start gap-3">
              <div
                className={`w-5 h-5 rounded-full border-2 flex items-center justify-center mt-0.5 ${
                  selectedId === flow.id
                    ? 'border-primary-500 bg-primary-500'
                    : 'border-dark-500'
                }`}
              >
                {selectedId === flow.id && (
                  <div className="w-2 h-2 rounded-full bg-white" />
                )}
              </div>
              <div className="flex-1">
                <h4 className="font-medium text-white">{flow.name}</h4>
                <p className="text-sm text-dark-400 mt-1">{flow.description}</p>
                <div className="mt-2 flex items-center gap-2">
                  <span className="text-xs text-dark-500">
                    {flow.steps.length} steps
                  </span>
                  {flow.steps.some((s) => s.requiresWalletSign) && (
                    <span className="text-xs text-primary-400 bg-primary-500/10 px-2 py-0.5 rounded">
                      Requires signing
                    </span>
                  )}
                </div>
              </div>
            </div>
          </Card>
        ))}

        {flows.length === 0 && (
          <div className="text-center py-8 text-dark-400">
            <p>No substandards available</p>
          </div>
        )}
      </div>

      <Button
        variant="primary"
        className="w-full"
        onClick={handleContinue}
        disabled={!selectedId || isProcessing}
      >
        Continue
      </Button>
    </div>
  );
}
