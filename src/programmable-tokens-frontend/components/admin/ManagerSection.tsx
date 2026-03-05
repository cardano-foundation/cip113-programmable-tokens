"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Users, Plus, Minus, CheckCircle, ExternalLink } from "lucide-react";
import { AdminTokenSelector } from "./AdminTokenSelector";
import { AdminTokenInfo } from "@/lib/api/admin";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { useToast } from "@/components/ui/use-toast";
import { getExplorerTxUrl } from "@/lib/utils";
import { cn } from "@/lib/utils";

interface ManagerSectionProps {
  tokens: AdminTokenInfo[];
  adminAddress: string;
}

type ManagerAction = "add" | "remove";
type ManagerStep = "form" | "signing" | "success";

export function ManagerSection({ tokens, adminAddress }: ManagerSectionProps) {
  const { wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();

  // Filter tokens where user has ISSUER_ADMIN role for whitelist substandard
  const manageableTokens = tokens.filter(
    (t) =>
      t.roles.includes("ISSUER_ADMIN") &&
      t.substandardId === "whitelist-send-receive-multiadmin"
  );

  const [selectedToken, setSelectedToken] = useState<AdminTokenInfo | null>(null);
  const [action, setAction] = useState<ManagerAction>("add");
  const [targetCredential, setTargetCredential] = useState("");
  const [step, setStep] = useState<ManagerStep>("form");
  const [isBuilding, setIsBuilding] = useState(false);
  const [isSigning, setIsSigning] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);

  const [errors, setErrors] = useState({
    token: "",
    targetCredential: "",
  });

  const validateForm = (): boolean => {
    const newErrors = {
      token: "",
      targetCredential: "",
    };

    if (!selectedToken) {
      newErrors.token = "Please select a token";
    }

    if (!targetCredential.trim()) {
      newErrors.targetCredential = "Manager credential is required";
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

      const { addAdmin, removeAdmin } = await import("@/lib/api/compliance");

      // Extract credential from address if needed
      let credential = targetCredential.trim();
      if (credential.startsWith("addr")) {
        const { deserializeAddress } = await import("@meshsdk/core");
        const deserialized = deserializeAddress(credential);
        credential = deserialized.pubKeyHash || credential;
      }

      const request = {
        adminAddress,
        targetCredential: credential,
        policyId: selectedToken.policyId,
        role: "WHITELIST_MANAGER",
      };

      let unsignedCborTx: string;
      if (action === "add") {
        const response = await addAdmin(request, selectedVersion?.txHash);
        unsignedCborTx = response.unsignedCborTx;
      } else {
        const response = await removeAdmin(request, selectedVersion?.txHash);
        unsignedCborTx = response.unsignedCborTx;
      }

      setIsBuilding(false);
      setStep("signing");
      setIsSigning(true);

      const signedTx = await wallet.signTx(unsignedCborTx);
      const submittedTxHash = await wallet.submitTx(signedTx);

      setTxHash(submittedTxHash);
      setStep("success");

      showToast({
        title: `Manager ${action === "add" ? "Added" : "Removed"}`,
        description: `Successfully ${action === "add" ? "added" : "removed"} the manager`,
        variant: "success",
      });
    } catch (error) {
      console.error("Manager operation error:", error);

      let errorMessage = `Failed to ${action} manager`;
      if (error instanceof Error) {
        if (error.message.includes("User declined")) {
          errorMessage = "Transaction was cancelled";
        } else {
          errorMessage = error.message;
        }
      }

      showToast({
        title: "Manager Operation Failed",
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
    setTargetCredential("");
    setTxHash(null);
    setErrors({ token: "", targetCredential: "" });
  };

  if (manageableTokens.length === 0) {
    return (
      <div className="flex flex-col items-center py-12 px-6">
        <Users className="h-16 w-16 text-dark-600 mb-4" />
        <h3 className="text-lg font-semibold text-white mb-2">
          No Manager Administration Access
        </h3>
        <p className="text-sm text-dark-400 text-center">
          You don&apos;t have super-admin (ISSUER_ADMIN) permissions for any whitelist tokens.
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
        <h3 className="text-lg font-semibold text-white mb-2">
          {action === "add" ? "Manager Added" : "Manager Removed"}
        </h3>
        <p className="text-sm text-dark-400 text-center mb-4">
          Successfully {action === "add" ? "added" : "removed"} the manager credential
        </p>

        <div className="w-full px-4 py-3 bg-dark-900 rounded-lg mb-4">
          <p className="text-xs text-dark-400 mb-1">Transaction Hash</p>
          <p className="text-xs text-primary-400 font-mono break-all">{txHash}</p>
        </div>

        <div className="flex gap-3 w-full">
          <a
            href={getExplorerTxUrl(txHash)}
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
            Manage More
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
          tokens={manageableTokens}
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

      {/* Action Toggle */}
      <div>
        <label className="block text-sm font-medium text-white mb-2">Action</label>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => setAction("add")}
            disabled={isBuilding}
            className={cn(
              "flex-1 flex items-center justify-center gap-2 px-4 py-3 rounded-lg border transition-colors",
              action === "add"
                ? "bg-green-500/10 border-green-500 text-green-400"
                : "bg-dark-800 border-dark-700 text-dark-400 hover:border-dark-600"
            )}
          >
            <Plus className="h-4 w-4" />
            Add Manager
          </button>
          <button
            type="button"
            onClick={() => setAction("remove")}
            disabled={isBuilding}
            className={cn(
              "flex-1 flex items-center justify-center gap-2 px-4 py-3 rounded-lg border transition-colors",
              action === "remove"
                ? "bg-red-500/10 border-red-500 text-red-400"
                : "bg-dark-800 border-dark-700 text-dark-400 hover:border-dark-600"
            )}
          >
            <Minus className="h-4 w-4" />
            Remove Manager
          </button>
        </div>
      </div>

      {/* Target Credential */}
      <Input
        label="Manager Address or Credential"
        value={targetCredential}
        onChange={(e) => {
          setTargetCredential(e.target.value);
          setErrors((prev) => ({ ...prev, targetCredential: "" }));
        }}
        placeholder="addr1... or credential hash"
        disabled={isBuilding || !selectedToken}
        error={errors.targetCredential}
        helperText={
          action === "add"
            ? "Address or payment key hash of the new whitelist manager"
            : "Address or payment key hash of the manager to remove"
        }
      />

      {/* Submit Button */}
      <Button
        type="submit"
        variant={action === "add" ? "primary" : "danger"}
        className="w-full"
        isLoading={isBuilding}
        disabled={isBuilding || !selectedToken}
      >
        {isBuilding
          ? "Building Transaction..."
          : action === "add"
          ? "Add Manager"
          : "Remove Manager"}
      </Button>
    </form>
  );
}
