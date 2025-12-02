/**
 * Utility Functions Module
 *
 * This module re-exports all utility functions for convenient importing.
 * Utilities are organized into categories:
 *
 * ## CSS Utilities (cn.ts)
 * - `cn` - Tailwind class merging
 *
 * ## Formatting Utilities (format.ts)
 * - `truncateAddress` - Shorten Cardano addresses
 * - `formatADA` / `formatADAWithSymbol` - ADA amount formatting
 * - `formatNumber` / `formatTokenAmount` - Number formatting
 * - `getNetworkDisplayName` / `getNetworkColor` - Network helpers
 *
 * ## Validation Utilities (validation.ts)
 * - `validateTokenName` - Token name validation
 * - `validateQuantity` - Quantity validation
 * - `validateCardanoAddress` - Address format validation
 * - `validateHexString` - Hex string validation
 * - `getByteLength` - UTF-8 byte length calculation
 *
 * @module lib/utils
 */

export { cn } from "./cn";
export {
  truncateAddress,
  formatADA,
  formatADAWithSymbol,
  formatNumber,
  formatTokenAmount,
  getNetworkDisplayName,
  getNetworkColor,
} from "./format";
export {
  validateTokenName,
  validateQuantity,
  validateCardanoAddress,
  validateHexString,
  getByteLength,
} from "./validation";
