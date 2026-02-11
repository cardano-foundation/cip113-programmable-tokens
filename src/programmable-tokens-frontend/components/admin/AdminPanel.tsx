"use client";

import { useState } from "react";
import { Coins, Shield, AlertTriangle, Flame } from "lucide-react";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { MintSection } from "./MintSection";
import { BurnSection } from "./BurnSection";
import { BlacklistSection } from "./BlacklistSection";
import { SeizeSection } from "./SeizeSection";
import { SpentUtxosSection } from "./SpentUtxosSection";
import { AdminTokenInfo } from "@/lib/api/admin";
import { cn } from "@/lib/utils";
import { AlertCircle } from "lucide-react";

interface AdminPanelProps {
  tokens: AdminTokenInfo[];
  adminAddress: string;
}

<<<<<<< HEAD
type AdminTab = "mint" | "blacklist" | "seize" | "spent-utxos";
=======
type AdminTab = "mint" | "burn" | "blacklist" | "seize";
>>>>>>> upstream/main

interface TabInfo {
  id: AdminTab;
  label: string;
  icon: React.ReactNode;
  description: string;
  requiredRole: "ISSUER_ADMIN" | "BLACKLIST_MANAGER";
}

const tabs: TabInfo[] = [
  {
    id: "mint",
    label: "Mint",
    icon: <Coins className="h-4 w-4" />,
    description: "Mint new tokens to recipients",
    requiredRole: "ISSUER_ADMIN",
  },
  {
    id: "burn",
    label: "Burn",
    icon: <Flame className="h-4 w-4" />,
    description: "Burn tokens from specific UTxOs",
    requiredRole: "ISSUER_ADMIN",
  },
  {
    id: "blacklist",
    label: "Blacklist",
    icon: <Shield className="h-4 w-4" />,
    description: "Manage frozen addresses",
    requiredRole: "BLACKLIST_MANAGER",
  },
  {
    id: "seize",
    label: "Seize",
    icon: <AlertTriangle className="h-4 w-4" />,
    description: "Seize tokens from blacklisted addresses",
    requiredRole: "ISSUER_ADMIN",
  },
  {
    id: "spent-utxos",
    label: "Spent UTXOs",
    icon: <AlertCircle className="h-4 w-4" />,
    description: "View already spent UTXOs to debug transaction errors",
    requiredRole: "ISSUER_ADMIN", // Show for any admin
  },
];

export function AdminPanel({ tokens, adminAddress }: AdminPanelProps) {
  const [activeTab, setActiveTab] = useState<AdminTab>("mint");

  // Determine which tabs are available based on user's roles
  const hasRole = (role: "ISSUER_ADMIN" | "BLACKLIST_MANAGER") => {
    return tokens.some((token) => token.roles.includes(role));
  };

  // Spent UTXOs tab is always available if user has any admin role
  const availableTabs = tabs.filter((tab) => 
    tab.id === "spent-utxos" 
      ? (hasRole("ISSUER_ADMIN") || hasRole("BLACKLIST_MANAGER"))
      : hasRole(tab.requiredRole)
  );

  // If no tabs are available, show empty state
  if (availableTabs.length === 0) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center py-16">
          <Shield className="h-16 w-16 text-dark-600 mb-4" />
          <h3 className="text-xl font-semibold text-white mb-2">
            No Admin Access
          </h3>
          <p className="text-dark-400 text-center max-w-md">
            You don&apos;t have administrator permissions for any programmable tokens.
            Contact the token issuer if you believe this is an error.
          </p>
        </CardContent>
      </Card>
    );
  }

  // Ensure activeTab is available
  if (!availableTabs.find((t) => t.id === activeTab)) {
    setActiveTab(availableTabs[0].id);
  }

  return (
    <Card>
      <CardHeader className="border-b border-dark-700">
        <div className="flex items-center justify-between">
          <CardTitle>Token Administration</CardTitle>
          <Badge variant="info" size="sm">
            {tokens.length} Token{tokens.length !== 1 ? "s" : ""}
          </Badge>
        </div>

        {/* Tabs */}
        <div className="flex gap-2 mt-4">
          {availableTabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={cn(
                "flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors",
                activeTab === tab.id
                  ? "bg-primary-500/10 text-primary-400 border border-primary-500/30"
                  : "bg-dark-800 text-dark-400 border border-dark-700 hover:border-dark-600 hover:text-dark-300"
              )}
            >
              {tab.icon}
              {tab.label}
            </button>
          ))}
        </div>
      </CardHeader>

      <CardContent className="pt-6">
        {/* Tab Description */}
        <p className="text-sm text-dark-400 mb-6">
          {tabs.find((t) => t.id === activeTab)?.description}
        </p>

        {/* Tab Content */}
        {activeTab === "mint" && (
          <MintSection tokens={tokens} feePayerAddress={adminAddress} />
        )}
        {activeTab === "burn" && (
          <BurnSection adminTokens={tokens} feePayerAddress={adminAddress} />
        )}
        {activeTab === "blacklist" && (
          <BlacklistSection tokens={tokens} adminAddress={adminAddress} />
        )}
        {activeTab === "seize" && (
          <SeizeSection tokens={tokens} adminAddress={adminAddress} />
        )}
        {activeTab === "spent-utxos" && (
          <SpentUtxosSection adminPkh={adminAddress} />
        )}
      </CardContent>
    </Card>
  );
}
