"use client";

import { Badge } from '@/components/ui/badge';

export type TransactionBuilder = 'backend' | 'frontend';

interface TransactionBuilderToggleProps {
  value: TransactionBuilder;
  onChange: (value: TransactionBuilder) => void;
  disabled?: boolean;
}

export function TransactionBuilderToggle({
  value,
  onChange,
  disabled = false,
}: TransactionBuilderToggleProps) {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-dark-200">
          Transaction Builder
        </label>
        <Badge variant="info" size="sm">
          Educational Feature
        </Badge>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <button
          type="button"
          onClick={() => onChange('backend')}
          disabled={disabled}
          className={`
            p-4 rounded-lg border-2 transition-all
            ${
              value === 'backend'
                ? 'border-primary-500 bg-primary-500/10'
                : 'border-dark-700 bg-dark-800 hover:border-dark-600'
            }
            ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
          `}
        >
          <div className="text-left">
            <div className="flex items-center gap-2 mb-1">
              <div
                className={`w-4 h-4 rounded-full border-2 ${
                  value === 'backend'
                    ? 'border-primary-500 bg-primary-500'
                    : 'border-dark-600'
                }`}
              >
                {value === 'backend' && (
                  <div className="w-full h-full rounded-full bg-white scale-50" />
                )}
              </div>
              <span className="font-semibold text-white">Backend</span>
              <Badge variant="success" size="sm">
                Default
              </Badge>
            </div>
            <p className="text-xs text-dark-400">
              Backend builds & returns unsigned transaction
            </p>
          </div>
        </button>

        <button
          type="button"
          onClick={() => onChange('frontend')}
          disabled={disabled}
          className={`
            p-4 rounded-lg border-2 transition-all
            ${
              value === 'frontend'
                ? 'border-primary-500 bg-primary-500/10'
                : 'border-dark-700 bg-dark-800 hover:border-dark-600'
            }
            ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
          `}
        >
          <div className="text-left">
            <div className="flex items-center gap-2 mb-1">
              <div
                className={`w-4 h-4 rounded-full border-2 ${
                  value === 'frontend'
                    ? 'border-primary-500 bg-primary-500'
                    : 'border-dark-600'
                }`}
              >
                {value === 'frontend' && (
                  <div className="w-full h-full rounded-full bg-white scale-50" />
                )}
              </div>
              <span className="font-semibold text-white">Frontend</span>
              <Badge variant="info" size="sm">
                Beta
              </Badge>
            </div>
            <p className="text-xs text-dark-400">
              Build transaction locally with Mesh SDK
            </p>
          </div>
        </button>
      </div>

      <p className="text-xs text-dark-400">
        <strong>Educational Note:</strong> This toggle shows two approaches to building transactions.
        Backend mode is simpler and more reliable. Frontend mode demonstrates how to build transactions
        client-side for educational purposes.
      </p>
    </div>
  );
}
