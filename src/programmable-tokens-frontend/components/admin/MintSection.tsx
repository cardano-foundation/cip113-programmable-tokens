"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Coins, CheckCircle, ExternalLink } from "lucide-react";
import { AdminTokenSelector } from "./AdminTokenSelector";
import { AdminTokenInfo } from "@/lib/api/admin";
import { mintToken, stringToHex } from "@/lib/api";
import { MintTokenRequest } from "@/types/api";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { useToast } from "@/components/ui/use-toast";
import { getExplorerTxUrl } from "@/lib/utils";

interface MintSectionProps {
  tokens: AdminTokenInfo[];
  feePayerAddress: string;
}

type MintStep = "form" | "signing" | "success";

export function MintSection({ tokens, feePayerAddress }: MintSectionProps) {
  const { wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();
  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";

  // Filter tokens where user has ISSUER_ADMIN role
  const mintableTokens = tokens.filter((t) => t.roles.includes("ISSUER_ADMIN"));

  const [selectedToken, setSelectedToken] = useState<AdminTokenInfo | null>(null);
  const [quantity, setQuantity] = useState("");
  const [recipientAddress, setRecipientAddress] = useState("");
  const [step, setStep] = useState<MintStep>("form");
  const [isBuilding, setIsBuilding] = useState(false);
  const [isSigning, setIsSigning] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);

  const [errors, setErrors] = useState({
    token: "",
    quantity: "",
    recipientAddress: "",
  });

  const validateForm = (): boolean => {
    const newErrors = {
      token: "",
      quantity: "",
      recipientAddress: "",
    };

    if (!selectedToken) {
      newErrors.token = "Please select a token to mint";
    }

    if (!quantity.trim()) {
      newErrors.quantity = "Quantity is required";
    } else if (!/^\d+$/.test(quantity)) {
      newErrors.quantity = "Quantity must be a positive number";
    } else if (BigInt(quantity) <= 0) {
      newErrors.quantity = "Quantity must be greater than 0";
    }

    if (!recipientAddress.trim()) {
      newErrors.recipientAddress = "Recipient address is required";
    } else if (!recipientAddress.startsWith("addr")) {
      newErrors.recipientAddress = "Invalid Cardano address format";
    }

    setErrors(newErrors);
    return !Object.values(newErrors).some((error) => error !== "");
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validateForm() || !selectedToken) {
      return;
    }

    try {
      setIsBuilding(true);

      const request: MintTokenRequest = {
        feePayerAddress,
        tokenPolicyId: selectedToken.policyId,
        assetName: selectedToken.assetName,
        quantity,
        recipientAddress: recipientAddress.trim(),
      };

      const unsignedCborTx = await mintToken(request, selectedVersion?.txHash);

      setIsBuilding(false);
      setStep("signing");
      setIsSigning(true);

      // Sign and submit
      const signedTx = await wallet.signTx(unsignedCborTx);
      const submittedTxHash = await wallet.submitTx(signedTx);

      setTxHash(submittedTxHash);
      setStep("success");

      showToast({
        title: "Mint Successful",
        description: `Minted ${quantity} ${selectedToken.assetNameDisplay} tokens`,
        variant: "success",
      });
    } catch (error) {
      console.error("Mint error:", error);

      let errorMessage = "Failed to mint tokens";
      if (error instanceof Error) {
        if (error.message.includes("User declined")) {
          errorMessage = "Transaction was cancelled";
        } else {
          errorMessage = error.message;
        }
      }

      showToast({
        title: "Mint Failed",
        description: errorMessage,
        variant: "error",
      });

      setStep("form");
    } finally {
      setIsBuilding(false);
      setIsSigning(false);
    }
  };

  const handleReset = () => {
    setStep("form");
    setQuantity("");
    setRecipientAddress("");
    setTxHash(null);
    setErrors({ token: "", quantity: "", recipientAddress: "" });
  };

  if (mintableTokens.length === 0) {
    return (
      <div className="flex flex-col items-center py-12 px-6">
        <Coins className="h-16 w-16 text-dark-600 mb-4" />
        <h3 className="text-lg font-semibold text-white mb-2">No Minting Access</h3>
        <p className="text-sm text-dark-400 text-center">
          You don&apos;t have issuer admin permissions for any tokens.
        </p>
      </div>
    );
  }

  if (step === "success" && txHash) {
    return (
      <div className="flex flex-col items-center py-8">
        <div className="w-16 h-16 rounded-full bg-green-500/10 flex items-center justify-center mb-4">
          <CheckCircle className="h-8 w-8 text-green-500" />
        </div>
        <h3 className="text-lg font-semibold text-white mb-2">Mint Complete!</h3>
        <p className="text-sm text-dark-400 text-center mb-4">
          Successfully minted {quantity} {selectedToken?.assetNameDisplay} tokens
        </p>

        <div className="w-full px-4 py-3 bg-dark-900 rounded-lg mb-4">
          <p className="text-xs text-dark-400 mb-1">Transaction Hash</p>
          <p className="text-xs text-primary-400 font-mono break-all">{txHash}</p>
        </div>

        <div className="flex gap-3 w-full">
          <a
            href={getExplorerTxUrl(network, txHash)}
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1"
          >
            <Button variant="ghost" className="w-full">
              <ExternalLink className="h-4 w-4 mr-2" />
              View on Explorer
            </Button>
          </a>
          <Button variant="primary" className="flex-1" onClick={handleReset}>
            Mint More
          </Button>
        </div>
      </div>
    );
  }

  if (step === "signing") {
    return (
      <div className="flex flex-col items-center py-12">
        <div className="h-12 w-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin mb-4" />
        <p className="text-white font-medium">
          {isSigning ? "Waiting for signature..." : "Building transaction..."}
        </p>
        <p className="text-sm text-dark-400 mt-2">
          Please confirm the transaction in your wallet
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Token Selector */}
      <div>
        <AdminTokenSelector
          tokens={mintableTokens}
          selectedToken={selectedToken}
          onSelect={(token) => {
            setSelectedToken(token);
            setErrors((prev) => ({ ...prev, token: "" }));
          }}
          disabled={isBuilding}
          filterByRole="ISSUER_ADMIN"
        />
        {errors.token && (
          <p className="mt-2 text-sm text-red-400">{errors.token}</p>
        )}
      </div>

      {/* Quantity */}
      <Input
        label="Quantity"
        type="number"
        value={quantity}
        onChange={(e) => {
          setQuantity(e.target.value);
          setErrors((prev) => ({ ...prev, quantity: "" }));
        }}
        placeholder="Enter amount to mint"
        disabled={isBuilding || !selectedToken}
        error={errors.quantity}
        helperText="Number of tokens to mint"
      />

      {/* Recipient Address */}
      <Input
        label="Recipient Address"
        value={recipientAddress}
        onChange={(e) => {
          setRecipientAddress(e.target.value);
          setErrors((prev) => ({ ...prev, recipientAddress: "" }));
        }}
        placeholder="addr1..."
        disabled={isBuilding || !selectedToken}
        error={errors.recipientAddress}
        helperText="Address to receive the minted tokens"
      />

      {/* Submit Button */}
      <Button
        type="submit"
        variant="primary"
        className="w-full"
        isLoading={isBuilding}
        disabled={isBuilding || !selectedToken}
      >
        {isBuilding ? "Building Transaction..." : "Mint Tokens"}
      </Button>
    </form>
  );
}
