/**
 * Utilities for parameterizing Plutus scripts on the client side
 * Mirrors the Java AikenScriptUtil functionality using MeshSDK
 */

import type { PlutusScript } from '@meshsdk/core';
import {
  resolveScriptHash as meshResolveScriptHash,
  serializeRewardAddress,
  applyParamsToScript
} from '@meshsdk/core';

/**
 * Apply parameters to an Aiken script
 *
 * @param params - Array of parameters to apply
 * @param compiledCode - The compiled script code (cbor hex)
 * @returns Parameterized script cbor hex
 */
export function applyParamsToAikenScript(
  params: any[],
  compiledCode: string
): string {
  console.log('compiledCode: ' + compiledCode)
  console.log('params: ' + JSON.stringify(params))
  return applyParamsToScript(compiledCode, params);
}

/**
 * Create a PlutusScript from compiled code
 *
 * @param compiledCode - The compiled script code (cbor hex)
 * @param version - Plutus version (default: 'V3')
 * @returns PlutusScript object
 */
export function createPlutusScript(
  compiledCode: string,
  version: 'V1' | 'V2' | 'V3' = 'V3'
): PlutusScript {
  return {
    code: compiledCode,
    version: version,
  };
}

/**
 * Get script hash from PlutusScript
 * Uses MeshSDK's resolveScriptHash
 */
export function getScriptHash(script: PlutusScript): string {
  return meshResolveScriptHash(script.code, script.version);
}

/**
 * Decode hex to bytes
 */
export function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
}

/**
 * Encode bytes to hex
 */
export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Resolve reward address (stake address) from PlutusScript
 *
 * @param scriptCode - The compiled script code (cbor hex)
 * @param version - Plutus version
 * @returns Reward address (stake address)
 */
export function resolveRewardAddress(scriptCode: string, version: 'V1' | 'V2' | 'V3'): string {
  // First get the script hash
  const scriptHash = meshResolveScriptHash(scriptCode, version);
  // Then serialize it to a reward address (stake address)
  // isScriptHash = true, networkId = 0 (testnet)
  // TODO: Make network configurable
  return serializeRewardAddress(scriptHash, true, 0);
}
