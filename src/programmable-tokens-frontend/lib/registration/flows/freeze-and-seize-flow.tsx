/**
 * Freeze-and-Seize Substandard Flow
 * Token registration with compliance features (freeze addresses, seize tokens)
 */

import { registerFlow } from '../flow-registry';
import type {
  RegistrationFlow,
  WizardState,
  FreezeAndSeizeRegistrationData,
  StepComponentProps,
} from '@/types/registration';
import { TokenDetailsStep } from '@/components/register/steps/token-details-step';
import { InitBlacklistStep } from '@/components/register/steps/freeze-and-seize';
import { BuildPreviewStep } from '@/components/register/steps/build-preview-step';
import { SignSubmitStep } from '@/components/register/steps/sign-submit-step';
import { SuccessStep } from '@/components/register/steps/success-step';

// Wrapper for BuildPreviewStep with flowId
function FreezeSeizeBuildPreviewStep(props: StepComponentProps) {
  return <BuildPreviewStep {...props} flowId="freeze-and-seize" />;
}

// Wrapper for SignSubmitStep that gets tx data from previous step
function FreezeSeizeSignSubmitStep(props: StepComponentProps) {
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

// Custom success step that includes blacklist info
function FreezeSeizeSuccessStep(props: StepComponentProps) {
  const blacklistResult = props.wizardState.stepStates['init-blacklist']?.result?.data as {
    blacklistNodePolicyId?: string;
    txHash?: string;
  } | undefined;

  const signSubmitResult = props.wizardState.stepStates['sign-submit']?.result?.data as {
    policyId?: string;
    txHash?: string;
  } | undefined;

  // Build enhanced result with blacklist info
  const enhancedResult = props.wizardState.finalResult || {
    policyId: signSubmitResult?.policyId || '',
    txHash: signSubmitResult?.txHash || '',
    substandardId: 'freeze-and-seize',
    assetName: '',
    quantity: '',
    metadata: {
      blacklistNodePolicyId: blacklistResult?.blacklistNodePolicyId,
      blacklistInitTxHash: blacklistResult?.txHash,
    },
  };

  return <SuccessStep {...props} result={enhancedResult} />;
}

const freezeAndSeizeFlow: RegistrationFlow = {
  id: 'freeze-and-seize',
  name: 'Freeze & Seize Token',
  description: 'Programmable token with compliance features: freeze addresses and seize tokens from frozen accounts.',
  steps: [
    {
      id: 'token-details',
      title: 'Token Details',
      description: 'Define your token name, supply, and recipient',
      requiresWalletSign: false,
      component: TokenDetailsStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'init-blacklist',
      title: 'Init Blacklist',
      description: 'Create the on-chain blacklist for compliance',
      requiresWalletSign: true,
      component: InitBlacklistStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'build-preview',
      title: 'Preview',
      description: 'Review your registration details',
      requiresWalletSign: false,
      component: FreezeSeizeBuildPreviewStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'sign-submit',
      title: 'Sign & Submit',
      description: 'Sign and submit the registration transaction',
      requiresWalletSign: true,
      component: FreezeSeizeSignSubmitStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'success',
      title: 'Complete',
      description: 'Registration complete',
      requiresWalletSign: false,
      component: FreezeSeizeSuccessStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
  ],
  getInitialData: () => ({}),
  buildRegistrationRequest: (state: WizardState): FreezeAndSeizeRegistrationData => {
    const tokenDetails = state.stepStates['token-details']?.data as {
      assetName?: string;
      quantity?: string;
      recipientAddress?: string;
    } | undefined;

    const blacklistResult = state.stepStates['init-blacklist']?.result?.data as {
      blacklistNodePolicyId?: string;
    } | undefined;

    return {
      substandardId: 'freeze-and-seize',
      feePayerAddress: '', // Will be filled by the step
      assetName: tokenDetails?.assetName || '',
      quantity: tokenDetails?.quantity || '',
      recipientAddress: tokenDetails?.recipientAddress,
      adminPubKeyHash: '', // Will be derived from feePayerAddress by backend
      blacklistNodePolicyId: blacklistResult?.blacklistNodePolicyId || '',
    };
  },
};

// Register the flow
registerFlow(freezeAndSeizeFlow);

export { freezeAndSeizeFlow };
