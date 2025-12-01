/**
 * Token Minting API
 */

import { MintTokenRequest, MintTokenResponse, MintFormData } from '@/types/api';
import { apiPost } from './client';

/**
 * Convert string to hex encoding
 * Required for assetName in minting requests
 */
export function stringToHex(str: string): string {
  const encoder = new TextEncoder();
  const encoded = encoder.encode(str);
  return Array.from(encoded).map(b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Convert hex to string
 */
export function hexToString(hex: string): string {
  const bytes = new Uint8Array(hex.match(/.{1,2}/g)?.map(byte => parseInt(byte, 16)) || []);
  const decoder = new TextDecoder();
  return decoder.decode(bytes);
}

/**
 * Mint tokens via backend API
 * Returns unsigned transaction CBOR hex
 */
export async function mintToken(request: MintTokenRequest): Promise<MintTokenResponse> {
  // Ensure assetName is hex encoded
  const hexEncodedRequest = {
    ...request,
    assetName: request.assetName.startsWith('0x')
      ? request.assetName.slice(2)
      : request.assetName,
  };

  return apiPost<MintTokenRequest, MintTokenResponse>(
    '/issue-token/mint',
    hexEncodedRequest,
    { timeout: 60000 } // 60 seconds for minting transaction
  );
}

/**
 * Prepare mint request from form data
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
