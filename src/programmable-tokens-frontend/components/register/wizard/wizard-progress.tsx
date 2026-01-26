"use client";

import { useRegistrationWizard } from '@/contexts/registration-wizard-context';
import type { StepStatus } from '@/types/registration';

export function WizardProgress() {
  const { currentFlow, state, dispatch } = useRegistrationWizard();

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

  return (
    <div className="mb-8">
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
  );
}
