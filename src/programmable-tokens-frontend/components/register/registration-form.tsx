/**
 * Registration Form Component
 *
 * This component provides the form for registering new programmable token policies
 * in the CIP-0113 protocol. Registration is the first step in the token lifecycle
 * and creates an on-chain registry entry linking a policy ID to its validators.
 *
 * ## Registration vs Minting
 *
 * - **Registration**: One-time operation that creates a new token policy and
 *   registers it with the protocol. Assigns the "validator triple" (issue,
 *   transfer, third-party logic).
 *
 * - **Minting**: Creates tokens under an already-registered policy. Can be done
 *   multiple times after registration.
 *
 * ## Validator Triple Selection
 *
 * Users select three validators from the chosen substandard:
 * 1. **Issue Logic**: Controls minting authorization
 * 2. **Transfer Logic**: Enforces transfer rules (required)
 * 3. **Third-Party Logic**: Optional additional validation (e.g., blacklist)
 *
 * ## Form Fields
 *
 * - **Token Name**: 1-32 characters, converted to hex for the asset name
 * - **Quantity**: Initial tokens to mint (can be > 0 for combined registration + mint)
 * - **Recipient Address**: Optional bech32 address for initial tokens
 * - **Validator Selection**: Required substandard and validator triple
 *
 * ## Transaction Flow
 *
 * 1. User fills form and selects validator triple via ValidatorTripleSelector
 * 2. Form validation checks all required fields
 * 3. Backend constructs unsigned transaction with registry insertion
 * 4. Parent component receives tx hex for wallet signing
 * 5. User signs and submits; policy is now registered
 *
 * @module components/register/registration-form
 */

"use client";

import { useState } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ValidatorTripleSelector } from './validator-triple-selector';
import { Substandard, RegisterTokenRequest } from '@/types/api';
import { registerToken, stringToHex } from '@/lib/api';
import { useToast } from '@/components/ui/use-toast';

/**
 * Props for the RegistrationForm component.
 */
interface RegistrationFormProps {
  /** Available substandard validators loaded from the backend */
  substandards: Substandard[];
  /**
   * Callback invoked when the backend successfully builds an unsigned transaction.
   *
   * @param unsignedCborTx - The unsigned transaction in CBOR hex format
   * @param policyId - The new token's policy ID (derived from validators)
   * @param substandardId - The selected substandard ID
   * @param issueContractName - The selected issue logic validator name
   * @param tokenName - The human-readable token name
   * @param quantity - The initial mint quantity
   * @param recipientAddress - Optional recipient for initial tokens
   */
  onTransactionBuilt: (
    unsignedCborTx: string,
    policyId: string,
    substandardId: string,
    issueContractName: string,
    tokenName: string,
    quantity: string,
    recipientAddress?: string
  ) => void;
}

/**
 * Registration form for creating new programmable token policies.
 *
 * This form collects all information needed to register a new token:
 * - Token metadata (name, initial quantity)
 * - Validator configuration (substandard and triple selection)
 * - Optional recipient for initial minting
 *
 * The form handles validation and communicates with the backend to build
 * the unsigned registration transaction.
 */
