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
 * Build all static standard scripts from deployment params.
 * Returns cached scripts that don't vary per substandard/token.
 */
export function buildDeploymentScripts(
  blueprint: PlutusBlueprint,
  deployment: DeploymentParams,
  provider: CardanoProvider
): ResolvedStandardScripts {
  const builders = createStandardScripts(blueprint, provider);

  const protocolParamsMint = builders.protocolParamsMint(
    deployment.protocolParams.txInput,
    deployment.protocolParams.alwaysFailScriptHash
  );

  const programmableLogicGlobal = builders.programmableLogicGlobal(
    protocolParamsMint.hash
  );

  const programmableLogicBase = builders.programmableLogicBase(
    programmableLogicGlobal.hash
  );

  const issuanceCborHexMint = builders.issuanceCborHexMint(
    deployment.issuance.txInput,
    deployment.issuance.alwaysFailScriptHash
  );

  const registryMint = builders.registryMint(
    deployment.directoryMint.txInput,
    issuanceCborHexMint.hash
  );

  const registrySpend = builders.registrySpend(protocolParamsMint.hash);

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
        programmableLogicBase.hash,
        registryMint.hash,
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
