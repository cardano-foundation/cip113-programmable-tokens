/**
 * Whitelist-Send-Receive-MultiAdmin Substandard Flow
 * Token registration with KYC compliance features:
 * - Three-tier admin hierarchy (super-admin → managers → users)
 * - Both senders and receivers must be whitelisted
 *
 * Uses combined build-sign-submit step: builds governance init + registration txs,
 * signs via CIP-103 signTxs (single wallet popup), submits sequentially.
 */

import { registerFlow, isFlowEnabled } from '../flow-registry';
import type {
  RegistrationFlow,
  WizardState,
  WhitelistMultiAdminRegistrationData,
  StepComponentProps,
} from '@/types/registration';
import { TokenDetailsStep } from '@/components/register/steps/token-details-step';
import { WhitelistCombinedBuildSignSubmitStep } from '@/components/register/steps/whitelist-multiadmin';
import { SuccessStep } from '@/components/register/steps/success-step';

// Custom success step that reads from the combined step's result
function WhitelistSuccessStep(props: StepComponentProps) {
  const combinedResult = props.wizardState.stepStates['combined-build-sign']?.result?.data as {
    managerSigsPolicyId?: string;
    managerListPolicyId?: string;
    whitelistPolicyId?: string;
    initTxHash?: string;
    tokenPolicyId?: string;
    regTxHash?: string;
  } | undefined;

  const enhancedResult = props.wizardState.finalResult || {
    policyId: combinedResult?.tokenPolicyId || '',
    txHash: combinedResult?.regTxHash || '',
    substandardId: 'whitelist-send-receive-multiadmin',
    assetName: '',
    quantity: '',
    metadata: {
      whitelistPolicyId: combinedResult?.whitelistPolicyId,
      managerListPolicyId: combinedResult?.managerListPolicyId,
      managerSigsPolicyId: combinedResult?.managerSigsPolicyId,
      initTxHash: combinedResult?.initTxHash,
    },
  };

  return <SuccessStep {...props} result={enhancedResult} />;
}

const whitelistMultiAdminFlow: RegistrationFlow = {
  id: 'whitelist-send-receive-multiadmin',
  name: 'Whitelist Multi-Admin Token',
  description: 'Programmable token with KYC compliance: multi-admin hierarchy and mandatory sender/receiver whitelist.',
  enabled: isFlowEnabled('whitelist-send-receive-multiadmin', true),
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
      component: WhitelistCombinedBuildSignSubmitStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
    {
      id: 'success',
      title: 'Complete',
      description: 'Registration complete',
      requiresWalletSign: false,
      component: WhitelistSuccessStep as React.ComponentType<StepComponentProps<unknown, unknown>>,
    },
  ],
  getInitialData: () => ({}),
  buildRegistrationRequest: (state: WizardState): WhitelistMultiAdminRegistrationData => {
    const tokenDetails = state.stepStates['token-details']?.data as {
      assetName?: string;
      quantity?: string;
      recipientAddress?: string;
    } | undefined;

    const combinedResult = state.stepStates['combined-build-sign']?.result?.data as {
      whitelistPolicyId?: string;
      managerListPolicyId?: string;
      managerSigsPolicyId?: string;
    } | undefined;

    return {
      substandardId: 'whitelist-send-receive-multiadmin',
      feePayerAddress: '',
      assetName: tokenDetails?.assetName || '',
      quantity: tokenDetails?.quantity || '',
      recipientAddress: tokenDetails?.recipientAddress,
      adminPubKeyHash: '',
      whitelistPolicyId: combinedResult?.whitelistPolicyId || '',
      managerListPolicyId: combinedResult?.managerListPolicyId || '',
      managerSigsPolicyId: combinedResult?.managerSigsPolicyId || '',
    };
  },
};

registerFlow(whitelistMultiAdminFlow);

export { whitelistMultiAdminFlow };
