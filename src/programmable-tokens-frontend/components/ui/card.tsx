/**
 * Card Components
 *
 * A set of composable card components for building structured content containers.
 * Cards use a dark theme with rounded corners and subtle borders.
 *
 * ## Components
 * - **Card**: Main container with optional hover effects
 * - **CardHeader**: Top section for title and description
 * - **CardTitle**: Styled heading within CardHeader
 * - **CardDescription**: Muted text for card subtitle
 * - **CardContent**: Main content area with padding
 * - **CardFooter**: Bottom section for actions
 *
 * @module components/ui/card
 *
 * @example
 * ```tsx
 * <Card hover>
 *   <CardHeader>
 *     <CardTitle>Token Details</CardTitle>
 *     <CardDescription>Programmable token information</CardDescription>
 *   </CardHeader>
 *   <CardContent>
 *     <p>Token content here</p>
 *   </CardContent>
 *   <CardFooter>
 *     <Button>Action</Button>
 *   </CardFooter>
 * </Card>
 * ```
 */

import { HTMLAttributes, forwardRef } from "react";
import { cn } from "@/lib/utils";

export interface CardProps extends HTMLAttributes<HTMLDivElement> {
  hover?: boolean;
}

const Card = forwardRef<HTMLDivElement, CardProps>(
  ({ className, hover = false, ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={cn(
          "rounded-xl bg-dark-800 border border-dark-700 shadow-lg",
          hover && "transition-all duration-200 hover:border-primary-500 hover:shadow-primary-500/10 hover:shadow-xl",
          className
        )}
        {...props}
      />
    );
  }
);

Card.displayName = "Card";

const CardHeader = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  ({ className, ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={cn("p-6 border-b border-dark-700", className)}
        {...props}
      />
    );
  }
);

CardHeader.displayName = "CardHeader";

const CardTitle = forwardRef<HTMLHeadingElement, HTMLAttributes<HTMLHeadingElement>>(
  ({ className, ...props }, ref) => {
    return (
      <h3
        ref={ref}
        className={cn("text-xl font-bold text-white", className)}
        {...props}
      />
    );
  }
);

CardTitle.displayName = "CardTitle";

const CardDescription = forwardRef<HTMLParagraphElement, HTMLAttributes<HTMLParagraphElement>>(
  ({ className, ...props }, ref) => {
    return (
      <p
        ref={ref}
        className={cn("text-sm text-dark-300 mt-1", className)}
        {...props}
      />
    );
  }
);

CardDescription.displayName = "CardDescription";

const CardContent = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  ({ className, ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={cn("p-6", className)}
        {...props}
      />
    );
  }
);

CardContent.displayName = "CardContent";

const CardFooter = forwardRef<HTMLDivElement, HTMLAttributes<HTMLDivElement>>(
  ({ className, ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={cn("p-6 pt-0 flex items-center gap-4", className)}
        {...props}
      />
    );
  }
);

CardFooter.displayName = "CardFooter";

export { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter };
