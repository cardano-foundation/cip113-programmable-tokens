"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { SubstandardSelector } from "./substandard-selector";
import {
  TransactionBuilderToggle,
  TransactionBuilder,
} from "./transaction-builder-toggle";
import { Substandard, LegacyMintFormData } from "@/types/api";
import {
  prepareLegacyMintRequest,
  legacyMintToken,
  stringToHex,
  getProtocolBlueprint,
  getProtocolBootstrap,
  getSubstandardBlueprint,
} from "@/lib/api";
import { useToast } from "@/components/ui/use-toast";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { getSubstandardHandler } from "@/lib/mesh-sdk/standard/factory";
import type { MintTransactionParams } from "@/lib/mesh-sdk/standard/factory";
import { IWallet } from "@meshsdk/core";

interface MintFormProps {
  substandards: Substandard[];
  onTransactionBuilt: (
    txHex: string,
    assetName: string,
    quantity: string
  ) => void;
  preSelectedSubstandard?: string;
  preSelectedIssueContract?: string;
}

export function MintForm({
  substandards,
  onTransactionBuilt,
  preSelectedSubstandard,
  preSelectedIssueContract,
}: MintFormProps) {
  const { connected, wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();

  const [tokenName, setTokenName] = useState("");
  const [quantity, setQuantity] = useState("");
  const [recipientAddress, setRecipientAddress] = useState("");
  const [substandardId, setSubstandardId] = useState("");
  const [validatorTitle, setValidatorTitle] = useState("");
  const [transactionBuilder, setTransactionBuilder] =
    useState<TransactionBuilder>("backend");
  const [isBuilding, setIsBuilding] = useState(false);

  const [errors, setErrors] = useState({
    tokenName: "",
    quantity: "",
    recipientAddress: "",
    substandard: "",
  });

  const handleSubstandardSelect = (
    selectedSubstandardId: string,
    selectedValidatorTitle: string
  ) => {
    setSubstandardId(selectedSubstandardId);
    setValidatorTitle(selectedValidatorTitle);
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

    if (!substandardId || !validatorTitle) {
      newErrors.substandard = "Please select a substandard and validator";
    }

    setErrors(newErrors);
    return !Object.values(newErrors).some((error) => error !== "");
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!connected) {
      showToast({
        title: "Wallet Not Connected",
        description: "Please connect your wallet to mint tokens",
        variant: "error",
      });
      return;
    }

    if (!validateForm()) {
      showToast({
        title: "Validation Error",
        description: "Please fix the errors in the form",
        variant: "error",
      });
      return;
    }

    try {
      setIsBuilding(true);

      // Get issuer address from wallet
      const addresses = await wallet.getUsedAddresses();
      if (!addresses || addresses.length === 0) {
        throw new Error("No addresses found in wallet");
      }
      const issuerAddress = addresses[0];

      let unsignedTxCborHex: string;

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

        // Prepare mint parameters
        const mintParams: MintTransactionParams = {
          assetName: tokenName,
          quantity,
          issuerBaseAddress: issuerAddress,
          recipientAddress: recipientAddress.trim() || undefined,
          substandardName: substandardId,
          substandardIssueContractName: validatorTitle,
        };

        // Build transaction client-side
        unsignedTxCborHex = await handler.buildMintTransaction(
          mintParams,
          protocolBootstrap,
          protocolBlueprint,
          substandardBlueprint,
          wallet as IWallet
        );
      } else {
        // Server-side transaction building (existing logic)
        const formData: LegacyMintFormData = {
          tokenName,
          quantity,
          substandardId,
          validatorTitle,
          recipientAddress: recipientAddress.trim() || undefined,
        };

        const request = prepareLegacyMintRequest(formData, issuerAddress);
        unsignedTxCborHex = await legacyMintToken(request);
      }

      showToast({
        title: "Transaction Built",
        description: `Transaction built successfully using ${transactionBuilder} builder`,
        variant: "success",
      });

      // Pass transaction to parent for preview and signing
      onTransactionBuilt(unsignedTxCborHex, tokenName, quantity);
    } catch (error) {
      console.error("Error building transaction:", error);
      showToast({
        title: "Transaction Build Failed",
        description:
          error instanceof Error
            ? error.message
            : "Failed to build transaction",
        variant: "error",
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
            setErrors((prev) => ({ ...prev, tokenName: "" }));
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
          setErrors((prev) => ({ ...prev, quantity: "" }));
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
          setErrors((prev) => ({ ...prev, recipientAddress: "" }));
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
          initialSubstandard={preSelectedSubstandard}
          initialValidator={preSelectedIssueContract}
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
        {isBuilding ? "Building Transaction..." : "Build Transaction"}
      </Button>

      {!connected && (
        <p className="text-sm text-center text-dark-400">
          Connect your wallet to continue
        </p>
      )}
    </form>
  );
}
