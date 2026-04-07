/**
 * Redeemer builders for CIP-113 validators.
 *
 * Matches the Aiken types in lib/types.ak:
 *   SmartTokenMintingAction { minting_logic_cred, minting_registry_proof }
 *   MintingRegistryProof = RefInput { index } | OutputIndex { index }
 *   ProgrammableLogicGlobalRedeemer = TransferAct { proofs } | ThirdPartyAct { ... }
 *   RegistryRedeemer = RegistryInit | RegistryInsert { key, hashed_param }
 */

import type { HexString, ScriptHash } from "../types.js";
import { Data } from "./datums.js";

// ---------------------------------------------------------------------------
// SmartTokenMintingAction (issuance_mint redeemer)
// ---------------------------------------------------------------------------

/**
 * Build a SmartTokenMintingAction redeemer for first mint (OutputIndex).
 * @param mintingLogicHash - Script hash of the minting logic substandard
 * @param registryOutputIndex - Index of the registry node in tx outputs
 */
export function issuanceRedeemerFirstMint(
  mintingLogicHash: ScriptHash,
  registryOutputIndex: number
) {
  return Data.constr(0, [
    Data.scriptCredential(mintingLogicHash),
    Data.constr(1, [Data.integer(registryOutputIndex)]), // OutputIndex { index }
  ]);
}

/**
 * Build a SmartTokenMintingAction redeemer for subsequent mint/burn (RefInput).
 * @param mintingLogicHash - Script hash of the minting logic substandard
 * @param registryRefInputIndex - Index of the registry node in sorted reference inputs
 */
export function issuanceRedeemerRefInput(
  mintingLogicHash: ScriptHash,
  registryRefInputIndex: number
) {
  return Data.constr(0, [
    Data.scriptCredential(mintingLogicHash),
    Data.constr(0, [Data.integer(registryRefInputIndex)]), // RefInput { index }
  ]);
}

// ---------------------------------------------------------------------------
// ProgrammableLogicGlobalRedeemer
// ---------------------------------------------------------------------------

export interface RegistryProof {
  type: "exists" | "not-exists";
  nodeIdx: number;
}

/**
 * Build a TransferAct redeemer for PLGlobal.
 * @param proofs - One proof per token policy in the transaction
 */
export function transferActRedeemer(proofs: RegistryProof[]) {
  return Data.constr(0, [
    Data.list(
      proofs.map((p) =>
        p.type === "exists"
          ? Data.constr(0, [Data.integer(p.nodeIdx)]) // TokenExists { node_idx }
          : Data.constr(1, [Data.integer(p.nodeIdx)]) // TokenDoesNotExist { node_idx }
      )
    ),
  ]);
}

/**
 * Build a ThirdPartyAct redeemer for PLGlobal (seize, wipe).
 * @param registryNodeIdx - Index of registry node in sorted reference inputs
 * @param outputsStartIdx - Starting index in outputs where processed outputs begin
 */
export function thirdPartyActRedeemer(
  registryNodeIdx: number,
  outputsStartIdx: number
) {
  return Data.constr(1, [
    Data.integer(registryNodeIdx),
    Data.integer(outputsStartIdx),
  ]);
}

// ---------------------------------------------------------------------------
// RegistryRedeemer (registry_mint)
// ---------------------------------------------------------------------------

/** RegistryInit redeemer */
export function registryInitRedeemer() {
  return Data.constr(0, []);
}

/**
 * RegistryInsert redeemer
 * @param key - The token's policy ID (issuance script hash)
 * @param hashedParam - The hashed minting logic parameter
 */
export function registryInsertRedeemer(key: HexString, hashedParam: HexString) {
  return Data.constr(1, [Data.bytes(key), Data.bytes(hashedParam)]);
}

// ---------------------------------------------------------------------------
// Blacklist redeemers
// ---------------------------------------------------------------------------

/** Blacklist init (constructor 0) */
export function blacklistInitRedeemer() {
  return Data.constr(0, []);
}

/** Blacklist add (constructor 1) — insert credential into blacklist */
export function blacklistAddRedeemer(stakingPkh: HexString) {
  return Data.constr(1, [Data.bytes(stakingPkh)]);
}

/** Blacklist remove (constructor 2) — remove credential from blacklist */
export function blacklistRemoveRedeemer(stakingPkh: HexString) {
  return Data.constr(2, [Data.bytes(stakingPkh)]);
}

// ---------------------------------------------------------------------------
// Generic redeemers
// ---------------------------------------------------------------------------

/** Simple spend redeemer: Constr(0, []) */
export function spendRedeemer() {
  return Data.void();
}
