/**
 * Transaction utilities — witness merging for CIP-103 stake registration flows.
 *
 * Previously contained a manual CBOR-level workaround for
 * https://github.com/IntersectMBO/evolution-sdk/issues/232
 * Fixed in @evolution-sdk/evolution 0.4.0 — now delegates to the SDK.
 */

import { Transaction } from "@evolution-sdk/evolution";

/**
 * Assemble a signed transaction from an unsigned tx CBOR hex and a
 * CIP-30 witness set CBOR hex. Merges vkey witnesses into the transaction.
 *
 * This function will likely be removed once CIP-103 is fully implemented.
 */
export function assembleSignedTx(unsignedTxHex: string, witnessSetHex: string): string {
  return Transaction.addVKeyWitnessesHex(unsignedTxHex, witnessSetHex);
}
