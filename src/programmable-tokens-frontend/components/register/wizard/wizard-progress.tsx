"use client";

import { useState } from 'react';
import { useRegistrationWizard } from '@/contexts/registration-wizard-context';
import type { StepStatus } from '@/types/registration';
import { Button } from '@/components/ui/button';

export function WizardProgress() {
  const { currentFlow, state, dispatch, reset } = useRegistrationWizard();
  const [showResetDialog, setShowResetDialog] = useState(false);

  if (!currentFlow) return null;

  const handleStepClick = (stepIndex: number) => {
    const step = currentFlow.steps[stepIndex];
    if (!step) return;

    const stepState = state.stepStates[step.id];
    // Only allow clicking completed steps or current step
    if (stepState?.status === 'completed' || stepIndex === state.currentStepIndex) {
      dispatch({ type: 'GO_TO_STEP', stepIndex });
    }
  };

  const getStepStatus = (stepId: string): StepStatus => {
    return state.stepStates[stepId]?.status || 'pending';
  };

  const getStatusClasses = (status: StepStatus, isActive: boolean) => {
    if (isActive) {
      return {
        circle: 'bg-primary-500 border-primary-500 text-white',
        line: 'bg-primary-500',
        text: 'text-white',
      };
    }

    switch (status) {
      case 'completed':
        return {
          circle: 'bg-primary-500 border-primary-500 text-white',
          line: 'bg-primary-500',
          text: 'text-dark-300',
        };
      case 'error':
        return {
          circle: 'bg-red-500 border-red-500 text-white',
          line: 'bg-dark-600',
          text: 'text-red-400',
        };
      default:
        return {
          circle: 'bg-dark-700 border-dark-600 text-dark-400',
          line: 'bg-dark-600',
          text: 'text-dark-500',
        };
    }
  };

  const handleReset = () => {
    reset();
    setShowResetDialog(false);
  };

  return (
    <>
      {/* Reset Confirmation Dialog */}
      {showResetDialog && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-dark-800 border border-dark-700 rounded-lg p-6 max-w-md mx-4">
            <h3 className="text-lg font-semibold text-white mb-2">Start from Scratch?</h3>
            <p className="text-dark-300 mb-6">
              This will reset all progress and return you to the beginning. This action cannot be undone.
            </p>
            <div className="flex gap-3 justify-end">
              <Button
                variant="outline"
                onClick={() => setShowResetDialog(false)}
              >
                Cancel
              </Button>
              <Button
                variant="danger"
                onClick={handleReset}
              >
                Reset Everything
              </Button>
            </div>
          </div>
        </div>
      )}

      <div className="mb-8">
        {/* Header with Reset Button */}
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-sm font-medium text-dark-300">Registration Progress</h3>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setShowResetDialog(true)}
            className="text-dark-400 hover:text-red-400"
          >
            <svg className="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Start from Scratch
          </Button>
        </div>

        {/* Mobile: Horizontal scrollable */}
        <div className="flex items-center justify-between overflow-x-auto pb-2 gap-2">
          {currentFlow.steps.map((step, index) => {
          const status = getStepStatus(step.id);
          const isActive = index === state.currentStepIndex;
          const isClickable = status === 'completed' || isActive;
          const classes = getStatusClasses(status, isActive);

          return (
            <div
              key={step.id}
              className="flex items-center flex-shrink-0"
            >
              {/* Step Circle and Label */}
              <button
                type="button"
                onClick={() => handleStepClick(index)}
                disabled={!isClickable}
                className={`flex items-center gap-2 ${
                  isClickable ? 'cursor-pointer' : 'cursor-not-allowed'
                }`}
              >
                {/* Circle */}
                <div
                  className={`w-8 h-8 rounded-full border-2 flex items-center justify-center text-sm font-medium transition-colors ${classes.circle}`}
                >
                  {status === 'completed' ? (
                    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                  ) : status === 'error' ? (
                    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  ) : (
                    index + 1
                  )}
                </div>

                {/* Label (hidden on small screens) */}
                <span className={`text-sm font-medium hidden sm:block ${classes.text}`}>
                  {step.title}
                </span>
              </button>

              {/* Connector Line */}
              {index < currentFlow.steps.length - 1 && (
                <div
                  className={`w-8 sm:w-12 h-0.5 mx-2 ${
                    status === 'completed' ? 'bg-primary-500' : 'bg-dark-600'
                  }`}
                />
              )}
            </div>
          );
        })}
      </div>

        {/* Current Step Title (mobile) */}
        <div className="mt-3 text-center sm:hidden">
          <span className="text-sm text-dark-300">
            Step {state.currentStepIndex + 1}: {currentFlow.steps[state.currentStepIndex]?.title}
          </span>
        </div>
      </div>
    </>
  );
}
