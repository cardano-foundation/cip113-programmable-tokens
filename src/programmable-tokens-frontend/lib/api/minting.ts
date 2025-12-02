/**
 * Token Minting API Module
 *
 * This module provides functions for minting programmable tokens via the
 * CIP-0113 backend API. It handles the conversion between user-facing form
 * data and the API request format.
 *
 * ## Workflow
 *
 * 1. User fills out the mint form (MintFormData)
 * 2. prepareMintRequest() converts to API format (MintTokenRequest)
 * 3. mintToken() sends request to backend
 * 4. Backend returns unsigned transaction CBOR
 * 5. Frontend uses Mesh SDK to sign and submit
 *
 * ## Hex Encoding
 *
 * Cardano asset names are raw bytes, but JSON doesn't support binary data.
 * We use hex encoding to safely transfer asset names:
 * - `stringToHex()` converts human-readable names to hex for API requests
 * - `hexToString()` converts hex back to human-readable for display
 *
 * @module lib/api/minting
 */

import { MintTokenRequest, MintTokenResponse, MintFormData } from '@/types/api';
import { apiPost } from './client';

/**
 * Convert a string to hexadecimal encoding.
 *
 * Uses the browser's TextEncoder API for UTF-8 encoding, then converts
 * each byte to a two-character hex string.
 *
 * @param str - The string to encode
 * @returns Hexadecimal string (lowercase, no prefix)
 *
 * @example
 * ```typescript
 * stringToHex("MyToken")  // Returns "4d79546f6b656e"
 * stringToHex("€")        // Returns "e282ac" (3 bytes for euro sign)
 * ```
 */
export function stringToHex(str: string): string {
  const encoder = new TextEncoder();
  const encoded = encoder.encode(str);
  return Array.from(encoded).map(b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Convert a hexadecimal string back to a regular string.
 *
 * Parses hex byte pairs and decodes them as UTF-8.
 *
 * @param hex - Hexadecimal string (with or without 0x prefix)
 * @returns Decoded string
 *
 * @example
 * ```typescript
 * hexToString("4d79546f6b656e")  // Returns "MyToken"
 * hexToString("0x4d79546f6b656e") // Also returns "MyToken"
 * ```
 */
export function hexToString(hex: string): string {
  const bytes = new Uint8Array(hex.match(/.{1,2}/g)?.map(byte => parseInt(byte, 16)) || []);
  const decoder = new TextDecoder();
  return decoder.decode(bytes);
}

/**
 * Mint tokens via the backend API.
 *
 * Sends a mint request to the backend and returns the unsigned transaction
 * CBOR hex. The caller is responsible for signing and submitting.
 *
 * @param request - The mint token request parameters
 * @returns Promise resolving to the unsigned transaction CBOR hex
 * @throws {ApiException} If the API request fails
 *
 * @example
 * ```typescript
 * const unsignedTx = await mintToken({
 *   issuerBaseAddress: wallet.address,
 *   substandardName: "dummy",
 *   substandardIssueContractName: "issuance_logic",
 *   assetName: stringToHex("MyToken"),
 *   quantity: "1000"
 * });
 * const signedTx = await wallet.signTx(unsignedTx);
 * const txHash = await wallet.submitTx(signedTx);
 * ```
 */
export async function mintToken(request: MintTokenRequest): Promise<MintTokenResponse> {
  // Ensure assetName is hex encoded (strip 0x prefix if present)
  const hexEncodedRequest = {
    ...request,
    assetName: request.assetName.startsWith('0x')
      ? request.assetName.slice(2)
      : request.assetName,
  };

  return apiPost<MintTokenRequest, MintTokenResponse>(
    '/issue-token/mint',
    hexEncodedRequest,
    { timeout: 60000 } // 60 seconds for minting transaction (includes on-chain lookups)
  );
}

/**
 * Prepare a mint request from form data.
 *
 * Converts the user-friendly form data to the API request format:
 * - Hex encodes the token name
 * - Maps form field names to API field names
 * - Handles optional recipient address
 *
 * @param formData - The mint form data from the UI
 * @param issuerAddress - The connected wallet's address
 * @returns MintTokenRequest ready for the API
 *
 * @example
 * ```typescript
 * const formData: MintFormData = {
 *   tokenName: "MyToken",
 *   quantity: "1000",
 *   substandardId: "dummy",
 *   validatorTitle: "issuance_logic"
 * };
 *
 * const request = prepareMintRequest(formData, wallet.address);
 * // request.assetName is now "4d79546f6b656e" (hex encoded)
 * ```
 */
export function prepareMintRequest(
  formData: MintFormData,
  issuerAddress: string
): MintTokenRequest {
  return {
    issuerBaseAddress: issuerAddress,
    substandardName: formData.substandardId,
    substandardIssueContractName: formData.validatorTitle,
    recipientAddress: formData.recipientAddress || undefined,
    assetName: stringToHex(formData.tokenName),
    quantity: formData.quantity,
  };
}
