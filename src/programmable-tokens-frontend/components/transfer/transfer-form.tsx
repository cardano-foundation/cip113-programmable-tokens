/**
 * Transfer Form Component
 *
 * This component provides the form for transferring CIP-0113 programmable tokens
 * between addresses. Unlike standard Cardano transfers, programmable transfers
 * are validated by on-chain smart contracts that enforce the token's registered
 * transfer logic.
 *
 * ## Key Features
 *
 * - **Token Dropdown**: Shows all programmable tokens in the connected wallet
 * - **Balance Display**: Real-time balance with "Max" button for full transfers
 * - **Address Validation**: Validates Cardano bech32 address format
 * - **Protocol Version Awareness**: Transfers use the selected protocol version
 *
 * ## Transfer Flow
 *
 * 1. User connects wallet and sees their programmable token balances
 * 2. User selects a token from the dropdown
 * 3. User enters quantity and recipient address
 * 4. Form validates inputs and submits to backend
 * 5. Backend constructs unsigned transaction with:
 *    - Spend from sender's programmable address
 *    - Output to recipient's programmable address
 *    - Required validator invocations (base, global, transfer logic)
 * 6. Parent component receives tx hex for wallet signing
 *
 * ## Programmable Address Handling
 *
 * The backend automatically handles programmable address derivation:
 * - Sender's base address → sender's programmable address (for input)
 * - Recipient's base address → recipient's programmable address (for output)
 *
 * Users work with regular bech32 addresses throughout.
 *
 * ## Transfer Logic Validation
 *
 * The token's registered transfer logic is invoked during the transfer.
 * Common validation patterns include:
 * - **Permissioned**: Requires issuer signature
 * - **Blacklistable**: Rejects blacklisted addresses
 * - **Open**: Allows all transfers (dummy substandard)
 *
 * @module components/transfer/transfer-form
 */

"use client";

import { useState, useEffect, useRef } from 'react';
import { useWallet } from '@meshsdk/react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { transferToken, getWalletBalance, parseWalletBalance } from '@/lib/api';
import { useToast } from '@/components/ui/use-toast';
import { TransferTokenRequest, ParsedAsset } from '@/types/api';
import { useProtocolVersion } from '@/contexts/protocol-version-context';
import { ChevronDown, RefreshCw, Coins } from 'lucide-react';
import { cn } from '@/lib/utils';

/**
 * Props for the TransferForm component.
 */
interface TransferFormProps {
  /**
   * Callback invoked when the backend successfully builds an unsigned transaction.
   *
   * @param unsignedCborTx - The unsigned transaction in CBOR hex format
   * @param unit - The token unit (policyId + assetName) being transferred
   * @param quantity - The amount being transferred
   * @param recipientAddress - The recipient's bech32 address
   */
  onTransactionBuilt: (
    unsignedCborTx: string,
    unit: string,
    quantity: string,
    recipientAddress: string
  ) => void;
}

/**
 * Transfer form for sending programmable tokens to other addresses.
 *
 * This form handles the complete transfer flow:
 * 1. Fetches and displays the user's programmable token balances
 * 2. Allows selection of a token to transfer via dropdown
 * 3. Validates quantity (must not exceed balance) and address format
 * 4. Communicates with the backend to build the unsigned transaction
 *
 * The component is protocol-version aware and will use the currently
 * selected version from ProtocolVersionContext.
 */
