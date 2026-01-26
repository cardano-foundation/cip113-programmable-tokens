/**
 * Token Minting API
 */

import {
  MintTokenRequest,
  MintTokenResponse,
  MintFormData,
  LegacyMintTokenRequest,
  LegacyMintFormData
} from '@/types/api';
import { apiPost } from './client';

/**
 * Convert string to hex encoding
 * Required for assetName in minting requests
 */
export function stringToHex(str: string): string {
  return Buffer.from(str, 'utf8').toString('hex');
}

/**
 * Convert hex to string
 */
export function hexToString(hex: string): string {
  return Buffer.from(hex, 'hex').toString('utf8');
}

/**
 * Admin mint tokens via backend API (mint to existing registered token)
 * Returns unsigned transaction CBOR hex
 */
export async function mintToken(
  request: MintTokenRequest,
  protocolTxHash?: string
): Promise<MintTokenResponse> {
  // Ensure assetName is hex encoded
  const hexEncodedRequest = {
    ...request,
    assetName: request.assetName.startsWith('0x')
      ? request.assetName.slice(2)
      : request.assetName,
  };

  const endpoint = protocolTxHash
    ? `/issue-token/mint?protocolTxHash=${protocolTxHash}`
    : '/issue-token/mint';

  return apiPost<MintTokenRequest, MintTokenResponse>(
    endpoint,
    hexEncodedRequest,
    { timeout: 60000 } // 60 seconds for minting transaction
  );
}

/**
 * Prepare admin mint request from form data
 */
export function prepareMintRequest(
  formData: MintFormData,
  feePayerAddress: string
): MintTokenRequest {
  return {
    feePayerAddress,
    tokenPolicyId: formData.policyId,
    recipientAddress: formData.recipientAddress,
    assetName: stringToHex(formData.tokenName),
    quantity: formData.quantity,
  };
}

// ============================================================================
// Legacy Minting (for /mint page - deprecated, use /register instead)
// ============================================================================

/**
 * @deprecated Use registration flow instead
 */
export async function legacyMintToken(
  request: LegacyMintTokenRequest,
  protocolTxHash?: string
): Promise<MintTokenResponse> {
  const hexEncodedRequest = {
    ...request,
    assetName: request.assetName.startsWith('0x')
      ? request.assetName.slice(2)
      : request.assetName,
  };

  const endpoint = protocolTxHash
    ? `/issue-token/mint?protocolTxHash=${protocolTxHash}`
    : '/issue-token/mint';

  return apiPost<LegacyMintTokenRequest, MintTokenResponse>(
    endpoint,
    hexEncodedRequest,
    { timeout: 60000 }
  );
}

/**
 * @deprecated Use registration flow instead
 */
export function prepareLegacyMintRequest(
  formData: LegacyMintFormData,
  issuerAddress: string
): LegacyMintTokenRequest {
  return {
    issuerBaseAddress: issuerAddress,
    substandardName: formData.substandardId,
    substandardIssueContractName: formData.validatorTitle,
    recipientAddress: formData.recipientAddress || undefined,
    assetName: stringToHex(formData.tokenName),
    quantity: formData.quantity,
  };
}
