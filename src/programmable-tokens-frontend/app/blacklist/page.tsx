"use client";

import { PageContainer } from '@/components/layout/page-container';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { BlacklistInfoCard } from '@/components/blacklist';
import { Shield, AlertTriangle, Lock, FileCheck, ExternalLink, ArrowRight, Ban, UserX } from 'lucide-react';
import Link from 'next/link';

export default function BlacklistPage() {
  return (
    <PageContainer>
      <div className="max-w-4xl mx-auto">
        <div className="mb-8">
          <div className="flex items-center gap-3 mb-2">
            <h1 className="text-3xl font-bold text-white">Blacklist Management</h1>
            <Badge variant="warning">Coming Soon</Badge>
          </div>
          <p className="text-dark-300">
            Manage address restrictions for CIP-0113 programmable tokens
          </p>
        </div>

        <Card className="mb-6 border-yellow-500/20 bg-yellow-500/5">
          <CardContent className="py-6">
            <div className="flex items-start gap-4">
              <div className="p-3 rounded-lg bg-yellow-500/10">
                <AlertTriangle className="w-6 h-6 text-yellow-500" />
              </div>
              <div>
                <h3 className="font-medium text-white mb-1">Feature In Development</h3>
                <p className="text-sm text-dark-300">
                  The blacklist management interface is currently under development.
                  The on-chain blacklist validator is ready, but the management UI requires
                  additional backend endpoints for listing, adding, and removing addresses.
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="grid gap-6 md:grid-cols-2 mb-6">
          <BlacklistInfoCard
            title="What is Blacklisting?"
            description="Address-based transfer restrictions"
            icon="shield"
            features={[
              "Block specific addresses from receiving tokens",
              "Compliance with regulatory requirements",
              "Prevents transfers to sanctioned addresses",
              "Uses on-chain sorted linked list for efficient lookups",
            ]}
          />
          <BlacklistInfoCard
            title="How It Works"
            description="On-chain validation mechanism"
            icon="lock"
            features={[
              "Manager-authorized address additions",
              "Validator checks blacklist before transfers",
              "Transactions to blacklisted addresses fail",
              "Linked list structure ensures O(log n) lookups",
            ]}
          />
        </div>

        <Card className="mb-6">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <FileCheck className="w-5 h-5" />
              Blacklist Validator
            </CardTitle>
            <CardDescription>
              On-chain smart contract for blacklist management
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              <div className="p-4 rounded-lg bg-dark-800/50">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm text-dark-400">Validator Name</span>
                  <Badge variant="info">blacklist_mint</Badge>
                </div>
                <p className="text-sm text-dark-300">
                  The blacklist_mint validator manages a linked list of blacklisted addresses.
                  Only the authorized manager can insert or remove entries from the blacklist.
                </p>
              </div>

              <div className="p-4 rounded-lg bg-dark-800/50">
                <h4 className="text-sm font-medium text-white mb-2">Supported Operations</h4>
                <div className="grid grid-cols-3 gap-3">
                  <div className="p-3 rounded bg-dark-700/50 text-center">
                    <Shield className="w-5 h-5 mx-auto mb-1 text-green-400" />
                    <span className="text-xs text-dark-300">Initialize</span>
                  </div>
                  <div className="p-3 rounded bg-dark-700/50 text-center">
                    <Ban className="w-5 h-5 mx-auto mb-1 text-red-400" />
                    <span className="text-xs text-dark-300">Add Address</span>
                  </div>
                  <div className="p-3 rounded bg-dark-700/50 text-center">
                    <UserX className="w-5 h-5 mx-auto mb-1 text-yellow-400" />
                    <span className="text-xs text-dark-300">Remove</span>
                  </div>
                </div>
              </div>

              <div className="p-4 rounded-lg bg-dark-800/50">
                <h4 className="text-sm font-medium text-white mb-2">Security Requirements</h4>
                <ul className="space-y-1 text-sm text-dark-300">
                  <li className="flex items-center gap-2">
                    <Lock className="w-4 h-4 text-primary-400" />
                    Manager signature required for all operations
                  </li>
                  <li className="flex items-center gap-2">
                    <Lock className="w-4 h-4 text-primary-400" />
                    One-shot minting policy ensures unique blacklist
                  </li>
                  <li className="flex items-center gap-2">
                    <Lock className="w-4 h-4 text-primary-400" />
                    28-byte public key hash validation
                  </li>
                </ul>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Quick Links</CardTitle>
            <CardDescription>Learn more about blacklist functionality</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <Link
              href="/mint"
              className="flex items-center justify-between p-4 rounded-lg bg-dark-800/50 hover:bg-dark-700/50 transition-colors group"
            >
              <div>
                <h3 className="font-medium text-white group-hover:text-primary-400 transition-colors">
                  Mint with Blacklist
                </h3>
                <p className="text-sm text-dark-400">
                  Create tokens with blacklist restrictions enabled
                </p>
              </div>
              <ArrowRight className="w-4 h-4 text-dark-400 group-hover:text-primary-400" />
            </Link>
            <a
              href="https://github.com/cardano-foundation/cip113-programmable-tokens/blob/main/src/programmable-tokens-onchain-aiken/validators/blacklist_mint.ak"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center justify-between p-4 rounded-lg bg-dark-800/50 hover:bg-dark-700/50 transition-colors group"
            >
              <div>
                <h3 className="font-medium text-white group-hover:text-primary-400 transition-colors">
                  View Source Code
                </h3>
                <p className="text-sm text-dark-400">
                  Explore the blacklist validator implementation
                </p>
              </div>
              <ExternalLink className="w-4 h-4 text-dark-400" />
            </a>
          </CardContent>
        </Card>
      </div>
    </PageContainer>
  );
}
