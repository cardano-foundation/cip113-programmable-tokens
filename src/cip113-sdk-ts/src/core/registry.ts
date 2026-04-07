/**
 * Registry node lookup and reference input index computation.
 */

import type { CardanoProvider } from "../provider/interface.js";
import type { Address, PolicyId, TxInput, UTxO } from "../types.js";

// ---------------------------------------------------------------------------
// Transaction input sorting (matches Cardano ledger canonical order)
// ---------------------------------------------------------------------------

/**
 * Sort transaction inputs lexicographically by (txHash, outputIndex).
 * This matches the Cardano ledger's canonical ordering used by
 * TransactionInputComparator in the Java code.
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
 * Parsed registry node from on-chain datum.
 */
export interface RegistryNode {
  key: string;
  next: string;
  transferLogicScript: string;
  thirdPartyTransferLogicScript: string;
  globalStateCs: string;
}

/**
 * Find the registry node UTxO for a given token policy ID.
 * Searches the registry spend address for a node whose key matches the policy.
 */
export async function findRegistryNode(
  provider: CardanoProvider,
  registrySpendAddress: Address,
  tokenPolicyId: PolicyId
): Promise<UTxO | undefined> {
  const utxos = await provider.getUtxos(registrySpendAddress);
  return utxos.find((utxo) => {
    // Parse the inline datum to check the key field
    // The key is the first field of Constr(0, [key, next, ...])
    const datum = utxo.datum;
    if (!datum) return false;
    return parseRegistryNodeKey(datum) === tokenPolicyId;
  });
}

/**
 * Find the covering node for a new token insertion.
 * The covering node satisfies: node.key < tokenPolicyId < node.next
 */
export async function findCoveringNode(
  provider: CardanoProvider,
  registrySpendAddress: Address,
  tokenPolicyId: PolicyId
): Promise<UTxO | undefined> {
  const utxos = await provider.getUtxos(registrySpendAddress);
  return utxos.find((utxo) => {
    const datum = utxo.datum;
    if (!datum) return false;
    const key = parseRegistryNodeKey(datum);
    const next = parseRegistryNodeNext(datum);
    if (key === undefined || next === undefined) return false;
    return key < tokenPolicyId && tokenPolicyId < next;
  });
}

// ---------------------------------------------------------------------------
// Datum parsing helpers (adapter-agnostic)
// ---------------------------------------------------------------------------

/**
 * Extract the "key" field from a RegistryNode datum.
 * Datum shape: Constr(0, [key: ByteArray, next: ByteArray, ...])
 */
function parseRegistryNodeKey(datum: unknown): string | undefined {
  return extractConstrField(datum, 0);
}

/**
 * Extract the "next" field from a RegistryNode datum.
 */
function parseRegistryNodeNext(datum: unknown): string | undefined {
  return extractConstrField(datum, 1);
}

/**
 * Extract a bytes field at a given index from a Constr datum.
 * This is adapter-agnostic: works with the { constr, fields } format
 * from our Data module.
 */
function extractConstrField(datum: unknown, fieldIndex: number): string | undefined {
  // Handle our Data format: { constr: 0, fields: [...] }
  if (
    typeof datum === "object" &&
    datum !== null &&
    "constr" in datum &&
    "fields" in datum
  ) {
    const d = datum as { constr: number; fields: unknown[] };
    const field = d.fields[fieldIndex];
    if (typeof field === "object" && field !== null && "bytes" in field) {
      return (field as { bytes: string }).bytes;
    }
  }
  return undefined;
}
