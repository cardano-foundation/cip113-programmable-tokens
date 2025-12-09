/**
 * Protocol Script Builder for client-side transaction building
 * Mirrors the Java ProtocolScriptBuilderService functionality
 */

import { PlutusScript } from '@meshsdk/core';
import { applyParamsToAikenScript, createPlutusScript, getScriptHash } from './script-utils';
import type { ProtocolBootstrapParams, ProtocolBlueprint } from '@/types/protocol';

/**
 * Build parameterized issuance mint script
 *
 * @param protocolParams - Protocol bootstrap parameters
 * @param substandardIssueScript - The substandard issue validator script
 * @param blueprint - Protocol blueprint containing contract codes
 * @returns Parameterized issuance mint script
 */
export function buildIssuanceMintScript(
  protocolParams: ProtocolBootstrapParams,
  substandardIssueScript: PlutusScript,
  blueprint: ProtocolBlueprint
): PlutusScript {
  const programmableLogicBaseScriptHash = protocolParams.programmableLogicBaseParams.scriptHash;
  const substandardIssueScriptHash = getScriptHash(substandardIssueScript);

  // Build parameters: [constr(1, [bytes(programmableLogicBaseScriptHash)]), constr(1, [bytes(substandardIssueScriptHash)])]
  const params = [
    {
      constructor: 1,
      fields: [{ bytes: programmableLogicBaseScriptHash }]
    },
    {
      constructor: 1,
      fields: [{ bytes: substandardIssueScriptHash }]
    }
  ];

  // Get the issuance mint contract from blueprint
  const issuanceMintCode = blueprint.validators.find(
    v => v.title === 'issuance_mint.issuance_mint.mint'
  )?.compiledCode;

  if (!issuanceMintCode) {
    throw new Error('Issuance mint contract not found in blueprint');
  }

  // Apply parameters
  const parameterizedCode = applyParamsToAikenScript(params, issuanceMintCode);

  return createPlutusScript(parameterizedCode, 'V3');
}

/**
 * Build parameterized directory mint script
 *
 * @param protocolParams - Protocol bootstrap parameters
 * @param blueprint - Protocol blueprint containing contract codes
 * @returns Parameterized directory mint script
 */
export function buildDirectoryMintScript(
  protocolParams: ProtocolBootstrapParams,
  blueprint: ProtocolBlueprint
): PlutusScript {
  const utxo1 = protocolParams.directoryMintParams.txInput;
  const issuanceScriptHash = protocolParams.directoryMintParams.issuanceScriptHash;

  // Build parameters: [constr(0, [bytes(txHash), int(outputIndex)]), bytes(issuanceScriptHash)]
  const params: any[] = [
    {
      constructor: 0,
      fields: [
        { bytes: utxo1.txHash },
        { int: utxo1.outputIndex }
      ]
    },
    { bytes: issuanceScriptHash }
  ];

  // Get the directory mint contract from blueprint
  const directoryMintCode = blueprint.validators.find(
    v => v.title === 'registry_mint.registry_mint.mint'
  )?.compiledCode;

  if (!directoryMintCode) {
    throw new Error('Directory mint contract not found in blueprint');
  }

  // Apply parameters
  const parameterizedCode = applyParamsToAikenScript(params, directoryMintCode);

  return createPlutusScript(parameterizedCode, 'V3');
}

/**
 * Build parameterized directory spend script
 *
 * @param protocolParams - Protocol bootstrap parameters
 * @param blueprint - Protocol blueprint containing contract codes
 * @returns Parameterized directory spend script
 */
export function buildDirectorySpendScript(
  protocolParams: ProtocolBootstrapParams,
  blueprint: ProtocolBlueprint
): PlutusScript {
  const protocolParamsScriptHash = protocolParams.protocolParams.scriptHash;

  // Build parameters: [bytes(protocolParamsScriptHash)]
  const params = [{ bytes: protocolParamsScriptHash }];

  // Get the directory spend contract from blueprint
  const directorySpendCode = blueprint.validators.find(
    v => v.title === 'registry_spend.registry_spend.spend'
  )?.compiledCode;

  if (!directorySpendCode) {
    throw new Error('Directory spend contract not found in blueprint');
  }

  // Apply parameters
  const parameterizedCode = applyParamsToAikenScript(params, directorySpendCode);

  return createPlutusScript(parameterizedCode, 'V3');
}

/**
 * Build parameterized programmable logic base script
 *
 * @param protocolParams - Protocol bootstrap parameters
 * @param blueprint - Protocol blueprint containing contract codes
 * @returns Parameterized programmable logic base script
 */
export function buildProgrammableLogicBaseScript(
  protocolParams: ProtocolBootstrapParams,
  blueprint: ProtocolBlueprint
): PlutusScript {
  const programmableLogicGlobalScriptHash = protocolParams.programmableLogicGlobalPrams.scriptHash;

  // Build parameters: [constr(1, [bytes(programmableLogicGlobalScriptHash)])]
  const params = [
    {
      constructor: 1,
      fields: [{ bytes: programmableLogicGlobalScriptHash }]
    }
  ];

  // Get the programmable logic base contract from blueprint
  const programmableLogicBaseCode = blueprint.validators.find(
    v => v.title === 'programmable_logic_base.programmable_logic_base.spend'
  )?.compiledCode;

  if (!programmableLogicBaseCode) {
    throw new Error('Programmable logic base contract not found in blueprint');
  }

  // Apply parameters
  const parameterizedCode = applyParamsToAikenScript(params, programmableLogicBaseCode);

  return createPlutusScript(parameterizedCode, 'V3');
}

/**
 * Build parameterized programmable logic global script
 *
 * @param protocolParams - Protocol bootstrap parameters
 * @param blueprint - Protocol blueprint containing contract codes
 * @returns Parameterized programmable logic global script
 */
export function buildProgrammableLogicGlobalScript(
  protocolParams: ProtocolBootstrapParams,
  blueprint: ProtocolBlueprint
): PlutusScript {
  const protocolParamsScriptHash = protocolParams.protocolParams.scriptHash;

  // Build parameters: [bytes(protocolParamsScriptHash)]
  const params = [{ bytes: protocolParamsScriptHash }];

  // Get the programmable logic global contract from blueprint
  const programmableLogicGlobalCode = blueprint.validators.find(
    v => v.title === 'programmable_logic_global.programmable_logic_global.withdraw'
  )?.compiledCode;

  if (!programmableLogicGlobalCode) {
    throw new Error('Programmable logic global contract not found in blueprint');
  }

  // Apply parameters
  const parameterizedCode = applyParamsToAikenScript(params, programmableLogicGlobalCode);

  return createPlutusScript(parameterizedCode, 'V3');
}
