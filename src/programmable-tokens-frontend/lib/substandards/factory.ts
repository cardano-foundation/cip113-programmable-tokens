/**
 * Simple factory for substandard handlers
 * Currently only supports "dummy" substandard
 */

import type { IWallet } from '@meshsdk/core';
import type { ProtocolBootstrapParams, ProtocolBlueprint, SubstandardBlueprint } from '@/types/protocol';
import { buildDummyMintTransaction, type MintTransactionParams } from './dummy-handler';

export type SubstandardId = 'dummy' | 'bafin';

export interface SubstandardHandler {
  buildMintTransaction(
    params: MintTransactionParams,
    protocolParams: ProtocolBootstrapParams,
    protocolBlueprint: ProtocolBlueprint,
    substandardBlueprint: SubstandardBlueprint,
    wallet: IWallet
  ): Promise<string>;
}

/**
 * Dummy substandard handler
 */
const dummyHandler: SubstandardHandler = {
  buildMintTransaction: buildDummyMintTransaction,
};

/**
 * Bafin substandard handler (stub - not implemented)
 */
const bafinHandler: SubstandardHandler = {
  buildMintTransaction: async () => {
    throw new Error('Bafin substandard not yet implemented for client-side transaction building');
  },
};

/**
 * Registry of substandard handlers
 */
const handlers: Record<string, SubstandardHandler> = {
  dummy: dummyHandler,
  bafin: bafinHandler,
};

/**
 * Get a substandard handler by ID
 *
 * @param substandardId - The substandard identifier
 * @returns The handler for the substandard
 * @throws Error if substandard not found
 */
export function getSubstandardHandler(substandardId: SubstandardId): SubstandardHandler {
  const handler = handlers[substandardId.toLowerCase()];

  if (!handler) {
    throw new Error(`Substandard not found: ${substandardId}`);
  }

  return handler;
}

/**
 * Check if a substandard is supported for client-side transaction building
 *
 * @param substandardId - The substandard identifier
 * @returns true if supported, false otherwise
 */
export function isSubstandardSupported(substandardId: string): boolean {
  return substandardId.toLowerCase() in handlers;
}

/**
 * Get all supported substandard IDs
 *
 * @returns Array of supported substandard IDs
 */
export function getSupportedSubstandards(): SubstandardId[] {
  return Object.keys(handlers) as SubstandardId[];
}
