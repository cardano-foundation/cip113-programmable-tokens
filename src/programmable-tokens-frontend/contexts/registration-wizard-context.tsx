"use client";

import React, {
  createContext,
  useContext,
  useReducer,
  useEffect,
  useCallback,
  useMemo,
  ReactNode,
} from 'react';
import type {
  WizardState,
  WizardAction,
  WizardContextValue,
  RegistrationFlow,
  WizardStep,
  StepResult,
  StepState,
  createInitialStepState,
} from '@/types/registration';
import { createInitialWizardState } from '@/types/registration';
import { getFlow } from '@/lib/registration/flow-registry';

// ============================================================================
// Constants
// ============================================================================

const STORAGE_KEY = 'registration-wizard-state';

// ============================================================================
// Reducer
// ============================================================================

function wizardReducer(state: WizardState, action: WizardAction): WizardState {
  const now = Date.now();

  switch (action.type) {
    case 'SELECT_FLOW': {
      const flow = getFlow(action.flowId);
      if (!flow) return state;

      // Initialize step states for the flow
      const stepStates: Record<string, StepState> = {};
      flow.steps.forEach((step, index) => {
        stepStates[step.id] = {
          stepId: step.id,
          status: index === 0 ? 'active' : 'pending',
          data: {},
        };
      });

      // Merge initial flow data into first step
      const initialData = flow.getInitialData();
      if (flow.steps.length > 0) {
        stepStates[flow.steps[0].id].data = initialData;
      }

      return {
        ...state,
        flowId: action.flowId,
        currentStepIndex: 0,
        stepStates,
        updatedAt: now,
        isComplete: false,
        finalResult: undefined,
        globalError: undefined,
      };
    }

    case 'NEXT_STEP': {
      const flow = getFlow(state.flowId || '');
      if (!flow) return state;

      const nextIndex = state.currentStepIndex + 1;
      if (nextIndex >= flow.steps.length) return state;

      const currentStepId = flow.steps[state.currentStepIndex]?.id;
      const nextStepId = flow.steps[nextIndex]?.id;
      if (!currentStepId || !nextStepId) return state;

      return {
        ...state,
        currentStepIndex: nextIndex,
        stepStates: {
          ...state.stepStates,
          [nextStepId]: {
            ...state.stepStates[nextStepId],
            status: 'active',
          },
        },
        updatedAt: now,
      };
    }

    case 'PREV_STEP': {
      if (state.currentStepIndex <= 0) return state;

      const flow = getFlow(state.flowId || '');
      if (!flow) return state;

      const prevIndex = state.currentStepIndex - 1;
      const prevStepId = flow.steps[prevIndex]?.id;
      if (!prevStepId) return state;

      return {
        ...state,
        currentStepIndex: prevIndex,
        stepStates: {
          ...state.stepStates,
          [prevStepId]: {
            ...state.stepStates[prevStepId],
            status: 'active',
          },
        },
        updatedAt: now,
      };
    }

    case 'GO_TO_STEP': {
      const flow = getFlow(state.flowId || '');
      if (!flow) return state;
      if (action.stepIndex < 0 || action.stepIndex >= flow.steps.length) return state;

      // Can only go back to completed steps or current step
      const targetStepId = flow.steps[action.stepIndex]?.id;
      if (!targetStepId) return state;

      const targetStepState = state.stepStates[targetStepId];
      if (
        action.stepIndex > state.currentStepIndex ||
        (targetStepState?.status !== 'completed' && action.stepIndex !== state.currentStepIndex)
      ) {
        return state;
      }

      return {
        ...state,
        currentStepIndex: action.stepIndex,
        stepStates: {
          ...state.stepStates,
          [targetStepId]: {
            ...state.stepStates[targetStepId],
            status: 'active',
          },
        },
        updatedAt: now,
      };
    }

    case 'UPDATE_STEP_DATA': {
      const stepState = state.stepStates[action.stepId];
      if (!stepState) return state;

      return {
        ...state,
        stepStates: {
          ...state.stepStates,
          [action.stepId]: {
            ...stepState,
            data: { ...stepState.data, ...action.data },
          },
        },
        updatedAt: now,
      };
    }

    case 'COMPLETE_STEP': {
      const stepState = state.stepStates[action.stepId];
      if (!stepState) return state;

      const flow = getFlow(state.flowId || '');
      const isLastStep = flow
        ? flow.steps.findIndex((s) => s.id === action.stepId) === flow.steps.length - 1
        : false;

      return {
        ...state,
        stepStates: {
          ...state.stepStates,
          [action.stepId]: {
            ...stepState,
            status: 'completed',
            result: action.result,
            error: undefined,
          },
        },
        isComplete: isLastStep,
        updatedAt: now,
      };
    }

    case 'SET_STEP_ERROR': {
      const stepState = state.stepStates[action.stepId];
      if (!stepState) return state;

      return {
        ...state,
        stepStates: {
          ...state.stepStates,
          [action.stepId]: {
            ...stepState,
            status: 'error',
            error: action.error,
          },
        },
        updatedAt: now,
      };
    }

    case 'CLEAR_STEP_ERROR': {
      const stepState = state.stepStates[action.stepId];
      if (!stepState) return state;

      return {
        ...state,
        stepStates: {
          ...state.stepStates,
          [action.stepId]: {
            ...stepState,
            status: 'active',
            error: undefined,
          },
        },
        updatedAt: now,
      };
    }

    case 'SET_GLOBAL_ERROR':
      return {
        ...state,
        globalError: action.error,
        updatedAt: now,
      };

    case 'CLEAR_GLOBAL_ERROR':
      return {
        ...state,
        globalError: undefined,
        updatedAt: now,
      };

    case 'SET_FINAL_RESULT':
      return {
        ...state,
        finalResult: action.result,
        isComplete: true,
        updatedAt: now,
      };

    case 'RESET_WIZARD':
      return createInitialWizardState();

    case 'RESTORE_STATE':
      return {
        ...action.state,
        updatedAt: now,
      };

    default:
      return state;
  }
}

