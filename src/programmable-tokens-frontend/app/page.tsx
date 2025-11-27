"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { PageContainer } from "@/components/layout";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Coins, Send, Shield, BarChart3, Rocket } from "lucide-react";

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
      icon: <Rocket className="h-8 w-8 text-primary-500" />,
      title: "Deploy Protocol",
      description: "Initialize the CIP-113 protocol with custom validation logic and substandards",
      href: "/deploy",
      available: true,
    },
    {
      icon: <Coins className="h-8 w-8 text-accent-500" />,
      title: "Mint Tokens",
      description: "Create programmable tokens with embedded validation rules and metadata",
      href: "/mint",
      available: true,
    },
    {
      icon: <Send className="h-8 w-8 text-highlight-500" />,
      title: "Transfer Tokens",
      description: "Transfer tokens with automatic validation against protocol rules",
      href: "/transfer",
      available: true,
    },
    {
      icon: <Shield className="h-8 w-8 text-blue-500" />,
      title: "Manage Blacklist",
      description: "Configure and manage blacklisted addresses for regulated tokens",
      href: "/blacklist",
      available: false,
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
                  <h3 className="font-semibold text-white">Deploy the Protocol</h3>
                  <p className="text-sm text-dark-300 mt-1">
                    Initialize the CIP-113 protocol with your chosen validation logic
                  </p>
                </div>
              </li>
              <li className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary-500/10 text-primary-500 flex items-center justify-center font-bold">
                  3
                </div>
                <div>
                  <h3 className="font-semibold text-white">Mint and Transfer</h3>
                  <p className="text-sm text-dark-300 mt-1">
                    Create programmable tokens and transfer them with automatic validation
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
