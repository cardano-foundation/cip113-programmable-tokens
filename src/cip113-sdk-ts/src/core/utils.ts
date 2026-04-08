/**
 * Utility functions.
 */

/** Convert a UTF-8 string to hex */
export function stringToHex(str: string): string {
  return Buffer.from(str, "utf-8").toString("hex");
}

/** Convert hex to UTF-8 string */
export function hexToString(hex: string): string {
  return Buffer.from(hex, "hex").toString("utf-8");
}

/** Protocol params NFT token name (hex-encoded "ProtocolParams") */
export const PROTOCOL_PARAMS_TOKEN_NAME = stringToHex("ProtocolParams");

/** Issuance CBOR hex NFT token name (hex-encoded "IssuanceCborHex") */
export const ISSUANCE_CBOR_HEX_TOKEN_NAME = stringToHex("IssuanceCborHex");

/** Origin node token name (empty byte string) */
export const ORIGIN_NODE_TOKEN_NAME = "";

/** Max next pointer for linked list sentinel (30 bytes, matches Aiken #"ff"*30) */
export const MAX_NEXT = "ff".repeat(30);

/**
 * Convert a hex-encoded Cardano address to bech32.
 * Uses Evolution SDK's Address module under the hood.
 *
 * CIP-30 wallets return hex addresses — this converts them for display and API use.
 */
export { addressHexToBech32 } from "../provider/address-utils.js";
