"use client";

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';
import { PageContainer } from '@/components/layout/page-container';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { RefreshCw, Coins, Send, ExternalLink, FileText, Github, ArrowRight, Server } from 'lucide-react';
import { ProtocolStatusCard } from '@/components/deploy/protocol-status-card';
import { BlueprintInfoCard } from '@/components/deploy/blueprint-info-card';
import { BootstrapParamsCard } from '@/components/deploy/bootstrap-params-card';
import { checkProtocolHealth, getProtocolBlueprint, getProtocolBootstrap, ProtocolBootstrapParams } from '@/lib/api/protocol';
import { ProtocolBlueprint } from '@/types/api';
import { useToast } from '@/components/ui/use-toast';

function getNetwork(): 'mainnet' | 'preprod' | 'preview' {
  const network = process.env.NEXT_PUBLIC_NETWORK;
  if (network === 'mainnet' || network === 'preprod' || network === 'preview') {
    return network;
  }
  return 'preview';
}

interface QuickActionProps {
  href: string;
  icon: React.ElementType;
  title: string;
  description: string;
  external?: boolean;
}

function QuickAction({ href, icon: Icon, title, description, external = false }: QuickActionProps) {
  const content = (
    <div className="flex items-center gap-4 p-4 rounded-lg bg-dark-800/50 hover:bg-dark-700/50 transition-colors group cursor-pointer">
      <div className="p-2 rounded-lg bg-primary-500/10 text-primary-400 group-hover:bg-primary-500/20">
        <Icon className="w-5 h-5" />
      </div>
      <div className="flex-1 min-w-0">
        <h3 className="font-medium text-white group-hover:text-primary-400 transition-colors">{title}</h3>
        <p className="text-sm text-dark-400">{description}</p>
      </div>
      {external ? <ExternalLink className="w-4 h-4 text-dark-400" /> : <ArrowRight className="w-4 h-4 text-dark-400 group-hover:text-primary-400 transition-colors" />}
    </div>
  );

  if (external) {
    return <a href={href} target="_blank" rel="noopener noreferrer">{content}</a>;
  }
  return <Link href={href}>{content}</Link>;
}

export default function DeployPage() {
  const { toast } = useToast();
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [health, setHealth] = useState<{
    isReady: boolean;
    hasBlueprint: boolean;
    hasBootstrap: boolean;
    validatorCount: number;
    error?: string;
  } | null>(null);
  const [blueprint, setBlueprint] = useState<ProtocolBlueprint | null>(null);
  const [bootstrapParams, setBootstrapParams] = useState<ProtocolBootstrapParams | null>(null);
  const network = getNetwork();

  const loadData = useCallback(async (showToast = false) => {
    setIsLoading(true);
    try {
      const [healthData, blueprintData, bootstrapData] = await Promise.allSettled([
        checkProtocolHealth(),
        getProtocolBlueprint(),
        getProtocolBootstrap(),
      ]);

      if (healthData.status === 'fulfilled') {
        setHealth(healthData.value);
      } else {
        setHealth({ isReady: false, hasBlueprint: false, hasBootstrap: false, validatorCount: 0, error: 'Failed to check protocol health' });
      }

      if (blueprintData.status === 'fulfilled') {
        setBlueprint(blueprintData.value);
      }

      if (bootstrapData.status === 'fulfilled') {
        setBootstrapParams(bootstrapData.value);
      }

      if (showToast) {
        toast({ title: 'Data Refreshed', description: 'Protocol information updated' });
      }
    } catch (error) {
      console.error('Failed to load protocol data:', error);
      if (showToast) {
        toast({ title: 'Error', description: 'Failed to refresh protocol data', variant: 'error' });
      }
    } finally {
      setIsLoading(false);
    }
  }, [toast]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadData(true);
    setIsRefreshing(false);
  };

  return (
    <PageContainer>
      <div className="max-w-4xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <div>
            <div className="flex items-center gap-3 mb-2">
              <h1 className="text-3xl font-bold text-white">Protocol Status</h1>
              <Badge variant="info" className="capitalize">{network}</Badge>
            </div>
            <p className="text-dark-300">CIP-0113 programmable tokens deployment information</p>
          </div>
          <Button variant="outline" onClick={handleRefresh} disabled={isLoading || isRefreshing}>
            <RefreshCw className={`w-4 h-4 mr-2 ${isRefreshing ? 'animate-spin' : ''}`} />
            Refresh
          </Button>
        </div>

        <div className="mb-6">
          <ProtocolStatusCard
            isReady={health?.isReady || false}
            hasBlueprint={health?.hasBlueprint || false}
            hasBootstrap={health?.hasBootstrap || false}
            validatorCount={health?.validatorCount || 0}
            isLoading={isLoading}
            error={health?.error}
          />
        </div>

        <div className="grid gap-6 md:grid-cols-2 mb-6">
          <BlueprintInfoCard blueprint={blueprint} isLoading={isLoading} />
          <BootstrapParamsCard params={bootstrapParams} isLoading={isLoading} network={network} />
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Server className="w-5 h-5" />
              Quick Actions
            </CardTitle>
            <CardDescription>Navigate to protocol operations</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <QuickAction href="/mint" icon={Coins} title="Mint Tokens" description="Create new programmable tokens with embedded logic" />
            <QuickAction href="/transfer" icon={Send} title="Transfer Tokens" description="Send tokens with programmable validation" />
            <QuickAction href="https://github.com/cardano-foundation/CIPs/tree/master/CIP-0113" icon={FileText} title="CIP-0113 Specification" description="Read the full programmable tokens specification" external />
            <QuickAction href="https://github.com/cardano-foundation/cip113-programmable-tokens" icon={Github} title="Source Code" description="View the reference implementation on GitHub" external />
          </CardContent>
        </Card>
      </div>
    </PageContainer>
  );
}
