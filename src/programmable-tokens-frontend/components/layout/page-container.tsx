import { ReactNode } from "react";
import { cn } from "@/lib/utils";

interface PageContainerProps {
  children: ReactNode;
  className?: string;
  maxWidth?: "sm" | "md" | "lg" | "xl" | "2xl" | "full";
}

const maxWidths = {
  sm: "max-w-2xl",
  md: "max-w-4xl",
  lg: "max-w-6xl",
  xl: "max-w-7xl",
  "2xl": "max-w-[1400px]",
  full: "max-w-full",
};

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
