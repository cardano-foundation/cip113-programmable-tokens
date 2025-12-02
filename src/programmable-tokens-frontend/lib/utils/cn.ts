/**
 * CSS Class Name Utility
 *
 * Combines clsx for conditional class handling with tailwind-merge
 * to intelligently merge Tailwind CSS classes, resolving conflicts.
 *
 * ## Why tailwind-merge?
 * Tailwind classes can conflict (e.g., `p-2 p-4`). tailwind-merge
 * resolves these by keeping only the last applicable class.
 *
 * @module lib/utils/cn
 */

import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * Merge and deduplicate Tailwind CSS class names.
 *
 * Combines conditional class logic (clsx) with Tailwind conflict
 * resolution (tailwind-merge) for clean, predictable class output.
 *
 * @param inputs - Class values (strings, objects, arrays)
 * @returns Merged class string with conflicts resolved
 *
 * @example
 * ```typescript
 * cn("p-2 p-4")           // "p-4"
 * cn("bg-red-500", false && "bg-blue-500")  // "bg-red-500"
 * cn({ "hidden": isHidden }, "flex")        // "flex" or "hidden flex"
 * ```
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
