/**
 * Standard script parameterization.
 *
 * Replicates the parameterization chain from ProtocolScriptBuilderService.java.
 * Uses Evolution SDK directly for UPLC.applyParamsToScript and ScriptHash.
 *
 * Dependency graph:
 *
 *   always_fail(nonce) → hash
 *   protocol_params_mint(utxo_ref, always_fail_hash) → hash
 *   programmable_logic_global(protocol_params_hash) → hash
 *   programmable_logic_base(Script(plg_hash)) → hash
 *   issuance_cbor_hex_mint(utxo_ref, always_fail_hash) → hash
 *   registry_mint(utxo_ref, issuance_cbor_hex_hash) → hash
 *   registry_spend(protocol_params_hash) → hash
 *   issuance_mint(Script(plb_hash), registry_mint_hash, Script(minting_logic_hash)) → hash
 */

import { Data } from "@evolution-sdk/evolution";
import type {
  DeploymentParams,
  HexString,
  PlutusBlueprint,
  PlutusScript,
  ScriptHash,
  TxInput,
} from "../types.js";
import { getValidatorCode, STANDARD_VALIDATORS } from "./blueprint.js";
import {
  parameterizeScript,
  outputReference,
  scriptCredential,
} from "../core/evo-utils.js";

// ---------------------------------------------------------------------------
// Script builders
// ---------------------------------------------------------------------------

export interface StandardScripts {
  alwaysFail(nonce: HexString): PlutusScript;
  protocolParamsMint(utxoRef: TxInput, alwaysFailHash: ScriptHash): PlutusScript;
  programmableLogicGlobal(protocolParamsHash: ScriptHash): PlutusScript;
  programmableLogicBase(plgHash: ScriptHash): PlutusScript;
  issuanceCborHexMint(utxoRef: TxInput, alwaysFailHash: ScriptHash): PlutusScript;
  registryMint(utxoRef: TxInput, issuanceCborHexHash: ScriptHash): PlutusScript;
  registrySpend(protocolParamsHash: ScriptHash): PlutusScript;
  issuanceMint(plbHash: ScriptHash, registryMintHash: ScriptHash, mintingLogicHash: ScriptHash): PlutusScript;
}

/**
 * Create standard script builders from a blueprint.
 * Uses Evolution SDK directly for parameterization and hashing.
 */
export function createStandardScripts(
  blueprint: PlutusBlueprint,
): StandardScripts {
  function parameterize(validatorTitle: string, params: Data.Data[]): PlutusScript {
    const code = getValidatorCode(blueprint, validatorTitle);
    return parameterizeScript(code, params);
  }

  return {
    alwaysFail(nonce) {
      return parameterize(STANDARD_VALIDATORS.ALWAYS_FAIL, [
        Data.bytearray(nonce),
      ]);
    },

    protocolParamsMint(utxoRef, alwaysFailHash) {
      return parameterize(STANDARD_VALIDATORS.PROTOCOL_PARAMS_MINT, [
        outputReference(utxoRef),
        Data.bytearray(alwaysFailHash),
      ]);
    },

    programmableLogicGlobal(protocolParamsHash) {
      return parameterize(STANDARD_VALIDATORS.PROGRAMMABLE_LOGIC_GLOBAL, [
        Data.bytearray(protocolParamsHash),
      ]);
    },

    programmableLogicBase(plgHash) {
      return parameterize(STANDARD_VALIDATORS.PROGRAMMABLE_LOGIC_BASE, [
        scriptCredential(plgHash),
      ]);
    },

    issuanceCborHexMint(utxoRef, alwaysFailHash) {
      return parameterize(STANDARD_VALIDATORS.ISSUANCE_CBOR_HEX_MINT, [
        outputReference(utxoRef),
        Data.bytearray(alwaysFailHash),
      ]);
    },

    registryMint(utxoRef, issuanceCborHexHash) {
      return parameterize(STANDARD_VALIDATORS.REGISTRY_MINT, [
        outputReference(utxoRef),
        Data.bytearray(issuanceCborHexHash),
      ]);
    },

    registrySpend(protocolParamsHash) {
      return parameterize(STANDARD_VALIDATORS.REGISTRY_SPEND, [
        Data.bytearray(protocolParamsHash),
      ]);
    },

    issuanceMint(plbHash, registryMintHash, mintingLogicHash) {
      return parameterize(STANDARD_VALIDATORS.ISSUANCE_MINT, [
        scriptCredential(plbHash),
        Data.bytearray(registryMintHash),
        scriptCredential(mintingLogicHash),
      ]);
    },
  };
}

/**
 * Build resolved standard scripts from deployment params.
 *
 * IMPORTANT: Uses the known hashes from DeploymentParams (the source of truth)
 * rather than re-deriving them from the blueprint.
 */
export function buildDeploymentScripts(
  blueprint: PlutusBlueprint,
  deployment: DeploymentParams,
): ResolvedStandardScripts {
  const builders = createStandardScripts(blueprint);

  const protocolParamsMint = builders.protocolParamsMint(
    deployment.protocolParams.txInput,
    deployment.protocolParams.alwaysFailScriptHash
  );
  protocolParamsMint.hash = deployment.protocolParams.policyId;

  const programmableLogicGlobal = builders.programmableLogicGlobal(
    deployment.protocolParams.policyId
  );
  programmableLogicGlobal.hash = deployment.programmableLogicGlobal.scriptHash;

  const programmableLogicBase = builders.programmableLogicBase(
    deployment.programmableLogicGlobal.scriptHash
  );
  programmableLogicBase.hash = deployment.programmableLogicBase.scriptHash;

  const issuanceCborHexMint = builders.issuanceCborHexMint(
    deployment.issuance.txInput,
    deployment.issuance.alwaysFailScriptHash
  );
  issuanceCborHexMint.hash = deployment.issuance.policyId;

  const registryMint = builders.registryMint(
    deployment.directoryMint.txInput,
    deployment.issuance.policyId
  );
  registryMint.hash = deployment.directoryMint.scriptHash;

  const registrySpend = builders.registrySpend(
    deployment.protocolParams.policyId
  );
  registrySpend.hash = deployment.directorySpend.scriptHash;

  return {
    protocolParamsMint,
    programmableLogicGlobal,
    programmableLogicBase,
    issuanceCborHexMint,
    registryMint,
    registrySpend,
    buildIssuanceMint(mintingLogicHash: ScriptHash) {
      return builders.issuanceMint(
        deployment.programmableLogicBase.scriptHash,
        deployment.directoryMint.scriptHash,
        mintingLogicHash
      );
    },
  };
}

export interface ResolvedStandardScripts {
  protocolParamsMint: PlutusScript;
  programmableLogicGlobal: PlutusScript;
  programmableLogicBase: PlutusScript;
  issuanceCborHexMint: PlutusScript;
  registryMint: PlutusScript;
  registrySpend: PlutusScript;
  /** Build issuance_mint for a specific minting logic — NOT cached */
  buildIssuanceMint(mintingLogicHash: ScriptHash): PlutusScript;
}
