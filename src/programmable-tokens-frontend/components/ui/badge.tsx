import { HTMLAttributes, forwardRef } from "react";
import { cn } from "@/lib/utils";

export interface BadgeProps extends HTMLAttributes<HTMLDivElement> {
  variant?: "default" | "success" | "error" | "warning" | "info";
  size?: "sm" | "md";
}

const Badge = forwardRef<HTMLDivElement, BadgeProps>(
  ({ className, variant = "default", size = "md", ...props }, ref) => {
    const variants = {
      default: "bg-dark-700 text-dark-200 border-dark-600",
      success: "bg-primary-500/10 text-primary-400 border-primary-500/20",
      error: "bg-red-500/10 text-red-400 border-red-500/20",
      warning: "bg-accent-500/10 text-accent-400 border-accent-500/20",
      info: "bg-blue-500/10 text-blue-400 border-blue-500/20",
    };

    const sizes = {
      sm: "px-2 py-0.5 text-xs",
      md: "px-3 py-1 text-sm",
    };

    return (
      <div
        ref={ref}
        className={cn(
          "inline-flex items-center gap-1 rounded-full border font-medium",
          variants[variant],
          sizes[size],
          className
        )}
        {...props}
      />
    );
  }
);

Badge.displayName = "Badge";

export { Badge };
