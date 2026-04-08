/**
 * Transaction utilities using Evolution SDK.
 *
 * Provides assembly of signed transactions from unsigned tx + witness set.
 */

import { Transaction } from "@evolution-sdk/evolution";

/**
 * Assemble a signed transaction from an unsigned tx CBOR and a witness set CBOR.
 *
 * CIP-30 `signTx()` returns the witness set, not the full signed tx.
 * This function merges them using Evolution SDK's `Transaction.addVKeyWitnessesHex`.
 *
 * @param unsignedTxHex - The unsigned transaction CBOR (hex)
 * @param witnessSetHex - The witness set returned by CIP-30 signTx (hex)
 * @returns The fully assembled signed transaction CBOR (hex)
 */
export function assembleSignedTx(unsignedTxHex: string, witnessSetHex: string): string {
  return Transaction.addVKeyWitnessesHex(unsignedTxHex, witnessSetHex);
}
