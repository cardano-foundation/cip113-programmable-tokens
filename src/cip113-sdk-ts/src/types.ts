/**
 * Core types for the CIP-113 SDK.
 */

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

/** Hex-encoded byte string */
export type HexString = string;

/** A Cardano policy ID (28-byte blake2b-224 hash, hex-encoded) */
export type PolicyId = HexString;

/** A Cardano script hash (same format as PolicyId) */
export type ScriptHash = HexString;

/** Bech32-encoded Cardano address */
export type Address = string;

/** Transaction hash (32-byte blake2b-256 hash, hex-encoded) */
export type TxHash = HexString;

// ---------------------------------------------------------------------------
// Transaction References
// ---------------------------------------------------------------------------

export interface TxInput {
  txHash: TxHash;
  outputIndex: number;
}

export interface UTxO {
  txHash: TxHash;
  outputIndex: number;
  address: Address;
  value: Value;
  datum?: PlutusData;
  datumHash?: HexString;
  referenceScript?: PlutusScript;
}

export interface Value {
  lovelace: bigint;
  assets?: Map<string, bigint>; // unit (policyId + assetName) -> quantity
}

// ---------------------------------------------------------------------------
// Scripts
// ---------------------------------------------------------------------------

export interface PlutusScript {
  type: "PlutusV3";
  compiledCode: HexString;
  hash: ScriptHash;
}

export type PlutusData = unknown; // Adapter-specific, opaque to core logic

// ---------------------------------------------------------------------------
// Blueprint (CIP-57)
// ---------------------------------------------------------------------------

export interface BlueprintValidator {
  title: string;
  compiledCode: HexString;
  hash: HexString;
  parameters?: BlueprintParameter[];
}

export interface BlueprintParameter {
  title: string;
  schema: { $ref?: string } & Record<string, unknown>;
}

export interface PlutusBlueprint {
  preamble: {
    title: string;
    version: string;
  };
  validators: BlueprintValidator[];
  definitions?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Deployment Parameters
// ---------------------------------------------------------------------------

/**
 * Parameters from a deployed CIP-113 protocol instance.
 * Produced by the bootstrap transaction, consumed by all subsequent operations.
 */
export interface DeploymentParams {
  /** Bootstrap transaction hash */
  txHash: TxHash;

  protocolParams: {
    txInput: TxInput;
    policyId: PolicyId;
    alwaysFailScriptHash: ScriptHash;
  };

  programmableLogicGlobal: {
    policyId: PolicyId;
    scriptHash: ScriptHash;
  };

  programmableLogicBase: {
    scriptHash: ScriptHash;
  };

  issuance: {
    txInput: TxInput;
    policyId: PolicyId;
    alwaysFailScriptHash: ScriptHash;
  };

  directoryMint: {
    txInput: TxInput;
    issuanceScriptHash: ScriptHash;
    scriptHash: ScriptHash;
  };

  directorySpend: {
    policyId: PolicyId;
    scriptHash: ScriptHash;
  };

  programmableBaseRefInput: TxInput;
  programmableGlobalRefInput: TxInput;
}

// ---------------------------------------------------------------------------
// Network
// ---------------------------------------------------------------------------

export type Network = "mainnet" | "preprod" | "preview";
