"use client";

import { useState, useCallback, useMemo } from 'react';
import { useRegistrationWizard } from '@/contexts/registration-wizard-context';
import type { StepResult, StepComponentProps } from '@/types/registration';

export function WizardStepContainer() {
  const {
    state,
    dispatch,
    currentFlow,
    currentStep,
    getStepData,
    canGoBack,
  } = useRegistrationWizard();

  const [isProcessing, setIsProcessing] = useState(false);

  // Get current step data
  const stepData = useMemo(() => {
    if (!currentStep) return {};
    return getStepData(currentStep.id);
  }, [currentStep, getStepData]);

  // Handle data change
  const handleDataChange = useCallback(
    (data: Record<string, unknown>) => {
      if (!currentStep) return;
      dispatch({
        type: 'UPDATE_STEP_DATA',
        stepId: currentStep.id,
        data,
      });
    },
    [currentStep, dispatch]
  );

  // Handle step completion
  const handleComplete = useCallback(
    (result: StepResult) => {
      if (!currentStep || !currentFlow) return;

      // Mark step as complete
      dispatch({
        type: 'COMPLETE_STEP',
        stepId: currentStep.id,
        result,
      });

      // Move to next step if not the last one
      const currentIndex = currentFlow.steps.findIndex((s) => s.id === currentStep.id);
      if (currentIndex < currentFlow.steps.length - 1) {
        dispatch({ type: 'NEXT_STEP' });
      }
    },
    [currentStep, currentFlow, dispatch]
  );

  // Handle error
  const handleError = useCallback(
    (error: string) => {
      if (!currentStep) return;
      dispatch({
        type: 'SET_STEP_ERROR',
        stepId: currentStep.id,
        error,
      });
    },
    [currentStep, dispatch]
  );

  // Handle back navigation
  const handleBack = useCallback(() => {
    if (canGoBack) {
      dispatch({ type: 'PREV_STEP' });
    }
  }, [canGoBack, dispatch]);

  // Set processing state
  const handleSetProcessing = useCallback((processing: boolean) => {
    setIsProcessing(processing);
  }, []);

  if (!currentStep || !currentFlow) {
    return (
      <div className="text-center py-8 text-dark-400">
        <p>No step to display</p>
      </div>
    );
  }

  // Build props for the step component
  const stepProps: StepComponentProps = {
    stepData,
    onDataChange: handleDataChange,
    onComplete: handleComplete,
    onError: handleError,
    onBack: canGoBack ? handleBack : undefined,
    wizardState: state,
    isProcessing,
    setProcessing: handleSetProcessing,
  };

  // Render the step component
  const StepComponent = currentStep.component;

  return (
    <div className="wizard-step-container">
      <StepComponent {...stepProps} />
    </div>
  );
}
