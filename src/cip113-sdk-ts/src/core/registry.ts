/**
 * Registry node lookup and reference input index computation.
 *
 * Uses Evolution SDK types directly — no adapter abstraction.
 */

import type { UTxO as EvoUTxO } from "@evolution-sdk/evolution";
import type { Address, PolicyId, TxInput } from "../types.js";
import {
  extractConstrBytesField,
  getInlineDatum,
  utxoTxHash,
  utxoOutputIndex,
} from "./evo-utils.js";

// ---------------------------------------------------------------------------
// Transaction input sorting (matches Cardano ledger canonical order)
// ---------------------------------------------------------------------------

/**
 * Sort transaction inputs lexicographically by (txHash, outputIndex).
 * This matches the Cardano ledger's canonical ordering.
 */
export function sortTxInputs<T extends TxInput>(inputs: T[]): T[] {
  return [...inputs].sort((a, b) => {
    const hashCmp = a.txHash.localeCompare(b.txHash);
    if (hashCmp !== 0) return hashCmp;
    return a.outputIndex - b.outputIndex;
  });
}

/**
 * Find the index of a TxInput in a sorted list of reference inputs.
 */
export function findRefInputIndex(
  sortedRefInputs: TxInput[],
  target: TxInput
): number {
  const idx = sortedRefInputs.findIndex(
    (ri) => ri.txHash === target.txHash && ri.outputIndex === target.outputIndex
  );
  if (idx === -1) {
    throw new Error(
      `Reference input ${target.txHash}#${target.outputIndex} not found in sorted list`
    );
  }
  return idx;
}

// ---------------------------------------------------------------------------
// Registry node queries
// ---------------------------------------------------------------------------

/**
 * Find the registry node UTxO for a given token policy ID.
 * Searches the provided UTxOs for a node whose key matches the policy.
 */
export function findRegistryNode(
  utxos: EvoUTxO.UTxO[],
  tokenPolicyId: PolicyId
): EvoUTxO.UTxO | undefined {
  return utxos.find((utxo) => {
    const datum = getInlineDatum(utxo);
    if (!datum) return false;
    return extractConstrBytesField(datum, 0) === tokenPolicyId;
  });
}

/**
 * Find the covering node for a new token insertion.
 * The covering node satisfies: node.key < tokenPolicyId < node.next
 */
export function findCoveringNode(
  utxos: EvoUTxO.UTxO[],
  tokenPolicyId: PolicyId
): EvoUTxO.UTxO | undefined {
  return utxos.find((utxo) => {
    const datum = getInlineDatum(utxo);
    if (!datum) return false;
    const key = extractConstrBytesField(datum, 0);
    const next = extractConstrBytesField(datum, 1);
    if (key === undefined || next === undefined) return false;
    return key < tokenPolicyId && tokenPolicyId < next;
  });
}

/**
 * Convert a UTxO to a TxInput for sorting purposes.
 */
export function utxoToTxInput(utxo: EvoUTxO.UTxO): TxInput {
  return {
    txHash: utxoTxHash(utxo),
    outputIndex: utxoOutputIndex(utxo),
  };
}
