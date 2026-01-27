"use client";

import { useState, useRef, useEffect } from "react";
import { ChevronDown, Coins } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { AdminTokenInfo, AdminRole } from "@/lib/api/admin";

interface AdminTokenSelectorProps {
  tokens: AdminTokenInfo[];
  selectedToken: AdminTokenInfo | null;
  onSelect: (token: AdminTokenInfo) => void;
  disabled?: boolean;
  filterByRole?: AdminRole;
}

export function AdminTokenSelector({
  tokens,
  selectedToken,
  onSelect,
  disabled = false,
  filterByRole,
}: AdminTokenSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Filter tokens by role if specified
  const filteredTokens = filterByRole
    ? tokens.filter((token) => token.roles.includes(filterByRole))
    : tokens;

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node)
      ) {
        setIsOpen(false);
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleSelect = (token: AdminTokenInfo) => {
    onSelect(token);
    setIsOpen(false);
  };

  const getRoleBadges = (roles: AdminRole[]) => {
    return roles.map((role) => {
      const variant = role === "ISSUER_ADMIN" ? "success" : "info";
      const label = role === "ISSUER_ADMIN" ? "Issuer" : "Blacklist";
      return (
        <Badge key={role} variant={variant} size="sm">
          {label}
        </Badge>
      );
    });
  };

  return (
    <div className="relative" ref={dropdownRef}>
      <label className="block text-sm font-medium text-white mb-2">
        Select Token
      </label>
      <button
        type="button"
        onClick={() => !disabled && setIsOpen(!isOpen)}
        disabled={disabled}
        className={cn(
          "w-full flex items-center justify-between gap-2 px-4 py-3 rounded-lg border",
          "bg-dark-800 border-dark-700 text-white",
          "hover:border-primary-500 transition-colors",
          "disabled:opacity-50 disabled:cursor-not-allowed"
        )}
      >
        <div className="flex items-center gap-3 flex-1 min-w-0">
          {selectedToken ? (
            <>
              <Coins className="h-5 w-5 text-primary-500 flex-shrink-0" />
              <div className="text-left flex-1 min-w-0">
                <p className="text-sm font-medium truncate">
                  {selectedToken.assetNameDisplay}
                </p>
                <p className="text-xs text-dark-400 truncate">
                  {selectedToken.policyId.substring(0, 20)}...
                </p>
              </div>
              <div className="flex gap-1">{getRoleBadges(selectedToken.roles)}</div>
            </>
          ) : (
            <>
              <Coins className="h-5 w-5 text-dark-500 flex-shrink-0" />
              <span className="text-dark-400">
                {filteredTokens.length === 0
                  ? "No tokens available"
                  : "Select a token to manage"}
              </span>
            </>
          )}
        </div>
        <ChevronDown
          className={cn(
            "h-4 w-4 text-dark-400 transition-transform flex-shrink-0",
            isOpen && "transform rotate-180"
          )}
        />
      </button>

      {isOpen && filteredTokens.length > 0 && (
        <div className="absolute z-10 w-full mt-2 bg-dark-800 border border-dark-700 rounded-lg shadow-xl max-h-64 overflow-y-auto">
          <div className="p-2 border-b border-dark-700">
            <p className="text-xs text-dark-400 px-2">
              {filterByRole
                ? `Tokens with ${filterByRole.replace("_", " ").toLowerCase()} role`
                : "All administered tokens"}
            </p>
          </div>
          {filteredTokens.map((token, index) => (
            <button
              key={`${token.policyId}-${index}`}
              type="button"
              onClick={() => handleSelect(token)}
              className={cn(
                "w-full px-4 py-3 text-left hover:bg-dark-700 transition-colors",
                "border-b border-dark-700 last:border-b-0",
                selectedToken?.policyId === token.policyId && "bg-dark-700"
              )}
            >
              <div className="flex items-center justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-white truncate">
                    {token.assetNameDisplay}
                  </p>
                  <p
                    className="text-xs text-dark-400 truncate"
                    title={token.policyId}
                  >
                    Policy: {token.policyId.substring(0, 20)}...
                  </p>
                  <p className="text-xs text-dark-500 mt-1">
                    Standard: {token.substandardId}
                  </p>
                </div>
                <div className="flex flex-col gap-1 items-end">
                  {getRoleBadges(token.roles)}
                </div>
              </div>
            </button>
          ))}
        </div>
      )}

      {filterByRole && filteredTokens.length === 0 && (
        <p className="mt-2 text-xs text-dark-400">
          No tokens with {filterByRole.replace("_", " ").toLowerCase()} permissions
        </p>
      )}
    </div>
  );
}
