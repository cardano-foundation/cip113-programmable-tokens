/**
 * Page Container Component
 *
 * A responsive container wrapper for page content. Provides consistent
 * padding, centering, and maximum width constraints across all pages.
 *
 * ## Width Options
 * - `sm`: max-w-2xl (672px)
 * - `md`: max-w-4xl (896px)
 * - `lg`: max-w-6xl (1152px) - default
 * - `xl`: max-w-7xl (1280px)
 * - `2xl`: max-w-[1400px]
 * - `full`: no max-width constraint
 *
 * @module components/layout/page-container
 */

import { ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Props for the PageContainer component.
 */
interface PageContainerProps {
  /** Child content to render */
  children: ReactNode;
  /** Additional CSS classes */
  className?: string;
  /** Maximum width constraint */
  maxWidth?: "sm" | "md" | "lg" | "xl" | "2xl" | "full";
}

/**
 * Tailwind class mapping for max-width options.
 */
const maxWidths = {
  sm: "max-w-2xl",
  md: "max-w-4xl",
  lg: "max-w-6xl",
  xl: "max-w-7xl",
  "2xl": "max-w-[1400px]",
  full: "max-w-full",
};

/**
 * Responsive page content container.
 *
 * @param props - Component props
 * @returns React component
 *
 * @example
 * ```tsx
 * <PageContainer maxWidth="md">
 *   <h1>Page Title</h1>
 *   <p>Page content...</p>
 * </PageContainer>
 * ```
 */
export function PageContainer({
  children,
  className,
  maxWidth = "lg"
}: PageContainerProps) {
  return (
    <div className={cn("container mx-auto px-4 py-8", maxWidths[maxWidth], className)}>
      {children}
    </div>
  );
}
