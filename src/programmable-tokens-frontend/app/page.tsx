"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { PageContainer } from "@/components/layout";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Shield, BarChart3, FileCheck, Settings } from "lucide-react";

const WalletInfoDynamic = dynamic(
  () => import("@/components/wallet").then((mod) => ({ default: mod.WalletInfo })),
  {
    ssr: false,
    loading: () => (
      <div className="max-w-md mx-auto">
        <Card>
          <CardContent className="flex items-center justify-center py-8">
            <div className="h-8 w-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          </CardContent>
        </Card>
      </div>
    )
  }
);

export default function Home() {

  const features = [
    {
      icon: <FileCheck className="h-8 w-8 text-primary-500" />,
      title: "Register Token",
      description: "Register a new programmable token policy with validation logic on-chain",
      href: "/register",
      available: true,
    },
    {
      icon: <Settings className="h-8 w-8 text-accent-500" />,
      title: "Admin Panel",
      description: "Mint tokens, manage blacklists, and seize tokens for compliance",
      href: "/admin",
      available: true,
    },
    {
      icon: <BarChart3 className="h-8 w-8 text-purple-500" />,
      title: "Dashboard",
      description: "View protocol state, token balances, and transaction history",
      href: "/dashboard",
      available: true,
    },
  ];

  return (
    <PageContainer maxWidth="xl">
      <div className="space-y-12">
        {/* Hero Section */}
        <div className="text-center space-y-4 py-12">
          <h1 className="text-5xl md:text-6xl font-bold bg-gradient-primary bg-clip-text text-transparent">
            CIP-113 Programmable Tokens
          </h1>
          <p className="text-xl text-dark-300 max-w-2xl mx-auto">
            Create and manage regulated tokens on Cardano with embedded validation logic
          </p>
        </div>

        {/* Wallet Connection Section */}
        <WalletInfoDynamic />

        {/* Features Grid */}
        <div>
          <h2 className="text-3xl font-bold text-white mb-6">Features</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {features.map((feature) => (
              <Card key={feature.title} hover className="relative">
                <CardHeader>
                  <div className="flex items-start justify-between">
                    <div className="p-3 rounded-lg bg-dark-900">
                      {feature.icon}
                    </div>
                    {!feature.available && (
                      <Badge variant="warning" size="sm">
                        Coming Soon
                      </Badge>
                    )}
                  </div>
                  <CardTitle className="mt-4">{feature.title}</CardTitle>
                  <CardDescription>{feature.description}</CardDescription>
                </CardHeader>
                <CardContent>
                  {feature.available ? (
                    <Link href={feature.href}>
                      <Button variant="ghost" className="w-full">
                        Get Started
                      </Button>
                    </Link>
                  ) : (
                    <Button variant="ghost" className="w-full" disabled>
                      Coming Soon
                    </Button>
                  )}
                </CardContent>
              </Card>
            ))}
          </div>
        </div>

        {/* Getting Started Section */}
        <Card>
          <CardHeader>
            <CardTitle>Getting Started</CardTitle>
            <CardDescription>
              Follow these steps to start using CIP-113 programmable tokens
            </CardDescription>
          </CardHeader>
          <CardContent>
            <ol className="space-y-4">
              <li className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary-500/10 text-primary-500 flex items-center justify-center font-bold">
                  1
                </div>
                <div>
                  <h3 className="font-semibold text-white">Connect Your Wallet</h3>
                  <p className="text-sm text-dark-300 mt-1">
                    Connect a Cardano wallet (Nami, Eternl, Lace, or Flint) to get started
                  </p>
                </div>
              </li>
              <li className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary-500/10 text-primary-500 flex items-center justify-center font-bold">
                  2
                </div>
                <div>
                  <h3 className="font-semibold text-white">Register Your Token</h3>
                  <p className="text-sm text-dark-300 mt-1">
                    Register a new programmable token policy and mint your initial tokens
                  </p>
                </div>
              </li>
              <li className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary-500/10 text-primary-500 flex items-center justify-center font-bold">
                  3
                </div>
                <div>
                  <h3 className="font-semibold text-white">Transfer Tokens</h3>
                  <p className="text-sm text-dark-300 mt-1">
                    Click the send button next to any token in your wallet to transfer
                  </p>
                </div>
              </li>
              <li className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary-500/10 text-primary-500 flex items-center justify-center font-bold">
                  4
                </div>
                <div>
                  <h3 className="font-semibold text-white">Admin Panel</h3>
                  <p className="text-sm text-dark-300 mt-1">
                    Use the Admin Panel to mint more tokens, manage blacklists, and seize tokens
                  </p>
                </div>
              </li>
            </ol>
          </CardContent>
        </Card>
      </div>
    </PageContainer>
  );
}
