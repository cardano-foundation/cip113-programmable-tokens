/**
 * Address utilities using Evolution SDK.
 *
 * This is the only other file (besides the adapter) that imports Evolution SDK,
 * specifically for address format conversion.
 */

import { Address as EvoAddress } from "@evolution-sdk/evolution";

/**
 * Convert a hex-encoded Cardano address to bech32.
 * If already bech32, returns as-is.
 *
 * CIP-30 wallets return hex-encoded addresses — this converts them
 * to the human-readable bech32 format (addr_test1..., addr1..., stake_test1...).
 */
export function addressHexToBech32(hexOrBech32: string): string {
  // Already bech32?
  if (hexOrBech32.startsWith("addr") || hexOrBech32.startsWith("stake")) {
    return hexOrBech32;
  }

  try {
    const addr = EvoAddress.fromHex(hexOrBech32);
    return EvoAddress.toBech32(addr);
  } catch {
    // If Evolution SDK can't parse it, return as-is
    return hexOrBech32;
  }
}
