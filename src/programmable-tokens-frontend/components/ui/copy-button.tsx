"use client";

import { useState, useCallback } from 'react';
import { Button } from './button';

interface CopyButtonProps {
  /** Value to copy to clipboard */
  value: string;
  /** Optional label to display */
  label?: string;
  /** Size variant */
  size?: 'sm' | 'default';
  /** Optional callback after copy */
  onCopy?: () => void;
}

export function CopyButton({ value, label, size = 'default', onCopy }: CopyButtonProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      onCopy?.();
      setTimeout(() => setCopied(false), 2000);
    } catch (error) {
      console.error('Failed to copy:', error);
    }
  }, [value, onCopy]);

  const iconSize = size === 'sm' ? 'w-3 h-3' : 'w-4 h-4';
  const buttonSize = size === 'sm' ? 'p-1' : 'p-1.5';

  return (
    <Button
      type="button"
      variant="ghost"
      size="sm"
      className={`${buttonSize} text-dark-400 hover:text-white`}
      onClick={handleCopy}
      title={copied ? 'Copied!' : 'Copy to clipboard'}
    >
      {copied ? (
        <svg
          className={`${iconSize} text-green-400`}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M5 13l4 4L19 7"
          />
        </svg>
      ) : (
        <svg
          className={iconSize}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
          />
        </svg>
      )}
      {label && <span className="ml-1">{label}</span>}
    </Button>
  );
}
