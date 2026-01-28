/**
 * Registration Wizard Types
 * Types for the step-based registration wizard system
 */

import type { ComponentType } from 'react';

// ============================================================================
// Step & Flow Definitions
// ============================================================================

/**
 * Props passed to every step component
 */
export interface StepComponentProps<TData = unknown, TResult = unknown> {
  /** Current data for this step */
  stepData: Partial<TData>;
  /** Update step data (partial merge) */
  onDataChange: (data: Partial<TData>) => void;
  /** Mark step as complete with result */
  onComplete: (result: StepResult<TResult>) => void;
  /** Report an error */
  onError: (error: string) => void;
  /** Navigate to previous step */
  onBack?: () => void;
  /** Full wizard state */
  wizardState: WizardState;
  /** Whether the step is processing (e.g., API call in progress) */
  isProcessing: boolean;
  /** Set processing state */
  setProcessing: (processing: boolean) => void;
}

/**
 * Result of completing a step
 */
export interface StepResult<T = unknown> {
  /** Step identifier */
  stepId: string;
  /** Result data from the step */
  data: T;
  /** Transaction hash if step involved signing */
  txHash?: string;
  /** Timestamp of completion */
  completedAt: number;
}

/**
 * Definition of a single wizard step
 */
export interface WizardStep {
  /** Unique step identifier */
  id: string;
  /** Display title */
  title: string;
  /** Optional description */
  description?: string;
  /** Whether this step requires wallet signing */
  requiresWalletSign: boolean;
  /** The React component to render for this step */
  component: ComponentType<StepComponentProps<unknown, unknown>>;
  /** Optional predicate to check if step can be entered */
  canEnter?: (state: WizardState) => boolean;
  /** Optional predicate to check if step can be skipped */
  canSkip?: (state: WizardState) => boolean;
}

/**
 * Definition of a registration flow (sequence of steps)
 */
export interface RegistrationFlow {
  /** Flow identifier (matches substandardId) */
  id: string;
  /** Display name */
  name: string;
  /** Description of this flow */
  description: string;
  /** Whether this flow is enabled (can be controlled via env vars) */
  enabled: boolean;
  /** Ordered list of steps */
  steps: WizardStep[];
  /** Factory for initial flow-specific data */
  getInitialData: () => Record<string, unknown>;
  /** Build the final registration request from wizard state */
  buildRegistrationRequest: (state: WizardState) => RegistrationRequest;
}

// ============================================================================
// Wizard State
// ============================================================================

/**
 * Status of a step
 */
export type StepStatus = 'pending' | 'active' | 'completed' | 'error' | 'skipped';

/**
 * State of a single step in the wizard
 */
export interface StepState {
  /** Step identifier */
  stepId: string;
  /** Current status */
  status: StepStatus;
  /** Step-specific data (form inputs, etc.) */
  data: Record<string, unknown>;
  /** Result from completing the step */
  result?: StepResult;
  /** Error message if status is 'error' */
  error?: string;
}

/**
 * Complete wizard state
 */
export interface WizardState {
  /** Selected flow/substandard ID */
  flowId: string | null;
  /** Index of current step */
  currentStepIndex: number;
  /** State for each step, keyed by step ID */
  stepStates: Record<string, StepState>;
  /** When wizard was started */
  startedAt: number;
  /** When wizard was last updated */
  updatedAt: number;
  /** Whether wizard is complete */
  isComplete: boolean;
  /** Final result (policyId, txHash, etc.) */
  finalResult?: RegistrationResult;
  /** Global error message */
  globalError?: string;
}

/**
 * Final result of registration
 */
export interface RegistrationResult {
  policyId: string;
  txHash: string;
  substandardId: string;
  assetName: string;
  quantity: string;
  recipientAddress?: string;
  /** Additional data specific to the substandard */
  metadata?: Record<string, unknown>;
}

// ============================================================================
// Registration Request Types
// ============================================================================

/**
 * Base registration data common to all substandards
 */
