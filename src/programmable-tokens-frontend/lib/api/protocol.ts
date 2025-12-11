/**
 * Protocol API Functions
 *
 * This module provides functions for interacting with CIP-0113 protocol
 * configuration endpoints. Used by the deploy page and protocol status displays.
 *
 * ## Endpoints
 * - `GET /api/v1/protocol/blueprint` - Aiken-generated Plutus blueprint
 * - `GET /api/v1/protocol/bootstrap` - Bootstrap parameters for the deployment
 * - `GET /api/v1/protocol-params/latest` - Latest protocol params version
 * - `GET /api/v1/registry/protocols` - All protocol versions with stats
 *
 * @module lib/api/protocol
 */

import { apiGet } from './client';
import { ProtocolBlueprint } from '@/types/api';

/**
 * Protocol bootstrap parameters returned by the backend.
 *
 * Contains UTxO references and script hashes for the deployed protocol.
 */
export interface ProtocolBootstrapParams {
  /** Protocol params UTxO reference */
  protocolParamsUtxo: {
    txHash: string;
    outputIndex: number;
  };
  /** Directory UTxO reference */
  directoryUtxo: {
    txHash: string;
    outputIndex: number;
  };
  /** Issuance UTxO reference */
  issuanceUtxo: {
    txHash: string;
    outputIndex: number;
  };
  /** Programmable logic base parameters */
  programmableLogicBaseParams: {
    scriptHash: string;
  };
  /** Directory mint parameters */
  directoryMintParams: {
    txInput: {
      txHash: string;
      outputIndex: number;
    };
    issuanceScriptHash: string;
  };
  /** Protocol params script information */
  protocolParams: {
    scriptHash: string;
  };
}

/**
 * Protocol params entity from database.
 */
export interface ProtocolParamsEntity {
  id: number;
  registryNodePolicyId: string;
  progLogicScriptHash: string;
  slot: number;
  txHash: string;
}

/**
 * Protocol statistics from registry.
 */
export interface ProtocolWithStats {
  protocolParamsId: number;
  registryNodePolicyId: string;
  progLogicScriptHash: string;
  tokenCount: number;
}

/**
 * Fetch the Plutus blueprint from the backend.
 *
 * The blueprint contains all compiled validators for the CIP-0113 protocol.
 *
 * @returns Promise resolving to the Plutus blueprint
 * @throws {ApiException} If the request fails
 *
 * @example
 * ```typescript
 * const blueprint = await getProtocolBlueprint();
 * console.log('Validators:', blueprint.validators.length);
 * ```
 */
export async function getProtocolBlueprint(): Promise<ProtocolBlueprint> {
  return apiGet<ProtocolBlueprint>('/protocol/blueprint');
}

/**
 * Fetch the protocol bootstrap parameters.
 *
 * Bootstrap parameters define the specific deployment instance with
 * UTxO references and script hashes.
 *
 * @returns Promise resolving to bootstrap parameters
 * @throws {ApiException} If the request fails
 *
 * @example
 * ```typescript
 * const params = await getProtocolBootstrap();
 * console.log('Protocol params UTxO:', params.protocolParamsUtxo.txHash);
 * ```
 */
export async function getProtocolBootstrap(): Promise<ProtocolBootstrapParams> {
  return apiGet<ProtocolBootstrapParams>('/protocol/bootstrap');
}

/**
 * Fetch the latest protocol params version.
 *
 * @returns Promise resolving to the latest protocol params, or null if none exist
 * @throws {ApiException} If the request fails (except 404)
 *
 * @example
 * ```typescript
 * const latest = await getLatestProtocolParams();
 * if (latest) {
 *   console.log('Latest protocol at slot:', latest.slot);
 * }
 * ```
 */
export async function getLatestProtocolParams(): Promise<ProtocolParamsEntity | null> {
  try {
    return await apiGet<ProtocolParamsEntity>('/protocol-params/latest');
  } catch (error) {
    // Return null for 404 (no protocol deployed yet)
    if (error && typeof error === 'object' && 'status' in error && error.status === 404) {
      return null;
    }
    throw error;
  }
}

/**
 * Fetch all protocol versions with their registry statistics.
 *
 * @returns Promise resolving to array of protocol versions with token counts
 * @throws {ApiException} If the request fails
 *
 * @example
 * ```typescript
 * const protocols = await getProtocolsWithStats();
 * protocols.forEach(p => {
 *   console.log(`Protocol ${p.protocolParamsId}: ${p.tokenCount} tokens`);
 * });
 * ```
 */
export async function getProtocolsWithStats(): Promise<ProtocolWithStats[]> {
  return apiGet<ProtocolWithStats[]>('/registry/protocols');
}

/**
 * Check if the protocol is ready (bootstrap params and blueprint available).
 *
 * @returns Promise resolving to health status object
 *
 * @example
 * ```typescript
 * const health = await checkProtocolHealth();
 * if (health.isReady) {
 *   console.log('Protocol ready with', health.validatorCount, 'validators');
 * }
 * ```
 */
export async function checkProtocolHealth(): Promise<{
  isReady: boolean;
  hasBlueprint: boolean;
  hasBootstrap: boolean;
  validatorCount: number;
  error?: string;
}> {
  let hasBlueprint = false;
  let hasBootstrap = false;
  let validatorCount = 0;
  let error: string | undefined;

  try {
    const blueprint = await getProtocolBlueprint();
    hasBlueprint = true;
    validatorCount = blueprint.validators?.length || 0;
  } catch (e) {
    error = e instanceof Error ? e.message : 'Failed to load blueprint';
  }

  try {
    await getProtocolBootstrap();
    hasBootstrap = true;
  } catch (e) {
    if (!error) {
      error = e instanceof Error ? e.message : 'Failed to load bootstrap params';
    }
  }

  return {
    isReady: hasBlueprint && hasBootstrap,
    hasBlueprint,
    hasBootstrap,
    validatorCount,
    error,
  };
}
