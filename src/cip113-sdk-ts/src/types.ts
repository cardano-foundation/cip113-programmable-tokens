/**
 * Core types for the CIP-113 SDK.
 *
 * String aliases (HexString, Address, etc.) kept for readability.
 * Evolution SDK types used directly where possible.
 */

import type {
  Data as EvoData,
  UTxO as EvoUTxO,
  Script as EvoScript,
  Assets as EvoAssets,
} from "@evolution-sdk/evolution";

// ---------------------------------------------------------------------------
// Primitives (string aliases for readability)
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
// Re-exports from Evolution SDK
// ---------------------------------------------------------------------------

/** PlutusData — Evolution SDK's Data.Data type */
export type PlutusData = EvoData.Data;

/** UTxO — Evolution SDK's UTxO type */
export type UTxO = EvoUTxO.UTxO;

/** Script — Evolution SDK's Script type */
export type Script = EvoScript.Script;

/** Assets — Evolution SDK's Assets type */
export type Assets = EvoAssets.Assets;

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

export interface TxInput {
  txHash: TxHash;
  outputIndex: number;
}

/** Script metadata: compiled code + hash for parameterization and attachment */
export interface PlutusScript {
  type: "PlutusV3";
  compiledCode: HexString;
  hash: ScriptHash;
}

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
