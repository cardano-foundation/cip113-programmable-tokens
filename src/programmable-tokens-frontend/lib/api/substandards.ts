/**
 * Substandards API Client
 *
 * This module provides functions for fetching and querying CIP-0113 substandard
 * validators. Substandards define the programmable behavior of tokens, such as
 * transfer restrictions, blacklist enforcement, or KYC requirements.
 *
 * ## Architecture
 *
 * Substandards are stored on the backend as individual Plutus blueprint files
 * in the `resources/substandards/` directory. Each substandard contains one or
 * more validators that implement specific token behaviors.
 *
 * ## Available Substandards
 *
 * Common substandards include:
 * - **blacklist**: Block transfers to/from specific addresses
 * - **whitelist**: Allow transfers only to approved addresses
 * - **transfer-limit**: Enforce maximum transfer amounts
 * - **kyc-required**: Require identity verification for transfers
 *
 * ## Usage
 *
 * ```typescript
 * import { getSubstandards, getValidatorTitles } from '@/lib/api/substandards';
 *
 * // Fetch all available substandards
 * const substandards = await getSubstandards();
 *
 * // Get validator titles for a specific substandard
 * const titles = getValidatorTitles('blacklist', substandards);
 * // ['blacklist_mint.mint', 'example_transfer_logic.spend']
 * ```
 *
 * @module lib/api/substandards
 */

import { SubstandardsResponse } from '@/types/api';
import { apiGet } from './client';

// ============================================================================
// API Functions
// ============================================================================

/**
 * Fetch available substandards from the backend.
 *
 * Retrieves the list of all configured substandard validators with their
 * metadata and compiled script information.
 *
 * @returns Promise resolving to array of substandard configurations
 * @throws {ApiException} If the API request fails
 *
 * @example
 * ```typescript
 * const substandards = await getSubstandards();
 * console.log(`Found ${substandards.length} substandards`);
 * substandards.forEach(s => console.log(`- ${s.id}: ${s.name}`));
 * ```
 */
export async function getSubstandards(): Promise<SubstandardsResponse> {
  return apiGet<SubstandardsResponse>('/substandards');
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Get validator titles for a specific substandard.
 *
 * Validator titles follow the Aiken naming convention: `module_name.purpose`
 * (e.g., "blacklist_mint.mint", "example_transfer_logic.spend").
 *
 * @param substandardId - The substandard ID (e.g., "blacklist")
 * @param substandards - The full substandards response from getSubstandards()
 * @returns Array of validator title strings, or empty array if not found
 *
 * @example
 * ```typescript
 * const titles = getValidatorTitles('blacklist', substandards);
 * // ['blacklist_mint.mint', 'example_transfer_logic.spend']
 * ```
 */
export function getValidatorTitles(substandardId: string, substandards: SubstandardsResponse): string[] {
  const substandard = substandards.find(s => s.id === substandardId);
  if (!substandard) return [];

  return substandard.validators.map(v => v.title);
}

/**
 * Check if a validator exists in a substandard.
 *
 * Useful for validation before attempting to use a specific validator
 * for token operations.
 *
 * @param substandardId - The substandard ID to search in
 * @param validatorTitle - The exact validator title to look for
 * @param substandards - The full substandards response
 * @returns true if the validator exists, false otherwise
 *
 * @example
 * ```typescript
 * if (hasValidator('blacklist', 'blacklist_mint.mint', substandards)) {
 *   // Safe to use this validator
 * }
 * ```
 */
export function hasValidator(
  substandardId: string,
  validatorTitle: string,
  substandards: SubstandardsResponse
): boolean {
  const titles = getValidatorTitles(substandardId, substandards);
  return titles.includes(validatorTitle);
}
