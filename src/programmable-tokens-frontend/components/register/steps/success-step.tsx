"use client";

import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { CopyButton } from '@/components/ui/copy-button';
import type { RegistrationResult } from '@/types/registration';

interface SuccessStepProps {
  wizardState: {
    flowId: string | null;
    stepStates: Record<string, {
      data: Record<string, unknown>;
      result?: { data?: unknown };
    }>;
    finalResult?: RegistrationResult;
  };
  result?: RegistrationResult;
}

export function SuccessStep({
  wizardState,
  result,
}: SuccessStepProps) {
  const router = useRouter();

  // Extract all values as explicit strings
  const tokenDetailsData = wizardState.stepStates['token-details']?.data ?? {};
  const tokenName: string = typeof tokenDetailsData.assetName === 'string'
    ? tokenDetailsData.assetName
    : '';
  const tokenQuantity: string = typeof tokenDetailsData.quantity === 'string'
    ? tokenDetailsData.quantity
    : '';

  // Get results from the various steps
  const buildPreviewResult = wizardState.stepStates['build-preview']?.result?.data as { policyId?: string } | undefined;
  const signSubmitResult = wizardState.stepStates['sign-submit']?.result as { txHash?: string; data?: { policyId?: string; txHash?: string } } | undefined;
  const initBlacklistResult = wizardState.stepStates['init-blacklist']?.result?.data as { blacklistNodePolicyId?: string; txHash?: string } | undefined;

  const registrationResult = result ?? wizardState.finalResult;
  // Try multiple sources for policyId and txHash
  const policyId: string = registrationResult?.policyId
    ?? buildPreviewResult?.policyId
    ?? signSubmitResult?.data?.policyId
    ?? '';
  const txHash: string = registrationResult?.txHash
    ?? signSubmitResult?.txHash
    ?? signSubmitResult?.data?.txHash
    ?? '';
  const flowId: string = wizardState.flowId ?? '';
  const substandardId: string = registrationResult?.substandardId ?? '';
  const resultAssetName: string = registrationResult?.assetName ?? '';
  const resultQuantity: string = registrationResult?.quantity ?? '';
  // Get blacklist node policy ID from init-blacklist step or finalResult metadata
  const blacklistNodePolicyId: string = initBlacklistResult?.blacklistNodePolicyId
    ?? (registrationResult?.metadata?.blacklistNodePolicyId
      ? String(registrationResult.metadata.blacklistNodePolicyId)
      : '');

  // Computed display values
  const displayTokenName: string = tokenName || resultAssetName || '-';
  const displaySubstandard: string = flowId || substandardId || '-';
  const displayQuantity: string = tokenQuantity
    ? BigInt(tokenQuantity).toLocaleString()
    : resultQuantity
    ? BigInt(resultQuantity).toLocaleString()
    : '-';

  const getExplorerUrl = (hash: string): string => {
    return `https://preview.cardanoscan.io/transaction/${hash}`;
  };

  const handleViewExplorer = (): void => {
    if (txHash) {
      window.open(getExplorerUrl(txHash), '_blank');
    }
  };

  const handleMintMore = (): void => {
    if (policyId) {
      router.push(`/admin?policyId=${policyId}`);
    } else {
      router.push('/admin');
    }
  };

  const handleRegisterAnother = (): void => {
    router.push('/register');
    window.location.reload();
  };

  return (
    <div className="space-y-6">
      <div className="text-center">
        <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-green-500/20 flex items-center justify-center">
          <svg className="w-8 h-8 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        </div>
        <h3 className="text-xl font-semibold text-white mb-2">Token Registered!</h3>
        <p className="text-dark-300">
          Your programmable token has been successfully registered on-chain
        </p>
      </div>

      <Card className="p-4 space-y-4">
        <h4 className="font-medium text-white">Token Details</h4>
        <div className="space-y-3">
          <div>
            <span className="text-sm text-dark-400">Token Name</span>
            <p className="text-white font-medium">{displayTokenName}</p>
          </div>
          <div>
            <span className="text-sm text-dark-400">Initial Supply</span>
            <p className="text-white font-medium">{displayQuantity}</p>
          </div>
          <div>
            <span className="text-sm text-dark-400">Substandard</span>
            <p className="text-white font-medium capitalize">{displaySubstandard}</p>
          </div>
        </div>
      </Card>

      {policyId ? (
        <Card className="p-4 space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="font-medium text-white">Policy ID</h4>
            <CopyButton value={policyId} />
          </div>
          <p className="text-sm text-primary-400 font-mono break-all">{policyId}</p>
          <p className="text-xs text-dark-500">
            Use this policy ID to mint additional tokens or manage your token
          </p>
        </Card>
      ) : null}

      {txHash ? (
        <Card className="p-4 space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="font-medium text-white">Transaction Hash</h4>
            <CopyButton value={txHash} />
          </div>
          <p className="text-sm text-primary-400 font-mono break-all">{txHash}</p>
        </Card>
      ) : null}

      {blacklistNodePolicyId ? (
        <Card className="p-4 space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="font-medium text-white">Blacklist Node Policy ID</h4>
            <CopyButton value={blacklistNodePolicyId} />
          </div>
          <p className="text-sm text-orange-400 font-mono break-all">{blacklistNodePolicyId}</p>
          <p className="text-xs text-dark-500">
            Required for compliance operations (freeze/seize)
          </p>
        </Card>
      ) : null}

      <div className="space-y-3">
        {txHash ? (
          <Button
            variant="outline"
            className="w-full"
            onClick={handleViewExplorer}
          >
            <svg className="w-4 h-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
            View on Explorer
          </Button>
        ) : null}

        <Button
          variant="primary"
          className="w-full"
          onClick={handleMintMore}
        >
          Mint More Tokens
        </Button>

        <Button
          variant="ghost"
          className="w-full"
          onClick={handleRegisterAnother}
        >
          Register Another Token
        </Button>
      </div>
    </div>
  );
}
