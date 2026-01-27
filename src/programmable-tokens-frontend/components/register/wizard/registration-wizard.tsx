"use client";

import { useEffect, useState, useCallback } from 'react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  RegistrationWizardProvider,
  useRegistrationWizard,
  useWizardResume,
} from '@/contexts/registration-wizard-context';
import { WizardProgress } from './wizard-progress';
import { WizardStepContainer } from './wizard-step-container';
import { IntermediateResultsPanel } from './intermediate-results-panel';

// Import flows to register them
import '@/lib/registration';

/**
 * Main wizard content (must be inside provider)
 */
function WizardContent() {
  const { state, dispatch, currentFlow, reset } = useRegistrationWizard();
  const { hasSavedSession, resumeSession, clearSession } = useWizardResume();
  const [showResumeDialog, setShowResumeDialog] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);

  // Check for resumable session on mount
  useEffect(() => {
    if (!isInitialized && hasSavedSession) {
      setShowResumeDialog(true);
    }
    setIsInitialized(true);
  }, [hasSavedSession, isInitialized]);

  // Handle resume
  const handleResume = useCallback(() => {
    const savedState = resumeSession();
    if (savedState) {
      dispatch({ type: 'RESTORE_STATE', state: savedState });
    }
    setShowResumeDialog(false);
  }, [resumeSession, dispatch]);

  // Handle start fresh
  const handleStartFresh = useCallback(() => {
    clearSession();
    reset();
    setShowResumeDialog(false);
  }, [clearSession, reset]);

  // Resume dialog
  if (showResumeDialog) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Resume Registration?</CardTitle>
          <CardDescription>
            You have an incomplete registration session. Would you like to continue where you left off?
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-3">
            <Button
              variant="primary"
              className="flex-1"
              onClick={handleResume}
            >
              Resume
            </Button>
            <Button
              variant="outline"
              className="flex-1"
              onClick={handleStartFresh}
            >
              Start Fresh
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  // Show flow selection if no flow selected
  if (!state.flowId || !currentFlow) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Select Token Type</CardTitle>
          <CardDescription>
            Choose the compliance model for your programmable token
          </CardDescription>
        </CardHeader>
        <CardContent>
          <FlowSelector />
        </CardContent>
      </Card>
    );
  }

  // Main wizard view
  return (
    <div className="space-y-6">
      {/* Progress Indicator */}
      <Card className="p-4">
        <WizardProgress />
      </Card>

      {/* Main Content Area */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Step Content - Takes up 2 columns on large screens */}
        <div className="lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>{currentFlow.steps[state.currentStepIndex]?.title}</CardTitle>
              {currentFlow.steps[state.currentStepIndex]?.description && (
                <CardDescription>
                  {currentFlow.steps[state.currentStepIndex].description}
                </CardDescription>
              )}
            </CardHeader>
            <CardContent>
              <WizardStepContainer />
            </CardContent>
          </Card>
        </div>

        {/* Intermediate Results Panel - 1 column on large screens */}
        <div className="lg:col-span-1">
          <IntermediateResultsPanel />
        </div>
      </div>

      {/* Global Error Display */}
      {state.globalError && (
        <Card className="border-red-500/50 bg-red-500/10">
          <CardContent className="py-4">
            <div className="flex items-start gap-3">
              <svg className="w-5 h-5 text-red-400 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <div>
                <p className="text-red-400 font-medium">Error</p>
                <p className="text-red-300 text-sm">{state.globalError}</p>
              </div>
              <Button
                variant="ghost"
                size="sm"
                className="ml-auto text-red-400"
                onClick={() => dispatch({ type: 'CLEAR_GLOBAL_ERROR' })}
              >
                Dismiss
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

/**
 * Initial flow selector (shown when no flow is selected)
 */
function FlowSelector() {
  const { dispatch } = useRegistrationWizard();

  // Import and use SelectSubstandardStep
  const { SelectSubstandardStep } = require('@/components/register/steps/select-substandard-step');

  const handleFlowSelect = (flowId: string) => {
    dispatch({ type: 'SELECT_FLOW', flowId });
  };

  return (
    <SelectSubstandardStep
      stepData={{}}
      onDataChange={() => {}}
      onComplete={(result: { data?: unknown }) => {
        if (result.data && typeof result.data === 'object' && 'substandardId' in result.data) {
          handleFlowSelect((result.data as { substandardId: string }).substandardId);
        }
      }}
      onError={() => {}}
      wizardState={{
        flowId: null,
        currentStepIndex: 0,
        stepStates: {},
        startedAt: Date.now(),
        updatedAt: Date.now(),
        isComplete: false,
      }}
      isProcessing={false}
      setProcessing={() => {}}
    />
  );
}

/**
 * Main Registration Wizard component
 * Wraps content in the wizard provider
 */
export function RegistrationWizard() {
  return (
    <RegistrationWizardProvider>
      <WizardContent />
    </RegistrationWizardProvider>
  );
}