export function TransferForm({ onTransactionBuilt }: TransferFormProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();
  const dropdownRef = useRef<HTMLDivElement>(null);

  const [assets, setAssets] = useState<ParsedAsset[]>([]);
  const [selectedAsset, setSelectedAsset] = useState<ParsedAsset | null>(null);
  const [isLoadingBalances, setIsLoadingBalances] = useState(false);
  const [quantity, setQuantity] = useState('');
  const [recipientAddress, setRecipientAddress] = useState('');
  const [isBuilding, setIsBuilding] = useState(false);
  const [showDropdown, setShowDropdown] = useState(false);

  const [errors, setErrors] = useState({
    token: '',
    quantity: '',
    recipientAddress: '',
  });

  // Load programmable token balances
  const loadBalances = async () => {
    if (!connected || !wallet) return;

    try {
      setIsLoadingBalances(true);
      const addresses = await wallet.getUsedAddresses();
      if (!addresses || addresses.length === 0) return;

      const address = addresses[0];
      const response = await getWalletBalance(address, selectedVersion?.txHash);
      const parsed = await parseWalletBalance(response);

      // Filter to only show programmable tokens
      const programmableAssets = parsed.assets.filter(asset => asset.isProgrammable);
      setAssets(programmableAssets);

      // Auto-select first asset if only one available
      if (programmableAssets.length === 1) {
        setSelectedAsset(programmableAssets[0]);
      }
    } catch (error) {
      console.error('Failed to load balances:', error);
      setAssets([]);
    } finally {
      setIsLoadingBalances(false);
    }
  };

  // Load balances on mount and when wallet/protocol version changes
  useEffect(() => {
    if (connected) {
      loadBalances();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connected, selectedVersion?.txHash]);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowDropdown(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleAssetSelect = (asset: ParsedAsset) => {
    setSelectedAsset(asset);
    setShowDropdown(false);
    setErrors(prev => ({ ...prev, token: '' }));
  };

  const handleSetMax = () => {
    if (selectedAsset) {
      setQuantity(selectedAsset.amount);
      setErrors(prev => ({ ...prev, quantity: '' }));
    }
  };

  const validateForm = (): boolean => {
    const newErrors = {
      token: '',
      quantity: '',
      recipientAddress: '',
    };

    if (!selectedAsset) {
      newErrors.token = 'Please select a token to transfer';
    }

    if (!quantity.trim()) {
      newErrors.quantity = 'Quantity is required';
    } else if (!/^\d+$/.test(quantity)) {
      newErrors.quantity = 'Quantity must be a positive number';
    } else if (BigInt(quantity) <= 0) {
      newErrors.quantity = 'Quantity must be greater than 0';
    } else if (selectedAsset && BigInt(quantity) > BigInt(selectedAsset.amount)) {
      newErrors.quantity = `Quantity exceeds balance (max: ${selectedAsset.amount})`;
    }

    if (!recipientAddress.trim()) {
      newErrors.recipientAddress = 'Recipient address is required';
    } else if (!recipientAddress.startsWith('addr')) {
      newErrors.recipientAddress = 'Invalid Cardano address format';
    }

    setErrors(newErrors);
    return !Object.values(newErrors).some(error => error !== '');
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!connected) {
      showToast({
        title: 'Wallet Not Connected',
        description: 'Please connect your wallet to transfer tokens',
        variant: 'error',
      });
      return;
    }

    if (!validateForm()) {
      return;
    }

    try {
      setIsBuilding(true);

      // Get sender address from wallet
      const addresses = await wallet.getUsedAddresses();
      if (!addresses || addresses.length === 0) {
        throw new Error('No addresses found in wallet');
      }
      const senderAddress = addresses[0];

      // Prepare transfer request
      const request: TransferTokenRequest = {
        senderAddress,
        unit: selectedAsset!.unit,
        quantity,
        recipientAddress: recipientAddress.trim(),
      };

      // Call backend to build transfer transaction
      const unsignedCborTx = await transferToken(request, selectedVersion?.txHash);

      showToast({
        title: 'Transaction Built',
        description: 'Review and sign the transaction to transfer your tokens',
        variant: 'success',
      });

      // Pass transaction to parent for preview and signing
      onTransactionBuilt(
        unsignedCborTx,
        selectedAsset!.unit,
        quantity,
        recipientAddress.trim()
      );
    } catch (error) {
      // Extract error message from backend response
      let errorMessage = 'Failed to build transfer transaction';
      let errorTitle = 'Transfer Failed';

      if (error instanceof Error) {
        errorMessage = error.message;

        // Check for specific error cases
        if (errorMessage.toLowerCase().includes('not enough funds')) {
          errorTitle = 'Insufficient Balance';
          errorMessage = 'You do not have enough tokens to complete this transfer.';
        } else if (errorMessage.toLowerCase().includes('could not find registry entry')) {
          errorTitle = 'Token Not Registered';
          errorMessage = 'This token policy has not been registered as a programmable token.';
        }
      }

      // Show toast notification
      showToast({
        title: errorTitle,
        description: errorMessage,
        variant: 'error',
        duration: 6000,
      });

      // Log error for debugging
      console.error('Transfer error:', { errorTitle, errorMessage });
    } finally {
      setIsBuilding(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Token Selection Dropdown */}
      <div>
        <label className="block text-sm font-medium text-white mb-2">
          Select Token
        </label>
        <div className="relative" ref={dropdownRef}>
          <button
            type="button"
            onClick={() => setShowDropdown(!showDropdown)}
            disabled={isLoadingBalances || isBuilding}
            className={cn(
              "w-full flex items-center justify-between gap-2 px-4 py-3 rounded-lg border",
              "bg-dark-800 border-dark-700 text-white",
              "hover:border-primary-500 transition-colors",
              "disabled:opacity-50 disabled:cursor-not-allowed",
              errors.token && "border-red-500"
            )}
          >
            <div className="flex items-center gap-3 flex-1 min-w-0">
              {selectedAsset ? (
                <>
                  <Coins className="h-5 w-5 text-primary-500 flex-shrink-0" />
                  <div className="text-left flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{selectedAsset.assetName}</p>
                    <p className="text-xs text-dark-400">Balance: {selectedAsset.amount}</p>
                  </div>
                  <Badge variant="success" size="sm">Programmable</Badge>
                </>
              ) : (
                <>
                  <Coins className="h-5 w-5 text-dark-500 flex-shrink-0" />
                  <span className="text-dark-400">
                    {isLoadingBalances ? 'Loading tokens...' : 'Select a token'}
                  </span>
                </>
              )}
            </div>
            <ChevronDown className={cn(
              "h-4 w-4 text-dark-400 transition-transform flex-shrink-0",
              showDropdown && "transform rotate-180"
            )} />
          </button>

          {showDropdown && (
            <div className="absolute z-10 w-full mt-2 bg-dark-800 border border-dark-700 rounded-lg shadow-xl max-h-64 overflow-y-auto">
              {assets.length === 0 ? (
                <div className="p-6 text-center">
                  <Coins className="h-12 w-12 text-dark-600 mx-auto mb-3" />
                  <p className="text-sm text-dark-300 mb-2">No programmable tokens found</p>
                  <p className="text-xs text-dark-400">
                    Register and mint tokens first
                  </p>
                </div>
              ) : (
                <>
                  <div className="p-2 border-b border-dark-700 flex items-center justify-between">
                    <p className="text-xs text-dark-400 px-2">Select token to transfer</p>
                    <button
                      type="button"
                      onClick={() => { loadBalances(); }}
                      className="p-1 hover:bg-dark-700 rounded transition-colors"
                      title="Refresh balances"
                    >
                      <RefreshCw className={cn(
                        "h-3 w-3 text-dark-400",
                        isLoadingBalances && "animate-spin"
                      )} />
                    </button>
                  </div>
                  {assets.map((asset, index) => (
                    <button
                      key={`${asset.unit}-${index}`}
                      type="button"
                      onClick={() => handleAssetSelect(asset)}
                      className={cn(
                        "w-full px-4 py-3 text-left hover:bg-dark-700 transition-colors",
                        "border-b border-dark-700 last:border-b-0",
                        selectedAsset?.unit === asset.unit && "bg-dark-700"
                      )}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-white truncate">
                            {asset.assetName}
                          </p>
                          <p className="text-xs text-dark-400 truncate" title={asset.policyId}>
                            Policy: {asset.policyId.substring(0, 16)}...
                          </p>
                        </div>
                        <div className="text-right">
                          <p className="text-sm font-bold text-accent-400">{asset.amount}</p>
                          <Badge variant="success" size="sm">Programmable</Badge>
                        </div>
                      </div>
                    </button>
                  ))}
                </>
              )}
            </div>
          )}
        </div>
        {errors.token && (
          <p className="mt-2 text-sm text-red-400">{errors.token}</p>
        )}
        <p className="mt-2 text-xs text-dark-400">
          Only programmable tokens are shown
        </p>
      </div>

      {/* Quantity */}
      <div>
        <div className="flex items-center justify-between mb-2">
          <label className="text-sm font-medium text-white">Quantity</label>
          {selectedAsset && (
            <button
              type="button"
              onClick={handleSetMax}
              disabled={isBuilding}
              className="text-xs text-primary-400 hover:text-primary-300 transition-colors"
            >
              Max: {selectedAsset.amount}
            </button>
          )}
        </div>
        <Input
          type="number"
          value={quantity}
          onChange={(e) => setQuantity(e.target.value)}
          placeholder="e.g., 100"
          disabled={isBuilding || !selectedAsset}
          error={errors.quantity}
          helperText="Number of tokens to transfer"
        />
      </div>

      {/* Recipient Address */}
      <div>
        <Input
          label="Recipient Address"
          value={recipientAddress}
          onChange={(e) => setRecipientAddress(e.target.value)}
          placeholder="addr1..."
          disabled={isBuilding}
          error={errors.recipientAddress}
          helperText="Cardano address of the recipient"
        />
      </div>

      {/* Submit Button */}
      <Button
        type="submit"
        variant="primary"
        className="w-full"
        isLoading={isBuilding}
        disabled={!connected || isBuilding || !selectedAsset}
      >
        {isBuilding ? 'Building Transaction...' : 'Transfer Tokens'}
      </Button>

      {!connected && (
        <p className="text-sm text-center text-dark-400">
          Connect your wallet to continue
        </p>
      )}
    </form>
  );
}
