/**
 * CIP-0113 API Client Module
 *
 * This module provides a unified API for communicating with the CIP-0113
 * backend services. It re-exports all API-related functionality from
 * individual modules for convenient importing.
 *
 * ## Available APIs
 *
 * ### Client (./client.ts)
 * - `apiGet<T>` - Typed GET requests
 * - `apiPost<T, R>` - Typed POST requests
 * - `getApiBaseUrl` - Get configured API URL
 *
 * ### Substandards (./substandards.ts)
 * - `getSubstandards` - Fetch available substandard validators
 *
 * ### Minting (./minting.ts)
 * - `mintProgrammableToken` - Create unsigned mint transaction
 * - `registerToken` - Register token in protocol registry
 * - `prepareMintRequest` - Build mint request from form data
 * - `stringToHex` - Convert string to hex for asset names
 *
 * ## Usage
 *
 * ```typescript
 * // Import all APIs
 * import { getSubstandards, mintProgrammableToken } from '@/lib/api';
 *
 * // Fetch substandards
 * const substandards = await getSubstandards();
 *
 * // Mint a token
 * const unsignedTx = await mintProgrammableToken(request);
 * ```
 *
 * @module lib/api
 */

// Re-export client utilities (fetch wrappers, error handling)
export * from './client';

// Re-export substandard API functions
export * from './substandards';

// Re-export minting API functions
export * from './minting';

// Re-export protocol API functions
export * from './protocol';
