"use client";

import { useProtocolVersion } from '@/contexts/protocol-version-context';
import { X, Settings, RefreshCw } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';

interface ProPanelModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function ProPanelModal({ isOpen, onClose }: ProPanelModalProps) {
  const { versions, selectedVersion, isLoading, selectVersion, resetToDefault } = useProtocolVersion();

  if (!isOpen) return null;

  const formatDate = (timestamp: number) => {
    try {
      // Backend returns Unix timestamp in seconds, JavaScript Date expects milliseconds
      return new Date(timestamp * 1000).toLocaleString();
    } catch {
      return String(timestamp);
    }
  };

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/50 z-50"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
        <Card className="w-full max-w-2xl max-h-[80vh] overflow-y-auto">
          <CardHeader>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Settings className="h-5 w-5 text-primary-500" />
                <CardTitle>Advanced Settings</CardTitle>
              </div>
              <button
                onClick={onClose}
                className="p-2 hover:bg-dark-700 rounded transition-colors"
                title="Close"
              >
                <X className="h-5 w-5 text-dark-400 hover:text-white" />
              </button>
            </div>
            <CardDescription>
              Advanced protocol version settings for power users
            </CardDescription>
          </CardHeader>

          <CardContent className="space-y-6">
            {/* Protocol Version Selector */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-white">Protocol Version</label>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={resetToDefault}
                  disabled={selectedVersion?.default}
                >
                  <RefreshCw className="h-3 w-3 mr-1" />
                  Reset to Default
                </Button>
              </div>

              {isLoading ? (
                <div className="flex items-center justify-center py-4">
                  <div className="h-6 w-6 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
                </div>
              ) : versions.length === 0 ? (
                <div className="p-4 bg-dark-900 rounded text-center text-dark-400 text-sm">
                  No protocol versions available
                </div>
              ) : (
                <select
                  value={selectedVersion?.txHash || ''}
                  onChange={(e) => selectVersion(e.target.value)}
                  className="w-full px-3 py-2 bg-dark-900 border border-dark-700 rounded text-white text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
                >
                  {versions.map((v) => (
                    <option key={v.txHash} value={v.txHash}>
                      {v.txHash.substring(0, 16)}...{v.txHash.substring(v.txHash.length - 8)}
                      {v.default && ' (Default)'}
                      {' - '}Slot {v.slot}
                      {' - '}{formatDate(v.timestamp)}
                    </option>
                  ))}
                </select>
              )}
            </div>

            {/* Selected Version Details */}
            {selectedVersion && (
              <div className="space-y-3">
                <div className="flex items-center gap-2">
                  <h3 className="text-sm font-medium text-white">Version Details</h3>
                  {selectedVersion.default && (
                    <Badge variant="success" size="sm">Default</Badge>
                  )}
                </div>

                <div className="p-4 bg-dark-900 rounded space-y-2 text-xs font-mono">
                  <div className="flex flex-col gap-1">
                    <span className="text-dark-400">Transaction Hash:</span>
                    <span className="text-primary-400 break-all">{selectedVersion.txHash}</span>
                  </div>

                  <div className="flex flex-col gap-1">
                    <span className="text-dark-400">Registry Node Policy ID:</span>
                    <span className="text-accent-400 break-all">{selectedVersion.registryNodePolicyId}</span>
                  </div>

                  <div className="flex flex-col gap-1">
                    <span className="text-dark-400">Programmable Logic Script Hash:</span>
                    <span className="text-highlight-400 break-all">{selectedVersion.progLogicScriptHash}</span>
                  </div>

                  <div className="grid grid-cols-2 gap-4 pt-2 border-t border-dark-700">
                    <div>
                      <span className="text-dark-400">Slot:</span>
                      <span className="text-white ml-2">{selectedVersion.slot}</span>
                    </div>
                    <div>
                      <span className="text-dark-400">Timestamp:</span>
                      <span className="text-white ml-2">{formatDate(selectedVersion.timestamp)}</span>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Info Banner */}
            <div className="p-3 bg-primary-500/10 border border-primary-500/20 rounded">
              <p className="text-xs text-primary-300">
                <strong>Note:</strong> Changing the protocol version will filter balances, minting, and transfers
                to only show data for the selected version. This is useful when multiple protocol versions are
                deployed on the same network.
              </p>
            </div>
          </CardContent>
        </Card>
      </div>
    </>
  );
}
