/**
 * Dummy Substandard Flow
 * Simple token registration without compliance features
 */

import { registerFlow } from '../flow-registry';
import type { RegistrationFlow, WizardState, DummyRegistrationData } from '@/types/registration';
import { TokenDetailsStep } from '@/components/register/steps/token-details-step';
import { PreRegistrationStep } from '@/components/register/steps/pre-registration-step';
import { SuccessStep } from '@/components/register/steps/success-step';

// Create wrapper components that pass flowId to BuildPreviewStep and SignSubmitStep
import { BuildPreviewStep } from '@/components/register/steps/build-preview-step';
import { SignSubmitStep } from '@/components/register/steps/sign-submit-step';
import type { StepComponentProps } from '@/types/registration';

// Wrapper for PreRegistrationStep with flowId
function DummyPreRegistrationStep(props: StepComponentProps) {
  return <PreRegistrationStep {...props} flowId="dummy" />;
}

// Wrapper for BuildPreviewStep with flowId
function DummyBuildPreviewStep(props: StepComponentProps) {
  return <BuildPreviewStep {...props} flowId="dummy" />;
}

// Wrapper for SignSubmitStep that gets tx data from previous step
function DummySignSubmitStep(props: StepComponentProps) {
  const buildResult = props.wizardState.stepStates['build-preview']?.result?.data as {
    policyId?: string;
    unsignedCborTx?: string;
  } | undefined;

  return (
    <SignSubmitStep
      {...props}
      unsignedCborTx={buildResult?.unsignedCborTx || ''}
      policyId={buildResult?.policyId || ''}
    />
  );
}

const dummyFlow: RegistrationFlow = {
  id: 'dummy',
  name: 'Dummy Token',
  description: 'Simple programmable token without compliance features. Good for testing and basic use cases.',
  steps: [
    {
      id: 'token-details',
      title: 'Token Details',
      description: 'Define your token name, supply, and recipient',
      requiresWalletSign: false,
      component: TokenDetailsStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'pre-registration',
      title: 'Pre-Register',
      description: 'Register required stake addresses',
      requiresWalletSign: true,
      component: DummyPreRegistrationStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'build-preview',
      title: 'Preview',
      description: 'Review your registration details',
      requiresWalletSign: false,
      component: DummyBuildPreviewStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'sign-submit',
      title: 'Sign & Submit',
      description: 'Sign and submit the registration transaction',
      requiresWalletSign: true,
      component: DummySignSubmitStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'success',
      title: 'Complete',
      description: 'Registration complete',
      requiresWalletSign: false,
      component: SuccessStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
  ],
  getInitialData: () => ({}),
  buildRegistrationRequest: (state: WizardState): DummyRegistrationData => {
    const tokenDetails = state.stepStates['token-details']?.data as {
      assetName?: string;
      quantity?: string;
      recipientAddress?: string;
    } | undefined;

    return {
      substandardId: 'dummy',
      feePayerAddress: '', // Will be filled by the step
      assetName: tokenDetails?.assetName || '',
      quantity: tokenDetails?.quantity || '',
      recipientAddress: tokenDetails?.recipientAddress,
    };
  },
};

// Register the flow
registerFlow(dummyFlow);

export { dummyFlow };
