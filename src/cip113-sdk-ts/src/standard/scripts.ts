/**
 * Standard script parameterization.
 *
 * Replicates the parameterization chain from ProtocolScriptBuilderService.java.
 * Each function takes a provider (for applyParamsToScript + scriptHash) and
 * returns a parameterized PlutusScript.
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

import type { CardanoProvider } from "../provider/interface.js";
import type {
  DeploymentParams,
  HexString,
  PlutusBlueprint,
  PlutusScript,
  ScriptHash,
  TxInput,
} from "../types.js";
import { getValidatorCode, STANDARD_VALIDATORS } from "./blueprint.js";
import { Data } from "../core/datums.js";

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
 */
export function createStandardScripts(
  blueprint: PlutusBlueprint,
  provider: CardanoProvider
): StandardScripts {
  function parameterize(validatorTitle: string, params: unknown[]): PlutusScript {
    const code = getValidatorCode(blueprint, validatorTitle);
    const parameterized = provider.applyParamsToScript(code, params);
    const hash = provider.scriptHash(parameterized);
    return { type: "PlutusV3", compiledCode: parameterized, hash };
  }

  return {
    alwaysFail(nonce) {
      return parameterize(STANDARD_VALIDATORS.ALWAYS_FAIL, [
        Data.bytes(nonce),
      ]);
    },

    protocolParamsMint(utxoRef, alwaysFailHash) {
      return parameterize(STANDARD_VALIDATORS.PROTOCOL_PARAMS_MINT, [
        Data.outputReference(utxoRef),
        Data.bytes(alwaysFailHash),
      ]);
    },

    programmableLogicGlobal(protocolParamsHash) {
      return parameterize(STANDARD_VALIDATORS.PROGRAMMABLE_LOGIC_GLOBAL, [
        Data.bytes(protocolParamsHash),
      ]);
    },

    programmableLogicBase(plgHash) {
      return parameterize(STANDARD_VALIDATORS.PROGRAMMABLE_LOGIC_BASE, [
        Data.scriptCredential(plgHash),
      ]);
    },

    issuanceCborHexMint(utxoRef, alwaysFailHash) {
      return parameterize(STANDARD_VALIDATORS.ISSUANCE_CBOR_HEX_MINT, [
        Data.outputReference(utxoRef),
        Data.bytes(alwaysFailHash),
      ]);
    },

    registryMint(utxoRef, issuanceCborHexHash) {
      return parameterize(STANDARD_VALIDATORS.REGISTRY_MINT, [
        Data.outputReference(utxoRef),
        Data.bytes(issuanceCborHexHash),
      ]);
    },

    registrySpend(protocolParamsHash) {
      return parameterize(STANDARD_VALIDATORS.REGISTRY_SPEND, [
        Data.bytes(protocolParamsHash),
      ]);
    },

    issuanceMint(plbHash, registryMintHash, mintingLogicHash) {
      return parameterize(STANDARD_VALIDATORS.ISSUANCE_MINT, [
        Data.scriptCredential(plbHash),
        Data.bytes(registryMintHash),
        Data.scriptCredential(mintingLogicHash),
      ]);
    },
  };
}

/**
 * Build resolved standard scripts from deployment params.
 *
 * IMPORTANT: Uses the known hashes from DeploymentParams (the source of truth)
 * rather than re-deriving them from the blueprint. Re-derivation can produce
 * different CBOR encoding → different hashes → wrong addresses.
 *
 * The compiled code is still parameterized from the blueprint when needed
 * (e.g., to attach a script to a transaction), but the hashes come from
 * the deployment.
 */
export function buildDeploymentScripts(
  blueprint: PlutusBlueprint,
  deployment: DeploymentParams,
  provider: CardanoProvider
): ResolvedStandardScripts {
  const builders = createStandardScripts(blueprint, provider);

  // Use KNOWN hashes from deployment — these are the actual on-chain values
  // Re-parameterize scripts for their compiled code, but override hashes

  const protocolParamsMint = builders.protocolParamsMint(
    deployment.protocolParams.txInput,
    deployment.protocolParams.alwaysFailScriptHash
  );
  // Override hash with the known deployment value
  protocolParamsMint.hash = deployment.protocolParams.policyId;

  const programmableLogicGlobal = builders.programmableLogicGlobal(
    deployment.protocolParams.policyId // Use known hash, not derived
  );
  programmableLogicGlobal.hash = deployment.programmableLogicGlobal.scriptHash;

  const programmableLogicBase = builders.programmableLogicBase(
    deployment.programmableLogicGlobal.scriptHash // Use known hash
  );
  programmableLogicBase.hash = deployment.programmableLogicBase.scriptHash;

  const issuanceCborHexMint = builders.issuanceCborHexMint(
    deployment.issuance.txInput,
    deployment.issuance.alwaysFailScriptHash
  );
  issuanceCborHexMint.hash = deployment.issuance.policyId;

  const registryMint = builders.registryMint(
    deployment.directoryMint.txInput,
    deployment.issuance.policyId // Use known hash
  );
  registryMint.hash = deployment.directoryMint.scriptHash;

  const registrySpend = builders.registrySpend(
    deployment.protocolParams.policyId // Use known hash
  );
  registrySpend.hash = deployment.directorySpend.scriptHash;

  return {
    protocolParamsMint,
    programmableLogicGlobal,
    programmableLogicBase,
    issuanceCborHexMint,
    registryMint,
    registrySpend,
    /** Build an issuance_mint script for a specific minting logic credential */
    buildIssuanceMint(mintingLogicHash: ScriptHash) {
      return builders.issuanceMint(
        deployment.programmableLogicBase.scriptHash, // Known PLB hash
        deployment.directoryMint.scriptHash, // Known registry mint hash
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