export function RegistrationForm({
  substandards,
  onTransactionBuilt,
}: RegistrationFormProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();

  const [tokenName, setTokenName] = useState('');
  const [quantity, setQuantity] = useState('');
  const [recipientAddress, setRecipientAddress] = useState('');
  const [substandardId, setSubstandardId] = useState('');
  const [issueContract, setIssueContract] = useState('');
  const [transferContract, setTransferContract] = useState('');
  const [thirdPartyContract, setThirdPartyContract] = useState('');
  const [isBuilding, setIsBuilding] = useState(false);

  const [errors, setErrors] = useState({
    tokenName: '',
    quantity: '',
    recipientAddress: '',
    substandard: '',
  });

  const handleValidatorSelect = (
    selectedSubstandardId: string,
    selectedIssueContract: string,
    selectedTransferContract: string,
    selectedThirdPartyContract?: string
  ) => {
    setSubstandardId(selectedSubstandardId);
    setIssueContract(selectedIssueContract);
    setTransferContract(selectedTransferContract);
    setThirdPartyContract(selectedThirdPartyContract || '');
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
    } else if (tokenName.length > 32) {
      newErrors.tokenName = 'Token name must be 32 characters or less';
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

    if (!substandardId || !issueContract || !transferContract) {
      newErrors.substandard = 'Please select substandard, issue contract, and transfer contract';
    }

    setErrors(newErrors);
    return !Object.values(newErrors).some(error => error !== '');
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!connected) {
      showToast({
        title: 'Wallet Not Connected',
        description: 'Please connect your wallet to register a token',
        variant: 'error',
      });
      return;
    }

    if (!validateForm()) {
      showToast({
        title: 'Validation Error',
        description: 'Please select all required validators',
        variant: 'error',
      });
      return;
    }

    try {
      setIsBuilding(true);

      // Get registrar address from wallet
      const addresses = await wallet.getUsedAddresses();
      if (!addresses || addresses.length === 0) {
        throw new Error('No addresses found in wallet');
      }
      const registrarAddress = addresses[0];

      // Prepare registration request
      const request: RegisterTokenRequest = {
        registrarAddress,
        substandardName: substandardId,
        substandardIssueContractName: issueContract,
        substandardTransferContractName: transferContract,
        substandardThirdPartyContractName: thirdPartyContract || '',
        assetName: stringToHex(tokenName),
        quantity,
        recipientAddress: recipientAddress.trim() || '',
      };

      // Call backend to build registration transaction
      const response = await registerToken(request);

      showToast({
        title: 'Transaction Built',
        description: 'Review and sign the transaction to register your token',
        variant: 'success',
      });

      // Pass transaction to parent for preview and signing
      onTransactionBuilt(
        response.unsignedCborTx,
        response.policyId,
        substandardId,
        issueContract,
        tokenName,
        quantity,
        recipientAddress.trim() || undefined
      );
    } catch (error) {
      // Extract error message from backend response
      let errorMessage = 'Failed to build registration transaction';
      let errorTitle = 'Registration Failed';

      if (error instanceof Error) {
        errorMessage = error.message;

        // Check if this is a "policy already registered" error
        if (errorMessage.toLowerCase().includes('already registered')) {
          errorTitle = 'Token Already Registered';
          // Extract policy ID if present in message
          const policyMatch = errorMessage.match(/policy\s+(\w+)\s+already/i);
          if (policyMatch) {
            const policyId = policyMatch[1];
            errorMessage = `Token policy ${policyId.substring(0, 16)}... has already been registered. Each policy can only be registered once.`;
          } else {
            errorMessage = 'This token policy has already been registered. Each policy can only be registered once.';
          }
        }
      }

      // Show toast notification
      showToast({
        title: errorTitle,
        description: errorMessage,
        variant: 'error',
        duration: 6000, // Show for 6 seconds
      });

      // Log error for debugging
      console.error('Registration error:', { errorTitle, errorMessage });
    } finally {
      setIsBuilding(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Validator Triple Selector */}
      <div>
        <ValidatorTripleSelector
          substandards={substandards}
          onSelect={handleValidatorSelect}
          disabled={isBuilding}
        />
        {errors.substandard && (
          <p className="mt-2 text-sm text-red-400">{errors.substandard}</p>
        )}
      </div>

      {/* Token Details Section */}
      <div className="space-y-4">
        <h3 className="text-lg font-semibold text-white">Token Details</h3>

        {/* Token Name */}
        <div>
          <Input
            label="Token Name"
            value={tokenName}
            onChange={(e) => setTokenName(e.target.value)}
            placeholder="e.g., MyToken"
            disabled={isBuilding}
            error={errors.tokenName}
            helperText="Human-readable name (max 32 characters)"
          />
        </div>

        {/* Quantity */}
        <div>
          <Input
            label="Quantity"
            type="number"
            value={quantity}
            onChange={(e) => setQuantity(e.target.value)}
            placeholder="e.g., 1000000"
            disabled={isBuilding}
            error={errors.quantity}
            helperText="Number of tokens to register/mint"
          />
        </div>

        {/* Recipient Address (Optional) */}
        <div>
          <Input
            label="Recipient Address (Optional)"
            value={recipientAddress}
            onChange={(e) => setRecipientAddress(e.target.value)}
            placeholder="addr1..."
            disabled={isBuilding}
            error={errors.recipientAddress}
            helperText="Leave empty to register to your own address"
          />
        </div>
      </div>

      {/* Submit Button */}
      <Button
        type="submit"
        variant="primary"
        className="w-full"
        isLoading={isBuilding}
        disabled={!connected || isBuilding || !issueContract || !transferContract}
      >
        {isBuilding ? 'Building Transaction...' : 'Register Token'}
      </Button>

      {!connected && (
        <p className="text-sm text-center text-dark-400">
          Connect your wallet to continue
        </p>
      )}
    </form>
  );
}
