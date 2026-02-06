import { deserializeAddress } from '@meshsdk/core';

/**
 * Extract the payment key hash from a Cardano address
 * @param address Bech32 encoded Cardano address
 * @returns Hex-encoded payment key hash (56 characters)
 * @throws Error if payment key hash cannot be extracted
 */
export function getPaymentKeyHash(address: string): string {
  const { pubKeyHash } = deserializeAddress(address);
  if (!pubKeyHash) {
    throw new Error('Could not extract payment key hash from address');
  }
  return pubKeyHash;
}
