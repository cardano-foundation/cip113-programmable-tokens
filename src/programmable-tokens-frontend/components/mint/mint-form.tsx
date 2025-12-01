"use client";

import { useState } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { SubstandardSelector } from './substandard-selector';
import { TransactionBuilderToggle, TransactionBuilder } from './transaction-builder-toggle';
import { Substandard, MintFormData } from '@/types/api';
import { prepareMintRequest, mintToken, stringToHex } from '@/lib/api';
import { useToast } from '@/components/ui/use-toast';

interface MintFormProps {
  substandards: Substandard[];
  onTransactionBuilt: (txHex: string, assetName: string, quantity: string) => void;
}

export function MintForm({ substandards, onTransactionBuilt }: MintFormProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();

  const [tokenName, setTokenName] = useState('');
  const [quantity, setQuantity] = useState('');
  const [recipientAddress, setRecipientAddress] = useState('');
  const [substandardId, setSubstandardId] = useState('');
  const [validatorTitle, setValidatorTitle] = useState('');
  const [transactionBuilder, setTransactionBuilder] = useState<TransactionBuilder>('backend');
  const [isBuilding, setIsBuilding] = useState(false);

  const [errors, setErrors] = useState({
    tokenName: '',
    quantity: '',
    recipientAddress: '',
    substandard: '',
  });

  const handleSubstandardSelect = (selectedSubstandardId: string, selectedValidatorTitle: string) => {
    setSubstandardId(selectedSubstandardId);
    setValidatorTitle(selectedValidatorTitle);
    setErrors(prev => ({ ...prev, substandard: '' }));
  };

  const validateForm = (): boolean => {
    const newErrors = {
      tokenName: '',
      quantity: '',
      recipientAddress: '',
      substandard: '',
    };

    if (!tokenName.trim()) {
      newErrors.tokenName = 'Token name is required';
    } else if (new TextEncoder().encode(tokenName).length > 32) {
      newErrors.tokenName = 'Token name must be 32 bytes or less';
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

    if (!substandardId || !validatorTitle) {
      newErrors.substandard = 'Please select a substandard and validator';
    }

    setErrors(newErrors);
    return !Object.values(newErrors).some(error => error !== '');
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!connected) {
      showToast({
        title: 'Wallet Not Connected',
        description: 'Please connect your wallet to mint tokens',
        variant: 'error',
      });
      return;
    }

    if (!validateForm()) {
      showToast({
        title: 'Validation Error',
        description: 'Please fix the errors in the form',
        variant: 'error',
      });
      return;
    }

    try {
      setIsBuilding(true);

      // Get issuer address from wallet
      const addresses = await wallet.getUsedAddresses();
      if (!addresses || addresses.length === 0) {
        throw new Error('No addresses found in wallet');
      }
      const issuerAddress = addresses[0];

      // Prepare request with hex-encoded asset name
      const formData: MintFormData = {
        tokenName,
        quantity,
        substandardId,
        validatorTitle,
        recipientAddress: recipientAddress.trim() || undefined,
      };

      const request = prepareMintRequest(formData, issuerAddress);

      // Call backend to build transaction
      const unsignedTxCborHex = await mintToken(request);

      showToast({
        title: 'Transaction Built',
        description: 'Review and sign the transaction to mint your tokens',
        variant: 'success',
      });

      // Pass transaction to parent for preview and signing
      onTransactionBuilt(unsignedTxCborHex, tokenName, quantity);
    } catch (error) {
      console.error('Error building transaction:', error);
      showToast({
        title: 'Transaction Build Failed',
        description: error instanceof Error ? error.message : 'Failed to build transaction',
        variant: 'error',
      });
    } finally {
      setIsBuilding(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Token Name */}
      <div>
        <Input
          label="Token Name"
          type="text"
          value={tokenName}
          onChange={(e) => {
            setTokenName(e.target.value);
            setErrors(prev => ({ ...prev, tokenName: '' }));
          }}
          disabled={isBuilding}
          error={errors.tokenName}
          helperText="Human-readable name (max 32 characters)"
          placeholder="MyToken"
        />
        {tokenName && (
          <p className="mt-1 text-xs text-dark-400">
            Hex: {stringToHex(tokenName)}
          </p>
        )}
      </div>

      {/* Quantity */}
      <Input
        label="Quantity"
        type="text"
        value={quantity}
        onChange={(e) => {
          setQuantity(e.target.value);
          setErrors(prev => ({ ...prev, quantity: '' }));
        }}
        disabled={isBuilding}
        error={errors.quantity}
        helperText="Number of tokens to mint"
        placeholder="1000000"
      />

      {/* Recipient Address (Optional) */}
      <Input
        label="Recipient Address (Optional)"
        type="text"
        value={recipientAddress}
        onChange={(e) => {
          setRecipientAddress(e.target.value);
          setErrors(prev => ({ ...prev, recipientAddress: '' }));
        }}
        disabled={isBuilding}
        error={errors.recipientAddress}
        helperText="Leave empty to mint to your own address"
        placeholder="addr..."
      />

      {/* Substandard Selector */}
      <div>
        <SubstandardSelector
          substandards={substandards}
          onSelect={handleSubstandardSelect}
          disabled={isBuilding}
        />
        {errors.substandard && (
          <p className="mt-1 text-sm text-red-400">{errors.substandard}</p>
        )}
      </div>

      {/* Transaction Builder Toggle */}
      <TransactionBuilderToggle
        value={transactionBuilder}
        onChange={setTransactionBuilder}
        disabled={isBuilding}
      />

      {/* Submit Button */}
      <Button
        type="submit"
        variant="primary"
        className="w-full"
        isLoading={isBuilding}
        disabled={!connected || isBuilding}
      >
        {isBuilding ? 'Building Transaction...' : 'Build Transaction'}
      </Button>

      {!connected && (
        <p className="text-sm text-center text-dark-400">
          Connect your wallet to continue
        </p>
      )}
    </form>
  );
}
