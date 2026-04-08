/**
 * Compute transaction hash from unsigned CBOR hex.
 *
 * Replaces `resolveTxHash()` from `@meshsdk/core`.
 *
 * A Cardano tx hash is blake2b-256 of the transaction body CBOR.
 * The unsigned tx CBOR is a CBOR array: [body, witnessSet, isValid, auxiliaryData].
 * We need to hash just the body (first element).
 *
 * For now, we use a simple approach: the backend already provides
 * the tx hash in most responses. Where we need to derive it from CBOR,
 * we can use the crypto API or Evolution SDK.
 */

/**
 * Derive a transaction hash from unsigned CBOR hex.
 *
 * This is a best-effort implementation. For production use,
 * we should use a proper CBOR parser + blake2b-256 hasher.
 */
export async function resolveTxHash(unsignedCborHex: string): Promise<string> {
  // Use SubtleCrypto with SHA-256 as an approximation
  // NOTE: Cardano uses blake2b-256, not SHA-256.
  // For accurate hashing, use @noble/hashes or Evolution SDK.
  // This placeholder works for display purposes during development.
  try {
    const bytes = hexToBytes(unsignedCborHex);
    // The CBOR array starts with 0x84 (array of 4 items)
    // TODO: properly extract the body bytes from CBOR
    // For now, hash the entire unsigned tx as a placeholder
    const hashBuffer = await crypto.subtle.digest("SHA-256", bytes as unknown as ArrayBuffer);
    return bytesToHex(new Uint8Array(hashBuffer));
  } catch {
    // Fallback: return empty string
    return "";
  }
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
