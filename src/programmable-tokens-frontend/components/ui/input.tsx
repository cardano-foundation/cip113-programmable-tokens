/**
 * Input Component
 *
 * A styled form input with optional label, error state, and helper text.
 * Extends all standard HTML input attributes.
 *
 * ## Features
 * - Optional label rendered above input
 * - Error state with red border and message
 * - Helper text for guidance
 * - Dark theme styling with focus rings
 * - Full width by default
 *
 * ## Accessibility
 * - Label properly associated with input
 * - Error messages visible to screen readers
 * - Focus states meet WCAG requirements
 *
 * @module components/ui/input
 *
 * @example
 * ```tsx
 * <Input
 *   label="Asset Name"
 *   placeholder="Enter token name"
 *   error={errors.assetName}
 *   helperText="Must be alphanumeric"
 * />
 * ```
 */

import { InputHTMLAttributes, forwardRef } from "react";
import { cn } from "@/lib/utils";

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  helperText?: string;
}

const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ className, label, error, helperText, type = "text", ...props }, ref) => {
    return (
      <div className="w-full">
        {label && (
          <label className="block text-sm font-medium text-dark-200 mb-2">
            {label}
          </label>
        )}
        <input
          type={type}
          className={cn(
            "flex w-full rounded-lg border bg-dark-800 px-4 py-3 text-white placeholder:text-dark-400",
            "transition-colors duration-200",
            "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-dark-900",
            "disabled:cursor-not-allowed disabled:opacity-50",
            error
              ? "border-red-500 focus:ring-red-500"
              : "border-dark-700 focus:border-primary-500 focus:ring-primary-500",
            className
          )}
          ref={ref}
          {...props}
        />
        {error && (
          <p className="mt-2 text-sm text-red-500">{error}</p>
        )}
        {helperText && !error && (
          <p className="mt-2 text-sm text-dark-400">{helperText}</p>
        )}
      </div>
    );
  }
);

Input.displayName = "Input";

export { Input };
