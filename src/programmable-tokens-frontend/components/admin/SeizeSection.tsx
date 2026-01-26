"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { AlertTriangle, CheckCircle, ExternalLink } from "lucide-react";
import { AdminTokenSelector } from "./AdminTokenSelector";
import { AdminTokenInfo } from "@/lib/api/admin";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { useToast } from "@/components/ui/use-toast";
import { getExplorerTxUrl } from "@/lib/utils";

interface SeizeSectionProps {
  tokens: AdminTokenInfo[];
  adminAddress: string;
}

type SeizeStep = "form" | "signing" | "success";

export function SeizeSection({ tokens, adminAddress }: SeizeSectionProps) {
  const { wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();
  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";

  // Filter tokens where user has ISSUER_ADMIN role (seize requires issuer admin)
  const seizableTokens = tokens.filter((t) => t.roles.includes("ISSUER_ADMIN"));

  const [selectedToken, setSelectedToken] = useState<AdminTokenInfo | null>(null);
  const [targetUtxo, setTargetUtxo] = useState("");
  const [recipientAddress, setRecipientAddress] = useState(adminAddress);
  const [step, setStep] = useState<SeizeStep>("form");
  const [isBuilding, setIsBuilding] = useState(false);
  const [isSigning, setIsSigning] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);

  const [errors, setErrors] = useState({
    token: "",
    targetUtxo: "",
    recipientAddress: "",
  });

  const validateForm = (): boolean => {
    const newErrors = {
      token: "",
      targetUtxo: "",
      recipientAddress: "",
    };

    if (!selectedToken) {
      newErrors.token = "Please select a token";
    }

    if (!targetUtxo.trim()) {
      newErrors.targetUtxo = "Target UTxO is required";
    } else if (!targetUtxo.includes("#")) {
      newErrors.targetUtxo = "Invalid UTxO format. Use: txHash#index";
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

      // Parse UTxO
      const [txHashPart, indexPart] = targetUtxo.split("#");
      const outputIndex = parseInt(indexPart, 10);

      if (isNaN(outputIndex)) {
        throw new Error("Invalid UTxO index");
      }

      // Import compliance API dynamically
      const { seizeTokens } = await import("@/lib/api/compliance");

      const request = {
        feePayerAddress: adminAddress,
        unit: `${selectedToken.policyId}.${selectedToken.assetName}`,
        utxoTxHash: txHashPart,
        utxoOutputIndex: outputIndex,
        destinationAddress: recipientAddress.trim(),
      };

      const response = await seizeTokens(request, selectedVersion?.txHash);
      const unsignedCborTx = response.unsignedCborTx;

      setIsBuilding(false);
      setStep("signing");
      setIsSigning(true);

      // Sign and submit
      const signedTx = await wallet.signTx(unsignedCborTx);
      const submittedTxHash = await wallet.submitTx(signedTx);

      setTxHash(submittedTxHash);
      setStep("success");

      showToast({
        title: "Tokens Seized",
        description: `Successfully seized tokens from the target UTxO`,
        variant: "success",
      });
    } catch (error) {
      console.error("Seize error:", error);

      let errorMessage = "Failed to seize tokens";
      if (error instanceof Error) {
        if (error.message.includes("User declined")) {
          errorMessage = "Transaction was cancelled";
        } else {
          errorMessage = error.message;
        }
      }

      showToast({
        title: "Seize Failed",
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
    setTargetUtxo("");
    setRecipientAddress(adminAddress);
    setTxHash(null);
    setErrors({ token: "", targetUtxo: "", recipientAddress: "" });
  };

  if (seizableTokens.length === 0) {
    return (
      <div className="flex flex-col items-center py-12 px-6">
        <AlertTriangle className="h-16 w-16 text-dark-600 mb-4" />
        <h3 className="text-lg font-semibold text-white mb-2">No Seize Access</h3>
        <p className="text-sm text-dark-400 text-center">
          You don&apos;t have issuer admin permissions required to seize tokens.
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
        <h3 className="text-lg font-semibold text-white mb-2">Tokens Seized</h3>
        <p className="text-sm text-dark-400 text-center mb-4">
          Tokens have been successfully seized and transferred
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
            Seize More
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
      {/* Warning Banner */}
      <div className="px-4 py-3 bg-yellow-500/10 border border-yellow-500/30 rounded-lg">
        <div className="flex gap-3">
          <AlertTriangle className="h-5 w-5 text-yellow-500 flex-shrink-0" />
          <div>
            <p className="text-sm font-medium text-yellow-500">
              Regulatory Action
            </p>
            <p className="text-xs text-yellow-500/80 mt-1">
              Seizing tokens is an irreversible action. Only use this for legitimate
              regulatory compliance purposes.
            </p>
          </div>
        </div>
      </div>

      {/* Token Selector */}
      <div>
        <AdminTokenSelector
          tokens={seizableTokens}
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

      {/* Target UTxO */}
      <Input
        label="Target UTxO"
        value={targetUtxo}
        onChange={(e) => {
          setTargetUtxo(e.target.value);
          setErrors((prev) => ({ ...prev, targetUtxo: "" }));
        }}
        placeholder="txHash#outputIndex"
        disabled={isBuilding || !selectedToken}
        error={errors.targetUtxo}
        helperText="The UTxO containing tokens to seize (format: txHash#index)"
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
        helperText="Address to receive the seized tokens"
      />

      {/* Submit Button */}
      <Button
        type="submit"
        variant="danger"
        className="w-full"
        isLoading={isBuilding}
        disabled={isBuilding || !selectedToken}
      >
        {isBuilding ? "Building Transaction..." : "Seize Tokens"}
      </Button>
    </form>
  );
}
