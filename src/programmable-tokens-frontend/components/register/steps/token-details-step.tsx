"use client";

import { useState, useEffect } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import type { StepComponentProps, TokenDetailsData } from '@/types/registration';

interface TokenDetailsStepProps extends StepComponentProps<TokenDetailsData, TokenDetailsData> {}

export function TokenDetailsStep({
  stepData,
  onDataChange,
  onComplete,
  onBack,
  isProcessing,
}: TokenDetailsStepProps) {
  const { connected, wallet } = useWallet();
  const [assetName, setAssetName] = useState(stepData.assetName || '');
  const [quantity, setQuantity] = useState(stepData.quantity || '');
  const [recipientAddress, setRecipientAddress] = useState(stepData.recipientAddress || '');
  const [errors, setErrors] = useState({
    assetName: '',
    quantity: '',
    recipientAddress: '',
  });

  // Auto-fill recipient with wallet address if empty
  useEffect(() => {
    const fillWalletAddress = async () => {
      if (!recipientAddress && connected && wallet) {
        try {
          const addresses = await wallet.getUsedAddresses();
          if (addresses?.[0]) {
            setRecipientAddress(addresses[0]);
            onDataChange({ recipientAddress: addresses[0] });
          }
        } catch (error) {
          console.error('Failed to get wallet address:', error);
        }
      }
    };
    fillWalletAddress();
  }, [connected, wallet, recipientAddress, onDataChange]);

  const validateForm = (): boolean => {
    const newErrors = {
      assetName: '',
      quantity: '',
      recipientAddress: '',
    };

    if (!assetName.trim()) {
      newErrors.assetName = 'Token name is required';
    } else if (assetName.length > 32) {
      newErrors.assetName = 'Token name must be 32 characters or less';
    }

    if (!quantity.trim()) {
      newErrors.quantity = 'Quantity is required';
    } else if (!/^\d+$/.test(quantity)) {
      newErrors.quantity = 'Quantity must be a positive number';
    } else if (BigInt(quantity) <= 0) {
      newErrors.quantity = 'Quantity must be greater than 0';
    }

    if (recipientAddress.trim() && !recipientAddress.startsWith('addr')) {
      newErrors.recipientAddress = 'Invalid Cardano address format';
    }

    setErrors(newErrors);
    return !Object.values(newErrors).some((error) => error !== '');
  };

  const handleChange = (field: keyof TokenDetailsData, value: string) => {
    switch (field) {
      case 'assetName':
        setAssetName(value);
        break;
      case 'quantity':
        setQuantity(value);
        break;
      case 'recipientAddress':
        setRecipientAddress(value);
        break;
    }
    onDataChange({ [field]: value });

    // Clear error when user starts typing
    if (errors[field]) {
      setErrors((prev) => ({ ...prev, [field]: '' }));
    }
  };

  const handleContinue = () => {
    if (!validateForm()) return;

    const data: TokenDetailsData = {
      assetName: assetName.trim(),
      quantity: quantity.trim(),
      recipientAddress: recipientAddress.trim() || undefined,
    };

    onComplete({
      stepId: 'token-details',
      data,
      completedAt: Date.now(),
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-white mb-2">Token Details</h3>
        <p className="text-dark-300 text-sm">
          Define your token&apos;s name, initial supply, and recipient
        </p>
      </div>

      <div className="space-y-4">
        <Input
          label="Token Name"
          value={assetName}
          onChange={(e) => handleChange('assetName', e.target.value)}
          placeholder="e.g., MyToken"
          disabled={isProcessing}
          error={errors.assetName}
          helperText="Human-readable name (max 32 characters)"
        />

        <Input
          label="Initial Supply"
          type="number"
          value={quantity}
          onChange={(e) => handleChange('quantity', e.target.value)}
          placeholder="e.g., 1000000"
          disabled={isProcessing}
          error={errors.quantity}
          helperText="Number of tokens to mint during registration"
        />

        <Input
          label="Recipient Address"
          value={recipientAddress}
          onChange={(e) => handleChange('recipientAddress', e.target.value)}
          placeholder="addr1..."
          disabled={isProcessing}
          error={errors.recipientAddress}
          helperText="Address to receive initial tokens (defaults to your wallet)"
        />
      </div>

      <div className="flex gap-3">
        {onBack && (
          <Button
            variant="outline"
            onClick={onBack}
            disabled={isProcessing}
          >
            Back
          </Button>
        )}
        <Button
          variant="primary"
          className="flex-1"
          onClick={handleContinue}
          disabled={isProcessing || !connected}
        >
          Continue
        </Button>
      </div>

      {!connected && (
        <p className="text-sm text-center text-dark-400">
          Connect your wallet to continue
        </p>
      )}
    </div>
  );
}
