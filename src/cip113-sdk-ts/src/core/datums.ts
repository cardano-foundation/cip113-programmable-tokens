/**
 * PlutusData builders for CIP-113 types.
 *
 * These produce adapter-agnostic data structures that match
 * the on-chain Aiken types. The provider adapter converts them
 * to the concrete SDK's PlutusData format.
 *
 * Convention: Constr(0, ...) = first variant, Constr(1, ...) = second variant.
 * Credential: Constr(0, [hash]) = VerificationKey, Constr(1, [hash]) = Script.
 */

import type { HexString, TxInput, ScriptHash } from "../types.js";

// ---------------------------------------------------------------------------
// Generic PlutusData constructors (adapter-agnostic)
// ---------------------------------------------------------------------------

/**
 * PlutusData builder — produces plain JS objects that adapters convert
 * to their native format.
 */
export const Data = {
  /** Constructor with index and fields */
  constr(index: number, fields: unknown[]): { constr: number; fields: unknown[] } {
    return { constr: index, fields };
  },

  /** Byte array from hex string */
  bytes(hex: HexString): { bytes: HexString } {
    return { bytes: hex };
  },

  /** Integer */
  integer(n: number | bigint): { int: bigint } {
    return { int: BigInt(n) };
  },

  /** List */
  list(items: unknown[]): { list: unknown[] } {
    return { list: items };
  },

  /** Map */
  map(entries: [unknown, unknown][]): { map: [unknown, unknown][] } {
    return { map: entries };
  },

  // -- Cardano-specific helpers --

  /** OutputReference: Constr(0, [Constr(0, [txHash]), outputIndex]) */
  outputReference(ref: TxInput) {
    return Data.constr(0, [
      Data.bytes(ref.txHash),
      Data.integer(ref.outputIndex),
    ]);
  },

  /** Script credential: Constr(1, [scriptHash]) */
  scriptCredential(hash: ScriptHash) {
    return Data.constr(1, [Data.bytes(hash)]);
  },

  /** Verification key credential: Constr(0, [keyHash]) */
  keyCredential(hash: HexString) {
    return Data.constr(0, [Data.bytes(hash)]);
  },

  /** Void / unit: Constr(0, []) */
  void() {
    return Data.constr(0, []);
  },
};

// ---------------------------------------------------------------------------
// CIP-113 Domain Types
// ---------------------------------------------------------------------------

export interface RegistryNodeData {
  key: HexString;
  next: HexString;
  transferLogicScript: { type: "key" | "script"; hash: ScriptHash };
  thirdPartyTransferLogicScript: { type: "key" | "script"; hash: ScriptHash };
  globalStateCs: HexString;
}

/** Build a RegistryNode datum */
export function registryNodeDatum(node: RegistryNodeData) {
  const credToData = (cred: { type: "key" | "script"; hash: ScriptHash }) =>
    cred.type === "script"
      ? Data.scriptCredential(cred.hash)
      : Data.keyCredential(cred.hash);

  return Data.constr(0, [
    Data.bytes(node.key),
    Data.bytes(node.next),
    credToData(node.transferLogicScript),
    credToData(node.thirdPartyTransferLogicScript),
    Data.bytes(node.globalStateCs),
  ]);
}

/** Build a ProgrammableLogicGlobalParams datum */
export function protocolParamsDatum(
  registryNodeCs: ScriptHash,
  progLogicCred: ScriptHash
) {
  return Data.constr(0, [
    Data.bytes(registryNodeCs),
    Data.scriptCredential(progLogicCred),
  ]);
}

/** Build a BlacklistNode datum */
export function blacklistNodeDatum(key: HexString, next: HexString) {
  return Data.constr(0, [Data.bytes(key), Data.bytes(next)]);
}

/** Build an IssuanceCborHex datum */
export function issuanceCborHexDatum(prefix: HexString, postfix: HexString) {
  return Data.constr(0, [Data.bytes(prefix), Data.bytes(postfix)]);
}
