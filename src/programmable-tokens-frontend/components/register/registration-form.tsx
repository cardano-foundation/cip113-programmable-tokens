"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ValidatorTripleSelector } from "./validator-triple-selector";
import {
  TransactionBuilderToggle,
  TransactionBuilder,
} from "@/components/mint/transaction-builder-toggle";
import { Substandard, RegisterTokenRequest } from "@/types/api";
import {
  registerToken,
  stringToHex,
  getProtocolBlueprint,
  getProtocolBootstrap,
  getSubstandardBlueprint,
} from "@/lib/api";
import { useToast } from "@/components/ui/use-toast";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { getSubstandardHandler } from "@/lib/mesh-sdk/standard/factory";
import type { RegisterTransactionParams } from "@/lib/mesh-sdk/standard/factory";
import type { IWallet } from "@meshsdk/core";

interface RegistrationFormProps {
  substandards: Substandard[];
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

export function RegistrationForm({
  substandards,
  onTransactionBuilt,
}: RegistrationFormProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();

  const [tokenName, setTokenName] = useState("");
  const [quantity, setQuantity] = useState("");
  const [recipientAddress, setRecipientAddress] = useState("");
  const [substandardId, setSubstandardId] = useState("");
  const [issueContract, setIssueContract] = useState("");
  const [transferContract, setTransferContract] = useState("");
  const [thirdPartyContract, setThirdPartyContract] = useState("");
  const [transactionBuilder, setTransactionBuilder] =
    useState<TransactionBuilder>("backend");
  const [isBuilding, setIsBuilding] = useState(false);

  const [errors, setErrors] = useState({
    tokenName: "",
    quantity: "",
    recipientAddress: "",
    substandard: "",
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
    setThirdPartyContract(selectedThirdPartyContract || "");
    setErrors((prev) => ({ ...prev, substandard: "" }));
  };

  const validateForm = (): boolean => {
    const newErrors = {
      tokenName: "",
      quantity: "",
      recipientAddress: "",
      substandard: "",
    };

    if (!tokenName.trim()) {
      newErrors.tokenName = "Token name is required";
    } else if (tokenName.length > 32) {
      newErrors.tokenName = "Token name must be 32 characters or less";
    }

    if (!quantity.trim()) {
      newErrors.quantity = "Quantity is required";
    } else if (!/^\d+$/.test(quantity)) {
      newErrors.quantity = "Quantity must be a positive number";
    } else if (BigInt(quantity) <= 0) {
      newErrors.quantity = "Quantity must be greater than 0";
    }

    if (recipientAddress.trim() && !recipientAddress.startsWith("addr")) {
      newErrors.recipientAddress = "Invalid Cardano address format";
    }

    if (!substandardId || !issueContract || !transferContract) {
      newErrors.substandard =
        "Please select substandard, issue contract, and transfer contract";
    }

    setErrors(newErrors);
    return !Object.values(newErrors).some((error) => error !== "");
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!connected) {
      showToast({
        title: "Wallet Not Connected",
        description: "Please connect your wallet to register a token",
        variant: "error",
      });
      return;
    }

    if (!validateForm()) {
      showToast({
        title: "Validation Error",
        description: "Please select all required validators",
        variant: "error",
      });
      return;
    }

    try {
      setIsBuilding(true);

      // Get registrar address from wallet
      const addresses = await wallet.getUsedAddresses();
      if (!addresses || addresses.length === 0) {
        throw new Error("No addresses found in wallet");
      }
      const registrarAddress = addresses[0];

      let unsignedCborTx: string;
      let policyId: string;

      if (transactionBuilder === "frontend") {
        // Client-side transaction building
        showToast({
          title: "Building Transaction",
          description: "Building transaction on client side...",
          variant: "default",
        });

        // Fetch protocol data
        const protocolTxHash = selectedVersion?.txHash;
        const [protocolBlueprint, protocolBootstrap, substandardBlueprint] =
          await Promise.all([
            getProtocolBlueprint(),
            getProtocolBootstrap(protocolTxHash),
            getSubstandardBlueprint(substandardId),
          ]);

        // Get substandard handler
        const handler = getSubstandardHandler(
          substandardId as "dummy" | "bafin"
        );

        // Prepare register parameters
        const registerParams: RegisterTransactionParams = {
          assetName: tokenName,
          quantity,
          registrarAddress,
          recipientAddress: recipientAddress.trim() || undefined,
          substandardName: substandardId,
          substandardIssueContractName: issueContract,
          substandardTransferContractName: transferContract,
          substandardThirdPartyContractName: thirdPartyContract || undefined,
          networkId: 0, // Preview/testnet
        };

        // Build transaction client-side
        const { unsignedTx, policy_Id } =
          await handler.buildRegisterTransaction(
            registerParams,
            protocolBootstrap,
            protocolBlueprint,
            substandardBlueprint,
            wallet as IWallet
          );
        unsignedCborTx = unsignedTx;
        policyId = policy_Id;
      } else {
        // Server-side transaction building (existing logic)
        const request: RegisterTokenRequest = {
          registrarAddress,
          substandardName: substandardId,
          substandardIssueContractName: issueContract,
          substandardTransferContractName: transferContract,
          substandardThirdPartyContractName: thirdPartyContract || "",
          assetName: stringToHex(tokenName),
          quantity,
          recipientAddress: recipientAddress.trim() || "",
        };

        // Call backend to build registration transaction
        const response = await registerToken(request, selectedVersion?.txHash);
        unsignedCborTx = response.unsignedCborTx;
        policyId = response.policyId;
      }

      showToast({
        title: "Transaction Built",
        description: `Transaction built successfully using ${transactionBuilder} builder`,
        variant: "success",
      });

      // Pass transaction to parent for preview and signing
      onTransactionBuilt(
        unsignedCborTx,
        policyId,
        substandardId,
        issueContract,
        tokenName,
        quantity,
        recipientAddress.trim() || undefined
      );
    } catch (error) {
      // Extract error message from backend response
      let errorMessage = "Failed to build registration transaction";
      let errorTitle = "Registration Failed";

      if (error instanceof Error) {
        errorMessage = error.message;

        // Check if this is a "policy already registered" error
        if (errorMessage.toLowerCase().includes("already registered")) {
          errorTitle = "Token Already Registered";
          // Extract policy ID if present in message
          const policyMatch = errorMessage.match(/policy\s+(\w+)\s+already/i);
          if (policyMatch) {
            const policyId = policyMatch[1];
            errorMessage = `Token policy ${policyId.substring(
              0,
              16
            )}... has already been registered. Each policy can only be registered once.`;
          } else {
            errorMessage =
              "This token policy has already been registered. Each policy can only be registered once.";
          }
        }
      }

      // Show toast notification
      showToast({
        title: errorTitle,
        description: errorMessage,
        variant: "error",
        duration: 6000, // Show for 6 seconds
      });

      // Log to console without showing Next.js error overlay
      console.log("Registration error:", { errorTitle, errorMessage });
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
        disabled={
          !connected || isBuilding || !issueContract || !transferContract
        }
      >
        {isBuilding ? "Building Transaction..." : "Register Token"}
      </Button>

      {!connected && (
        <p className="text-sm text-center text-dark-400">
          Connect your wallet to continue
        </p>
      )}
    </form>
  );
}
