/**
 * UI Components Module
 *
 * Barrel export for all reusable UI primitives. These components
 * provide consistent styling and behavior across the application.
 *
 * ## Available Components
 * - **Button**: Primary action buttons with variants
 * - **Card**: Content containers with header/content/footer
 * - **Input**: Form text inputs with validation
 * - **Select**: Dropdown selection inputs
 * - **Badge**: Status indicators and labels
 * - **Toast/Toaster**: Notification system
 *
 * ## Usage
 * ```tsx
 * import { Button, Card, Input, Badge } from '@/components/ui';
 * ```
 *
 * @module components/ui
 */

export { Button } from "./button";
export type { ButtonProps } from "./button";

export { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from "./card";
export type { CardProps } from "./card";

export { Input } from "./input";
export type { InputProps } from "./input";

export { Select } from "./select";
export type { SelectProps, SelectOption } from "./select";

export { Badge } from "./badge";
export type { BadgeProps } from "./badge";

export { Toast, Toaster, useToast } from "./toast";
export type { Toast as ToastType, ToastVariant } from "./use-toast";
