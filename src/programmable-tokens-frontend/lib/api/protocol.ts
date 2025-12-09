/**
 * API functions for fetching protocol blueprints and bootstrap data
 */

import { apiGet } from './client';
import type { ProtocolBlueprint, ProtocolBootstrapParams, SubstandardBlueprint } from '@/types/protocol';

/**
 * Get protocol blueprint (validators and compiled code)
 *
 * @returns Protocol blueprint with all validators
 */
export async function getProtocolBlueprint(): Promise<ProtocolBlueprint> {
  return apiGet<ProtocolBlueprint>('/protocol/blueprint');
}

/**
 * Get protocol bootstrap parameters
 *
 * @param protocolTxHash - Optional protocol version tx hash (uses default if not provided)
 * @returns Protocol bootstrap parameters
 */
export async function getProtocolBootstrap(protocolTxHash?: string): Promise<ProtocolBootstrapParams> {
  const endpoint = protocolTxHash
    ? `/protocol/bootstrap?txHash=${protocolTxHash}`
    : '/protocol/bootstrap';

  return apiGet<ProtocolBootstrapParams>(endpoint);
}

/**
 * Get substandard blueprint (validators for a specific substandard)
 *
 * @param substandardId - The substandard identifier (e.g., "dummy", "bafin")
 * @returns Substandard blueprint with validators
 */
export async function getSubstandardBlueprint(substandardId: string): Promise<SubstandardBlueprint> {
  return apiGet<SubstandardBlueprint>(`/substandards/${substandardId}`);
}