// ============================================================================
// Context
// ============================================================================

const WizardContext = createContext<WizardContextValue | undefined>(undefined);

// ============================================================================
// Provider
// ============================================================================

interface WizardProviderProps {
  children: ReactNode;
}

export function RegistrationWizardProvider({ children }: WizardProviderProps) {
  const [state, dispatch] = useReducer(wizardReducer, createInitialWizardState());

  // Persist state to localStorage
  useEffect(() => {
    if (typeof window === 'undefined') return;

    // Clear saved state when wizard is complete
    if (state.isComplete) {
      localStorage.removeItem(STORAGE_KEY);
      return;
    }

    // Don't save if no flow selected
    if (!state.flowId) {
      return;
    }

    // Only save if there's meaningful progress (at least one step has data or is completed)
    const hasProgress = Object.values(state.stepStates).some(
      (s) => s.status === 'completed' || Object.keys(s.data).length > 0
    );

    if (hasProgress) {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
      } catch (error) {
        console.error('Failed to save wizard state:', error);
      }
    }
  }, [state]);

  // Get current flow
  const currentFlow = useMemo<RegistrationFlow | null>(() => {
    if (!state.flowId) return null;
    return getFlow(state.flowId) || null;
  }, [state.flowId]);

  // Get current step
  const currentStep = useMemo<WizardStep | null>(() => {
    if (!currentFlow) return null;
    return currentFlow.steps[state.currentStepIndex] || null;
  }, [currentFlow, state.currentStepIndex]);

  // Get step data helper
  const getStepData = useCallback(
    <T = Record<string, unknown>>(stepId: string): Partial<T> => {
      return (state.stepStates[stepId]?.data || {}) as Partial<T>;
    },
    [state.stepStates]
  );

  // Get step result helper
  const getStepResult = useCallback(
    <T = unknown>(stepId: string): StepResult<T> | undefined => {
      return state.stepStates[stepId]?.result as StepResult<T> | undefined;
    },
    [state.stepStates]
  );

  // Check if step is completed
  const isStepCompleted = useCallback(
    (stepId: string): boolean => {
      return state.stepStates[stepId]?.status === 'completed';
    },
    [state.stepStates]
  );

  // Can go back
  const canGoBack = useMemo(() => {
    return state.currentStepIndex > 0;
  }, [state.currentStepIndex]);

  // Can go next
  const canGoNext = useMemo(() => {
    if (!currentFlow || !currentStep) return false;
    const stepState = state.stepStates[currentStep.id];
    return (
      stepState?.status === 'completed' &&
      state.currentStepIndex < currentFlow.steps.length - 1
    );
  }, [currentFlow, currentStep, state.stepStates, state.currentStepIndex]);

  // Reset wizard
  const reset = useCallback(() => {
    dispatch({ type: 'RESET_WIZARD' });
    if (typeof window !== 'undefined') {
      localStorage.removeItem(STORAGE_KEY);
    }
  }, []);

  // Check for resumable session
  const hasResumableSession = useCallback((): boolean => {
    if (typeof window === 'undefined') return false;
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (!saved) return false;
      const parsed = JSON.parse(saved) as WizardState;
      // Valid if has flowId and not complete
      return !!parsed.flowId && !parsed.isComplete;
    } catch {
      return false;
    }
  }, []);

  // Clear saved session
  const clearSavedSession = useCallback(() => {
    if (typeof window !== 'undefined') {
      localStorage.removeItem(STORAGE_KEY);
    }
  }, []);

  const value: WizardContextValue = {
    state,
    dispatch,
    currentFlow,
    currentStep,
    getStepData,
    getStepResult,
    isStepCompleted,
    canGoBack,
    canGoNext,
    reset,
    hasResumableSession,
    clearSavedSession,
  };

  return <WizardContext.Provider value={value}>{children}</WizardContext.Provider>;
}

// ============================================================================
// Hook
// ============================================================================

export function useRegistrationWizard(): WizardContextValue {
  const context = useContext(WizardContext);
  if (context === undefined) {
    throw new Error('useRegistrationWizard must be used within a RegistrationWizardProvider');
  }
  return context;
}

// ============================================================================
// Resume Hook
// ============================================================================

/**
 * Hook to handle resuming a saved wizard session
 */
export function useWizardResume(): {
  hasSavedSession: boolean;
  resumeSession: () => WizardState | null;
  clearSession: () => void;
} {
  const hasSavedSession = useMemo(() => {
    if (typeof window === 'undefined') return false;
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (!saved) return false;
      const parsed = JSON.parse(saved) as WizardState;
      return !!parsed.flowId && !parsed.isComplete;
    } catch {
      return false;
    }
  }, []);

  const resumeSession = useCallback((): WizardState | null => {
    if (typeof window === 'undefined') return null;
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (!saved) return null;
      return JSON.parse(saved) as WizardState;
    } catch {
      return null;
    }
  }, []);

  const clearSession = useCallback(() => {
    if (typeof window !== 'undefined') {
      localStorage.removeItem(STORAGE_KEY);
    }
  }, []);

  return { hasSavedSession, resumeSession, clearSession };
}
