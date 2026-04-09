/**
 * Transaction utilities — manual CBOR-level witness merging.
 *
 * Workaround for https://github.com/IntersectMBO/evolution-sdk/issues/232
 * The Evolution SDK's `addVKeyWitnessesBytes` fails on Conway-era transactions
 * containing certificates (tag 258). This implementation splices witnesses at
 * the raw CBOR byte level, never decoding the transaction body.
 *
 * A Cardano transaction is a 4-element CBOR array:
 *   [body, witnessSet, isValid, auxiliaryData]
 *
 * The witness set is a CBOR map where key 0 = vkey witnesses (array).
 * CIP-30 signTx() returns only the witness set, not the full tx.
 */

import { CBOR, Bytes } from "@evolution-sdk/evolution";

type CborMap = Map<CBOR.CBOR, CBOR.CBOR>;

// CBOR witness set key for vkey witnesses — always bigint (CBOR unsigned int)
const VKEY_WITNESSES_KEY = 0n;

// ---------------------------------------------------------------------------
// CBOR helpers
// ---------------------------------------------------------------------------

/** Decode a CBOR item at `offset` and return the end offset (skips the item). */
function skipCborItem(data: Uint8Array, offset: number): number {
  const { newOffset } = CBOR.decodeItemWithOffset(data, offset);
  return newOffset;
}

/**
 * Build a new CBOR Map with keys in ascending bigint order.
 * Cardano requires witness set map keys in canonical (ascending) order.
 */
function buildSortedWitnessMap(ws: CborMap): ReadonlyMap<CBOR.CBOR, CBOR.CBOR> {
  const entries = [...ws.entries()].sort((a, b) => {
    const ka = typeof a[0] === "bigint" ? a[0] : BigInt(a[0] as number);
    const kb = typeof b[0] === "bigint" ? b[0] : BigInt(b[0] as number);
    return ka < kb ? -1 : ka > kb ? 1 : 0;
  });
  return new Map(entries);
}

// ---------------------------------------------------------------------------
// Core: assemble signed transaction
// ---------------------------------------------------------------------------

/**
 * Assemble a signed transaction from an unsigned tx CBOR and a witness set CBOR.
 *
 * This performs raw CBOR byte-level splicing:
 * 1. Locate the witness set region in the transaction bytes
 * 2. Decode only the witness set (not the body — avoids the cert tag 258 bug)
 * 3. Extract vkey witnesses from the CIP-30 witness set
 * 4. Merge vkey witnesses into the transaction's witness set
 * 5. Reconstruct: original body bytes + new witness set + original tail
 */
export function assembleSignedTx(unsignedTxHex: string, witnessSetHex: string): string {
  const txBytes = Bytes.fromHex(unsignedTxHex);
  const walletWsBytes = Bytes.fromHex(witnessSetHex);

  // --- Parse CIP-30 witness set to extract vkey witnesses ---
  // CBOR integers decode as bigint in Evolution SDK, so map keys are 0n not 0
  const walletWs = CBOR.fromCBORBytes(walletWsBytes) as CborMap;
  const walletVkeys = walletWs.get(VKEY_WITNESSES_KEY);
  if (!walletVkeys || !Array.isArray(walletVkeys) || walletVkeys.length === 0) {
    // No vkey witnesses to add — return as-is
    return unsignedTxHex;
  }

  // --- Locate regions in the transaction CBOR ---
  // Skip outer array header (0x84 for array(4))
  const arrHdrEnd = (txBytes[0] & 0x1f) < 24 ? 1 : 2;

  // Skip body item → gives us bodyEnd = start of witness set
  const bodyEnd = skipCborItem(txBytes, arrHdrEnd);

  // Skip witness set item → gives us witnessEnd = start of isValid
  const witnessEnd = skipCborItem(txBytes, bodyEnd);

  // --- Decode only the witness set ---
  const existingWsBytes = txBytes.subarray(bodyEnd, witnessEnd);
  const existingWs = CBOR.fromCBORBytes(existingWsBytes) as CborMap;

  // --- Merge vkey witnesses ---
  const existingVkeys = (existingWs.get(VKEY_WITNESSES_KEY) ?? []) as Array<CBOR.CBOR>;

  // Deduplicate by public key bytes (first element of each [pubkey, signature] pair)
  const seen = new Set<string>();
  const merged: Array<CBOR.CBOR> = [];
  for (const vk of [...existingVkeys, ...(walletVkeys as Array<CBOR.CBOR>)]) {
    const pair = vk as [Uint8Array, Uint8Array];
    const pubkeyHex = Bytes.toHex(pair[0]);
    if (!seen.has(pubkeyHex)) {
      seen.add(pubkeyHex);
      merged.push(vk);
    }
  }

  // Update the witness set map with merged vkey witnesses (bigint key)
  existingWs.set(VKEY_WITNESSES_KEY, merged);

  // --- Re-encode the witness set with keys in canonical ascending order ---
  const sortedWs = buildSortedWitnessMap(existingWs);
  const newWsBytes = CBOR.toCBORBytes(sortedWs);

  // --- Reconstruct the transaction ---
  // [original header + body] + [new witness set] + [original isValid + auxData]
  const prefix = txBytes.subarray(0, bodyEnd);       // array header + body
  const suffix = txBytes.subarray(witnessEnd);         // isValid + auxiliaryData

  const result = new Uint8Array(prefix.length + newWsBytes.length + suffix.length);
  result.set(prefix, 0);
  result.set(newWsBytes, prefix.length);
  result.set(suffix, prefix.length + newWsBytes.length);

  return Bytes.toHex(result);
}
