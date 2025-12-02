/**
 * Button Component
 *
 * A versatile button component with multiple variants and sizes.
 * Supports loading state and all standard HTML button attributes.
 *
 * ## Variants
 * - **primary**: Gradient background, used for main actions
 * - **secondary**: Accent color, used for secondary actions
 * - **ghost**: Transparent with border, for tertiary actions
 * - **outline**: Outline style for subtle actions
 * - **danger**: Red background for destructive actions
 *
 * ## Sizes
 * - **sm**: Small padding, text-sm
 * - **md**: Medium padding (default)
 * - **lg**: Large padding for prominent CTAs
 *
 * @module components/ui/button
 *
 * @example
 * ```tsx
 * <Button variant="primary" size="md" onClick={handleMint}>
 *   Mint Token
 * </Button>
 *
 * <Button variant="danger" isLoading={isDeleting}>
 *   Delete
 * </Button>
 * ```
 */

import { ButtonHTMLAttributes, forwardRef } from "react";
import { cn } from "@/lib/utils";

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "ghost" | "outline" | "danger";
  size?: "sm" | "md" | "lg";
  isLoading?: boolean;
}

const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = "primary", size = "md", isLoading, disabled, children, ...props }, ref) => {
    const baseStyles = "inline-flex items-center justify-center rounded-lg font-semibold transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-dark-900";

    const variants = {
      primary: "bg-gradient-primary text-white hover:shadow-lg hover:scale-[1.02] active:scale-[0.98] focus:ring-primary-500",
      secondary: "bg-accent-500 text-white hover:bg-accent-600 hover:shadow-lg hover:scale-[1.02] active:scale-[0.98] focus:ring-accent-500",
      ghost: "bg-transparent text-primary-400 hover:bg-dark-800 hover:text-primary-300 border border-dark-700 hover:border-primary-500 focus:ring-primary-500",
      outline: "bg-transparent text-white hover:bg-dark-800 border border-dark-600 hover:border-dark-500 focus:ring-dark-500",
      danger: "bg-red-600 text-white hover:bg-red-700 hover:shadow-lg hover:scale-[1.02] active:scale-[0.98] focus:ring-red-500",
    };

    const sizes = {
      sm: "px-3 py-1.5 text-sm",
      md: "px-6 py-3 text-base",
      lg: "px-8 py-4 text-lg",
    };

    return (
      <button
        ref={ref}
        className={cn(
          baseStyles,
          variants[variant],
          sizes[size],
          isLoading && "cursor-wait",
          className
        )}
        disabled={disabled || isLoading}
        {...props}
      >
        {isLoading ? (
          <div className="flex items-center gap-2">
            <svg
              className="animate-spin h-4 w-4"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
              />
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
            <span>{children}</span>
          </div>
        ) : (
          children
        )}
      </button>
    );
  }
);

Button.displayName = "Button";

export { Button };
