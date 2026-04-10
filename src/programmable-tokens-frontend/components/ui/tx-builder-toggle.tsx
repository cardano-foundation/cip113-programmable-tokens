"use client";

import { cn } from "@/lib/utils/cn";

export type TransactionBuilder = "sdk" | "backend";

interface TxBuilderToggleProps {
  value: TransactionBuilder;
  onChange: (builder: TransactionBuilder) => void;
  sdkAvailable: boolean;
  className?: string;
}

export function TxBuilderToggle({ value, onChange, sdkAvailable, className }: TxBuilderToggleProps) {
  if (!sdkAvailable) return null;

  return (
    <div className={cn("flex items-center justify-between px-3 py-2 bg-dark-900 rounded-lg", className)}>
      <span className="text-xs text-dark-400">Tx Builder</span>
      <div className="flex gap-1 bg-dark-800 rounded-md p-0.5">
        <button
          type="button"
          onClick={() => onChange("sdk")}
          className={cn(
            "px-3 py-1 text-xs rounded transition-colors",
            value === "sdk"
              ? "bg-primary-500 text-white"
              : "text-dark-400 hover:text-white"
          )}
        >
          SDK
        </button>
        <button
          type="button"
          onClick={() => onChange("backend")}
          className={cn(
            "px-3 py-1 text-xs rounded transition-colors",
            value === "backend"
              ? "bg-primary-500 text-white"
              : "text-dark-400 hover:text-white"
          )}
        >
          Backend
        </button>
      </div>
    </div>
  );
}