export interface BaseRegistrationData {
  substandardId: string;
  feePayerAddress: string;
  assetName: string;
  quantity: string;
  recipientAddress?: string;
}

/**
 * Dummy substandard registration data
 */
export interface DummyRegistrationData extends BaseRegistrationData {
  substandardId: 'dummy';
}

/**
 * Freeze-and-seize substandard registration data
 */
export interface FreezeAndSeizeRegistrationData extends BaseRegistrationData {
  substandardId: 'freeze-and-seize';
  adminPubKeyHash: string;
  blacklistNodePolicyId: string;
}

/**
 * Union type for all registration requests
 */
export type RegistrationRequest = DummyRegistrationData | FreezeAndSeizeRegistrationData;

// ============================================================================
// Step-Specific Data Types
// ============================================================================

/**
 * Data for substandard selection step
 */
export interface SubstandardSelectionData {
  substandardId: string;
}

/**
 * Data for token details step
 */
export interface TokenDetailsData {
  assetName: string;
  quantity: string;
  recipientAddress?: string;
}

/**
 * Data for preview step
 */
export interface PreviewStepData {
  confirmed: boolean;
}

/**
 * Result from blacklist init step
 */
export interface BlacklistInitResult {
  blacklistNodePolicyId: string;
  txHash: string;
}

/**
 * Result from sign & submit step
 */
export interface SignSubmitResult {
  policyId: string;
  txHash: string;
  unsignedCborTx?: string;
}

// ============================================================================
// Wizard Actions (for reducer)
// ============================================================================

export type WizardAction =
  | { type: 'SELECT_FLOW'; flowId: string }
  | { type: 'NEXT_STEP' }
  | { type: 'PREV_STEP' }
  | { type: 'GO_TO_STEP'; stepIndex: number }
  | { type: 'UPDATE_STEP_DATA'; stepId: string; data: Record<string, unknown> }
  | { type: 'COMPLETE_STEP'; stepId: string; result: StepResult }
  | { type: 'SET_STEP_ERROR'; stepId: string; error: string }
  | { type: 'CLEAR_STEP_ERROR'; stepId: string }
  | { type: 'SET_GLOBAL_ERROR'; error: string }
  | { type: 'CLEAR_GLOBAL_ERROR' }
  | { type: 'SET_FINAL_RESULT'; result: RegistrationResult }
  | { type: 'RESET_WIZARD' }
  | { type: 'RESTORE_STATE'; state: WizardState };

// ============================================================================
// Context Types
// ============================================================================

/**
 * Wizard context value
 */
export interface WizardContextValue {
  /** Current wizard state */
  state: WizardState;
  /** Dispatch actions to update state */
  dispatch: React.Dispatch<WizardAction>;
  /** Currently active flow definition */
  currentFlow: RegistrationFlow | null;
  /** Current step definition */
  currentStep: WizardStep | null;
  /** Get data for a specific step */
  getStepData: <T = Record<string, unknown>>(stepId: string) => Partial<T>;
  /** Get result for a specific step */
  getStepResult: <T = unknown>(stepId: string) => StepResult<T> | undefined;
  /** Check if a step is completed */
  isStepCompleted: (stepId: string) => boolean;
  /** Check if wizard can go to previous step */
  canGoBack: boolean;
  /** Check if wizard can go to next step */
  canGoNext: boolean;
  /** Reset wizard to initial state */
  reset: () => void;
  /** Check if there's a resumable session */
  hasResumableSession: () => boolean;
  /** Clear saved session */
  clearSavedSession: () => void;
}

// ============================================================================
// Helpers
// ============================================================================

/**
 * Create initial state for a step
 */
export function createInitialStepState(stepId: string): StepState {
  return {
    stepId,
    status: 'pending',
    data: {},
  };
}

/**
 * Create initial wizard state
 */
export function createInitialWizardState(): WizardState {
  const now = Date.now();
  return {
    flowId: null,
    currentStepIndex: 0,
    stepStates: {},
    startedAt: now,
    updatedAt: now,
    isComplete: false,
  };
}
