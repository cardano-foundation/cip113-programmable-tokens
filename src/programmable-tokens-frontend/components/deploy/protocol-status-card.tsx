/**
 * Protocol Status Card Component
 *
 * Displays the current status of the CIP-0113 protocol deployment.
 * Shows health checks for blueprint availability, bootstrap params,
 * and validator count.
 *
 * @module components/deploy/protocol-status-card
 */

"use client";

import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { CheckCircle, XCircle, AlertCircle, Database, FileCode, Settings } from 'lucide-react';

/**
 * Props for ProtocolStatusCard component.
 */
interface ProtocolStatusCardProps {
  /** Whether the protocol is fully ready */
  isReady: boolean;
  /** Whether the Plutus blueprint is loaded */
  hasBlueprint: boolean;
  /** Whether bootstrap parameters are available */
  hasBootstrap: boolean;
  /** Number of validators in the blueprint */
  validatorCount: number;
  /** Loading state */
  isLoading?: boolean;
  /** Error message if status check failed */
  error?: string;
}

/**
 * Status indicator with icon and label.
 */
function StatusIndicator({
  status,
  label,
  detail,
}: {
  status: 'success' | 'error' | 'warning' | 'loading';
  label: string;
  detail?: string;
}) {
  const icons = {
    success: <CheckCircle className="w-5 h-5 text-green-500" />,
    error: <XCircle className="w-5 h-5 text-red-500" />,
    warning: <AlertCircle className="w-5 h-5 text-yellow-500" />,
    loading: (
      <div className="w-5 h-5 border-2 border-primary-500 border-t-transparent rounded-full animate-spin" />
    ),
  };

  return (
    <div className="flex items-center gap-3 p-3 rounded-lg bg-dark-800/50">
      {icons[status]}
      <div className="flex-1">
        <span className="text-white font-medium">{label}</span>
        {detail && <p className="text-sm text-dark-400 mt-0.5">{detail}</p>}
      </div>
    </div>
  );
}

/**
 * Protocol status card showing deployment health.
 *
 * @param props - Component props
 * @returns React component
 *
 * @example
 * ```tsx
 * <ProtocolStatusCard
 *   isReady={true}
 *   hasBlueprint={true}
 *   hasBootstrap={true}
 *   validatorCount={12}
 * />
 * ```
 */
export function ProtocolStatusCard({
  isReady,
  hasBlueprint,
  hasBootstrap,
  validatorCount,
  isLoading = false,
  error,
}: ProtocolStatusCardProps) {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Protocol Status</CardTitle>
            <CardDescription>
              CIP-0113 deployment health check
            </CardDescription>
          </div>
          <Badge
            variant={isLoading ? 'default' : isReady ? 'success' : 'error'}
          >
            {isLoading ? 'Checking...' : isReady ? 'Ready' : 'Not Ready'}
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {error && (
          <div className="p-3 bg-red-500/10 border border-red-500/20 rounded-lg mb-4">
            <p className="text-sm text-red-300">{error}</p>
          </div>
        )}

        <StatusIndicator
          status={isLoading ? 'loading' : hasBlueprint ? 'success' : 'error'}
          label="Plutus Blueprint"
          detail={
            hasBlueprint
              ? `${validatorCount} validators loaded`
              : 'Blueprint not available'
          }
        />

        <StatusIndicator
          status={isLoading ? 'loading' : hasBootstrap ? 'success' : 'error'}
          label="Bootstrap Parameters"
          detail={
            hasBootstrap
              ? 'Protocol UTxOs configured'
              : 'Bootstrap params not loaded'
          }
        />

        <StatusIndicator
          status={
            isLoading
              ? 'loading'
              : isReady
                ? 'success'
                : 'warning'
          }
          label="Protocol Ready"
          detail={
            isReady
              ? 'All systems operational'
              : 'Protocol not fully initialized'
          }
        />
      </CardContent>
    </Card>
  );
}
