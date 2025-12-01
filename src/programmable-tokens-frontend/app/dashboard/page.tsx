"use client";

import { useState, useEffect } from 'react';
import dynamic from 'next/dynamic';
import Link from 'next/link';
import { PageContainer } from '@/components/layout/page-container';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  Wallet,
  Coins,
  Send,
  ArrowUpRight,
  RefreshCw,
  AlertCircle,
  CheckCircle,
  Clock,
  Database
} from 'lucide-react';
import { apiGet } from '@/lib/api/client';
import { useToast } from '@/components/ui/use-toast';

// Dynamically import wallet-dependent components
const WalletInfoDynamic = dynamic(
  () => import('@/components/wallet').then((mod) => ({ default: mod.WalletInfo })),
  { ssr: false }
);

interface RegistryNode {
  policyId: string;
  transferLogic: string;
  issuerLogic: string;
  txHash: string;
  slot: number;
}

interface ProtocolStats {
  protocolParamsId: number;
  registryNodePolicyId: string;
  progLogicScriptHash: string;
  tokenCount: number;
}

interface TokenBalance {
  unit: string;
  policyId: string;
  assetName: string;
  assetNameReadable: string;
  amount: string;
}

export default function DashboardPage() {
  const { toast } = useToast();
  const [registeredTokens, setRegisteredTokens] = useState<RegistryNode[]>([]);
  const [protocolStats, setProtocolStats] = useState<ProtocolStats[]>([]);
  const [isLoadingTokens, setIsLoadingTokens] = useState(true);
  const [isLoadingStats, setIsLoadingStats] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Hex to readable string
  const hexToString = (hex: string): string => {
    try {
      const bytes = new Uint8Array(hex.match(/.{1,2}/g)?.map(byte => parseInt(byte, 16)) || []);
      const decoded = new TextDecoder().decode(bytes);
      // Return hex if not printable ASCII
      return /^[\x20-\x7E]*$/.test(decoded) ? decoded : hex.slice(0, 16) + '...';
    } catch {
      return hex.slice(0, 16) + '...';
    }
  };

  // Fetch registered tokens
  const fetchRegisteredTokens = async () => {
    setIsLoadingTokens(true);
    try {
      const response = await apiGet<Array<{ protocolParams: unknown; nodes: RegistryNode[] }>>('/registry/tokens');
      const allTokens = response.flatMap(r => r.nodes || []);
      setRegisteredTokens(allTokens);
    } catch (err) {
      console.error('Failed to fetch tokens:', err);
      setError('Failed to load registered tokens');
    } finally {
      setIsLoadingTokens(false);
    }
  };

  // Fetch protocol stats
  const fetchProtocolStats = async () => {
    setIsLoadingStats(true);
    try {
      const response = await apiGet<ProtocolStats[]>('/registry/protocols');
      setProtocolStats(response);
    } catch (err) {
      console.error('Failed to fetch protocol stats:', err);
    } finally {
      setIsLoadingStats(false);
    }
  };

  // Fetch data on mount
  useEffect(() => {
    fetchRegisteredTokens();
    fetchProtocolStats();
  }, []);

  // Refresh all data
  const handleRefresh = () => {
    fetchRegisteredTokens();
    fetchProtocolStats();
    toast({
      title: 'Refreshing',
      description: 'Fetching latest data from the backend...',
    });
  };

  const totalTokens = protocolStats.reduce((acc, p) => acc + (p.tokenCount || 0), 0);

  return (
    <PageContainer maxWidth="xl">
      <div className="space-y-8">
        {/* Page Header */}
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
          <div>
            <h1 className="text-3xl font-bold text-white mb-2">Dashboard</h1>
            <p className="text-dark-300">
              View protocol status, registered tokens, and manage your assets
            </p>
          </div>
          <Button variant="ghost" onClick={handleRefresh} className="gap-2">
            <RefreshCw className="h-4 w-4" />
            Refresh
          </Button>
        </div>

        {/* Wallet Section */}
        <WalletInfoDynamic />

        {/* Stats Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm text-dark-400">Protocol Instances</p>
                  <p className="text-3xl font-bold text-white mt-1">
                    {isLoadingStats ? '...' : protocolStats.length}
                  </p>
                </div>
                <div className="p-3 bg-primary-500/10 rounded-lg">
                  <Database className="h-6 w-6 text-primary-500" />
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="pt-6">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm text-dark-400">Registered Tokens</p>
                  <p className="text-3xl font-bold text-white mt-1">
                    {isLoadingTokens ? '...' : registeredTokens.length}
                  </p>
                </div>
                <div className="p-3 bg-accent-500/10 rounded-lg">
                  <Coins className="h-6 w-6 text-accent-500" />
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="pt-6">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm text-dark-400">Network</p>
                  <p className="text-xl font-bold text-white mt-1">Preview</p>
                </div>
                <div className="p-3 bg-green-500/10 rounded-lg">
                  <CheckCircle className="h-6 w-6 text-green-500" />
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="pt-6">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm text-dark-400">Status</p>
                  <p className="text-xl font-bold text-white mt-1">Active</p>
                </div>
                <div className="p-3 bg-highlight-500/10 rounded-lg">
                  <Clock className="h-6 w-6 text-highlight-500" />
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Quick Actions */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <Link href="/mint">
            <Card hover className="h-full cursor-pointer">
              <CardContent className="pt-6">
                <div className="flex items-center gap-4">
                  <div className="p-4 bg-accent-500/10 rounded-xl">
                    <Coins className="h-8 w-8 text-accent-500" />
                  </div>
                  <div className="flex-1">
                    <h3 className="text-lg font-semibold text-white">Mint Tokens</h3>
                    <p className="text-sm text-dark-400">Create new programmable tokens</p>
                  </div>
                  <ArrowUpRight className="h-5 w-5 text-dark-400" />
                </div>
              </CardContent>
            </Card>
          </Link>

          <Link href="/transfer">
            <Card hover className="h-full cursor-pointer">
              <CardContent className="pt-6">
                <div className="flex items-center gap-4">
                  <div className="p-4 bg-highlight-500/10 rounded-xl">
                    <Send className="h-8 w-8 text-highlight-500" />
                  </div>
                  <div className="flex-1">
                    <h3 className="text-lg font-semibold text-white">Transfer Tokens</h3>
                    <p className="text-sm text-dark-400">Send tokens with validation</p>
                  </div>
                  <ArrowUpRight className="h-5 w-5 text-dark-400" />
                </div>
              </CardContent>
            </Card>
          </Link>
        </div>

        {/* Registered Tokens Table */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Coins className="h-5 w-5 text-primary-500" />
              Registered Programmable Tokens
            </CardTitle>
            <CardDescription>
              All tokens registered in the CIP-113 protocol registry
            </CardDescription>
          </CardHeader>
          <CardContent>
            {isLoadingTokens ? (
              <div className="flex justify-center py-12">
                <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
              </div>
            ) : error ? (
              <div className="p-4 bg-red-500/10 border border-red-500/20 rounded-lg">
                <div className="flex items-center gap-2 text-red-300">
                  <AlertCircle className="h-5 w-5" />
                  <p>{error}</p>
                </div>
              </div>
            ) : registeredTokens.length === 0 ? (
              <div className="text-center py-12">
                <Coins className="h-12 w-12 text-dark-500 mx-auto mb-4" />
                <p className="text-dark-400 mb-2">No tokens registered yet</p>
                <p className="text-sm text-dark-500">
                  Be the first to mint a programmable token!
                </p>
                <Link href="/mint">
                  <Button className="mt-4">Mint Your First Token</Button>
                </Link>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-dark-700">
                      <th className="text-left py-3 px-4 text-sm font-medium text-dark-400">Policy ID</th>
                      <th className="text-left py-3 px-4 text-sm font-medium text-dark-400">Transfer Logic</th>
                      <th className="text-left py-3 px-4 text-sm font-medium text-dark-400">Slot</th>
                      <th className="text-left py-3 px-4 text-sm font-medium text-dark-400">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {registeredTokens.map((token, idx) => (
                      <tr key={token.policyId || idx} className="border-b border-dark-800 hover:bg-dark-900/50">
                        <td className="py-3 px-4">
                          <span className="font-mono text-xs text-white">
                            {token.policyId?.slice(0, 16)}...{token.policyId?.slice(-8)}
                          </span>
                        </td>
                        <td className="py-3 px-4">
                          <Badge variant="default" size="sm">
                            {token.transferLogic?.slice(0, 12)}...
                          </Badge>
                        </td>
                        <td className="py-3 px-4 text-dark-400">
                          {token.slot?.toLocaleString()}
                        </td>
                        <td className="py-3 px-4">
                          <a
                            href={`https://preview.cardanoscan.io/transaction/${token.txHash}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-primary-500 hover:text-primary-400 text-sm inline-flex items-center gap-1"
                          >
                            View Tx
                            <ArrowUpRight className="h-3 w-3" />
                          </a>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Protocol Instances */}
        {protocolStats.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Database className="h-5 w-5 text-primary-500" />
                Protocol Instances
              </CardTitle>
              <CardDescription>
                Active CIP-113 protocol deployments
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {protocolStats.map((protocol) => (
                  <div
                    key={protocol.protocolParamsId}
                    className="p-4 bg-dark-900 rounded-lg border border-dark-700"
                  >
                    <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                      <div>
                        <div className="flex items-center gap-2 mb-2">
                          <Badge variant="success" size="sm">Active</Badge>
                          <span className="text-sm text-dark-400">
                            ID: {protocol.protocolParamsId}
                          </span>
                        </div>
                        <p className="text-xs font-mono text-dark-300">
                          Registry: {protocol.registryNodePolicyId?.slice(0, 24)}...
                        </p>
                        <p className="text-xs font-mono text-dark-300">
                          Logic: {protocol.progLogicScriptHash?.slice(0, 24)}...
                        </p>
                      </div>
                      <div className="text-right">
                        <p className="text-2xl font-bold text-white">{protocol.tokenCount || 0}</p>
                        <p className="text-sm text-dark-400">Tokens</p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </PageContainer>
  );
}
