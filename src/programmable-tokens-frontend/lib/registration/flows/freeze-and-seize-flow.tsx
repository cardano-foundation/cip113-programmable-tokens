/**
 * Freeze-and-Seize Substandard Flow
 * Token registration with compliance features (freeze addresses, seize tokens)
 *
 * Uses combined build-sign-submit step: builds init + registration txs together,
 * signs via CIP-103 signTxs (single wallet popup), submits sequentially.
 */

import { registerFlow, isFlowEnabled } from '../flow-registry';
import type {
  RegistrationFlow,
  WizardState,
  FreezeAndSeizeRegistrationData,
  StepComponentProps,
} from '@/types/registration';
import { TokenDetailsStep } from '@/components/register/steps/token-details-step';
import { CombinedBuildSignSubmitStep } from '@/components/register/steps/freeze-and-seize';
import { SuccessStep } from '@/components/register/steps/success-step';

// Custom success step that reads from the combined step's result
function FreezeSeizeSuccessStep(props: StepComponentProps) {
  const combinedResult = props.wizardState.stepStates['combined-build-sign']?.result?.data as {
    blacklistNodePolicyId?: string;
    initTxHash?: string;
    tokenPolicyId?: string;
    regTxHash?: string;
  } | undefined;

  // Build enhanced result with blacklist info
  const enhancedResult = props.wizardState.finalResult || {
    policyId: combinedResult?.tokenPolicyId || '',
    txHash: combinedResult?.regTxHash || '',
    substandardId: 'freeze-and-seize',
    assetName: '',
    quantity: '',
    metadata: {
      blacklistNodePolicyId: combinedResult?.blacklistNodePolicyId,
      blacklistInitTxHash: combinedResult?.initTxHash,
    },
  };

  return <SuccessStep {...props} result={enhancedResult} />;
}

const freezeAndSeizeFlow: RegistrationFlow = {
  id: 'freeze-and-seize',
  name: 'Freeze & Seize Token',
  description: 'Programmable token with compliance features: freeze addresses and seize tokens from frozen accounts.',
  enabled: isFlowEnabled('freeze-and-seize', true), // Default: enabled
  steps: [
    {
      id: 'token-details',
      title: 'Token Details',
      description: 'Define your token name, supply, and recipient',
      requiresWalletSign: false,
      component: TokenDetailsStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'combined-build-sign',
      title: 'Build & Sign',
      description: 'Build, sign, and submit both transactions',
      requiresWalletSign: true,
      component: CombinedBuildSignSubmitStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
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

    const combinedResult = state.stepStates['combined-build-sign']?.result?.data as {
      blacklistNodePolicyId?: string;
    } | undefined;

    return {
      substandardId: 'freeze-and-seize',
      feePayerAddress: '', // Will be filled by the step
      assetName: tokenDetails?.assetName || '',
      quantity: tokenDetails?.quantity || '',
      recipientAddress: tokenDetails?.recipientAddress,
      adminPubKeyHash: '', // Will be derived from feePayerAddress by backend
      blacklistNodePolicyId: combinedResult?.blacklistNodePolicyId || '',
    };
  },
};

// Register the flow
registerFlow(freezeAndSeizeFlow);

export { freezeAndSeizeFlow };
