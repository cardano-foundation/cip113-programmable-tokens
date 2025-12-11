/**
 * Transaction Builder Toggle Component
 *
 * An educational feature toggle that allows users to choose between
 * backend and frontend transaction building. This helps users understand
 * the different approaches to building Cardano transactions.
 *
 * ## Builder Options
 *
 * ### Backend Builder (Recommended)
 * - Transactions built on the server using cardano-client-lib
 * - Handles script references and protocol parameters
 * - More reliable for complex programmable token transactions
 *
 * ### Frontend Builder
 * - Transactions built in browser using Mesh SDK
 * - Educational: shows client-side transaction construction
 * - Useful for understanding the transaction building process
 *
 * @module components/mint/transaction-builder-toggle
 */

"use client";

import { Badge } from '@/components/ui/badge';

/**
 * Transaction builder type selection.
 */
export type TransactionBuilder = 'backend' | 'frontend';

/**
 * Props for TransactionBuilderToggle component.
 */
interface TransactionBuilderToggleProps {
  /** Currently selected builder */
  value: TransactionBuilder;
  /** Callback when selection changes */
  onChange: (value: TransactionBuilder) => void;
  /** Whether the toggle is disabled */
  disabled?: boolean;
}

/**
 * Toggle for selecting transaction building approach.
 *
 * @param props - Component props
 * @returns React component
 *
 * @example
 * ```tsx
 * <TransactionBuilderToggle
 *   value={builder}
 *   onChange={setBuilder}
 * />
 * ```
 */
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
            ${value === 'backend'
              ? 'border-primary-500 bg-primary-500/10'
              : 'border-dark-700 bg-dark-800 hover:border-dark-600'
            }
            ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
          `}
        >
          <div className="text-left">
            <div className="flex items-center gap-2 mb-1">
              <div
                className={`w-4 h-4 rounded-full border-2 ${value === 'backend'
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
          disabled={true} // Always disabled for now
          className="p-4 rounded-lg border-2 border-dark-700 bg-dark-800 opacity-50 cursor-not-allowed"
        >
          <div className="text-left">
            <div className="flex items-center gap-2 mb-1">
              <div className="w-4 h-4 rounded-full border-2 border-dark-600" />
              <span className="font-semibold text-white">Frontend</span>
              <Badge variant="warning" size="sm">
                Coming Soon
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
