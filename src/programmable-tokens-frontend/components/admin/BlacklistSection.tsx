"use client";

import { useState } from "react";
import { useWallet } from "@meshsdk/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Shield, Plus, Minus, CheckCircle, ExternalLink } from "lucide-react";
import { AdminTokenSelector } from "./AdminTokenSelector";
import { AdminTokenInfo } from "@/lib/api/admin";
import { useProtocolVersion } from "@/contexts/protocol-version-context";
import { useToast } from "@/components/ui/use-toast";
import { getExplorerTxUrl } from "@/lib/utils";
import { cn } from "@/lib/utils";

interface BlacklistSectionProps {
  tokens: AdminTokenInfo[];
  adminAddress: string;
}

type BlacklistAction = "add" | "remove";
type BlacklistStep = "form" | "signing" | "success";

export function BlacklistSection({ tokens, adminAddress }: BlacklistSectionProps) {
  const { wallet } = useWallet();
  const { toast: showToast } = useToast();
  const { selectedVersion } = useProtocolVersion();
  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";

  // Filter tokens where user has BLACKLIST_MANAGER role
  const manageableTokens = tokens.filter((t) =>
    t.roles.includes("BLACKLIST_MANAGER")
  );

  const [selectedToken, setSelectedToken] = useState<AdminTokenInfo | null>(null);
  const [action, setAction] = useState<BlacklistAction>("add");
  const [targetAddress, setTargetAddress] = useState("addr_test1qrhxewfhmagpjam32gn3g9flg620vdzzx6kg485cr48zs96xnd0c4sp430mfhegqvh5psjh5garzwgqank2ff8cxv0tq8luwgh");
  const [step, setStep] = useState<BlacklistStep>("form");
  const [isBuilding, setIsBuilding] = useState(false);
  const [isSigning, setIsSigning] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);

  const [errors, setErrors] = useState({
    token: "",
    targetAddress: "",
  });

  const validateForm = (): boolean => {
    const newErrors = {
      token: "",
      targetAddress: "",
    };

    if (!selectedToken) {
      newErrors.token = "Please select a token";
    }

    if (!targetAddress.trim()) {
      newErrors.targetAddress = "Address is required";
    } else if (!targetAddress.startsWith("addr")) {
      newErrors.targetAddress = "Invalid Cardano address format";
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

      // Import compliance API dynamically to avoid issues during Phase 2
      const { addToBlacklist, removeFromBlacklist } = await import(
        "@/lib/api/compliance"
      );

      const request = {
        tokenPolicyId: selectedToken.policyId,
        targetAddress: targetAddress.trim(),
        feePayerAddress: adminAddress,
      };

      let unsignedCborTx: string;
      if (action === "add") {
        const response = await addToBlacklist(request, selectedVersion?.txHash);
        console.log(response,"response")
        unsignedCborTx = response.unsignedCborTx;
      } else {
        const response = await removeFromBlacklist(request, selectedVersion?.txHash);
        console.log(response,"response")

        unsignedCborTx = response.unsignedCborTx;
      }

      setIsBuilding(false);
      setStep("signing");
      setIsSigning(true);

      // Sign and submit
      // Use partial signing (true) because the transaction may include UTXOs or certificates
      // that don't belong to the connected wallet (e.g., blacklist script UTXOs)
      const signedTx = await wallet.signTx(unsignedCborTx, true);
      const submittedTxHash = await wallet.submitTx(signedTx);

      setTxHash(submittedTxHash);
      setStep("success");

      showToast({
        title: `${action === "add" ? "Added to" : "Removed from"} Blacklist`,
        description: `Successfully ${action === "add" ? "blacklisted" : "un-blacklisted"} the address`,
        variant: "success",
      });
    } catch (error) {
      console.error("Blacklist error:", error);

      let errorMessage = `Failed to ${action} address to blacklist`;
      if (error instanceof Error) {
        if (error.message.includes("User declined")) {
          errorMessage = "Transaction was cancelled";
        } else {
          errorMessage = error.message;
        }
      }

      showToast({
        title: "Blacklist Operation Failed",
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
    setTargetAddress("");
    setTxHash(null);
    setErrors({ token: "", targetAddress: "" });
  };

  if (manageableTokens.length === 0) {
    return (
      <div className="flex flex-col items-center py-12 px-6">
        <Shield className="h-16 w-16 text-dark-600 mb-4" />
        <h3 className="text-lg font-semibold text-white mb-2">
          No Blacklist Management Access
        </h3>
        <p className="text-sm text-dark-400 text-center">
          You don&apos;t have blacklist manager permissions for any tokens.
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
          {action === "add" ? "Address Blacklisted" : "Address Removed"}
        </h3>
        <p className="text-sm text-dark-400 text-center mb-4">
          Successfully {action === "add" ? "added to" : "removed from"} the blacklist
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
          filterByRole="BLACKLIST_MANAGER"
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
                ? "bg-red-500/10 border-red-500 text-red-400"
                : "bg-dark-800 border-dark-700 text-dark-400 hover:border-dark-600"
            )}
          >
            <Plus className="h-4 w-4" />
            Add to Blacklist
          </button>
          <button
            type="button"
            onClick={() => setAction("remove")}
            disabled={isBuilding}
            className={cn(
              "flex-1 flex items-center justify-center gap-2 px-4 py-3 rounded-lg border transition-colors",
              action === "remove"
                ? "bg-green-500/10 border-green-500 text-green-400"
                : "bg-dark-800 border-dark-700 text-dark-400 hover:border-dark-600"
            )}
          >
            <Minus className="h-4 w-4" />
            Remove from Blacklist
          </button>
        </div>
      </div>

      {/* Target Address */}
      <Input
        label="Target Address"
        value={targetAddress}
        onChange={(e) => {
          setTargetAddress(e.target.value);
          setErrors((prev) => ({ ...prev, targetAddress: "" }));
        }}
        placeholder="addr1..."
        disabled={isBuilding || !selectedToken}
        error={errors.targetAddress}
        helperText={
          action === "add"
            ? "Address to add to the blacklist (will be frozen)"
            : "Address to remove from the blacklist (will be unfrozen)"
        }
      />

      {/* Submit Button */}
      <Button
        type="submit"
        variant={action === "add" ? "danger" : "primary"}
        className="w-full"
        isLoading={isBuilding}
        disabled={isBuilding || !selectedToken}
      >
        {isBuilding
          ? "Building Transaction..."
          : action === "add"
          ? "Add to Blacklist"
          : "Remove from Blacklist"}
      </Button>
    </form>
  );
}
