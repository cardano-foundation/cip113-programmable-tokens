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
  const [isLoadingConfig, setIsLoadingConfig] = useState(true);

  useEffect(() => {
    // Fetch runtime config and filter flows
    async function loadFlows() {
      try {
        // Fetch runtime config from API
        const response = await fetch('/api/config');
        if (response.ok) {
          const config = await response.json();

          // Get all flows and apply runtime config
          const allFlows = getAllFlows(true); // Include all flows
          const enabledFlows = allFlows.filter(flow => {
            const runtimeEnabled = config.flows[flow.id];
            // Runtime config overrides build-time config
            return runtimeEnabled !== undefined ? runtimeEnabled : flow.enabled;
          });

          setFlows(enabledFlows);
        } else {
          // Fallback to build-time config
          setFlows(getAllFlows());
        }
      } catch (error) {
        console.error('Failed to load runtime config, using build-time config:', error);
        // Fallback to build-time config
        setFlows(getAllFlows());
      } finally {
        setIsLoadingConfig(false);
      }
    }

    loadFlows();
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
      {isLoadingConfig ? (
        <div className="flex items-center justify-center py-8">
          <div className="h-8 w-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
        </div>
      ) : (
        <>
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
        </>
      )}
    </div>
  );
}
