/**
 * Freeze-and-Seize script builders.
 *
 * Replicates FreezeAndSeizeScriptBuilderService.java.
 * Uses Evolution SDK directly for parameterization and hashing.
 */

import { Data } from "@evolution-sdk/evolution";
import type { HexString, PlutusBlueprint, PlutusScript, ScriptHash, TxInput } from "../../types.js";
import { getValidatorCode } from "../../standard/blueprint.js";
import {
  parameterizeScript,
  keyCredential,
  scriptCredential,
  outputReference,
} from "../../core/evo-utils.js";

// ---------------------------------------------------------------------------
// FES Validator Titles
// ---------------------------------------------------------------------------

export const FES_VALIDATORS = {
  ISSUER_ADMIN: "example_transfer_logic.issuer_admin_contract.withdraw",
  TRANSFER: "example_transfer_logic.transfer.withdraw",
  BLACKLIST_MINT: "blacklist_mint.blacklist_mint.mint",
  BLACKLIST_SPEND: "blacklist_spend.blacklist_spend.spend",
} as const;

// ---------------------------------------------------------------------------
// Script Builders
// ---------------------------------------------------------------------------

export interface FESScripts {
  buildIssuerAdmin(adminPkh: HexString, assetNameHex: HexString): PlutusScript;
  buildTransfer(progLogicBaseHash: ScriptHash, blacklistNodePolicyId: HexString): PlutusScript;
  buildBlacklistMint(bootstrapTxInput: TxInput, adminPkh: HexString): PlutusScript;
  buildBlacklistSpend(blacklistMintPolicyId: HexString): PlutusScript;
}

/**
 * Create FES script builders from a blueprint.
 * Uses Evolution SDK directly for parameterization and hashing.
 */
export function createFESScripts(
  blueprint: PlutusBlueprint,
): FESScripts {
  function parameterize(validatorTitle: string, params: Data.Data[]): PlutusScript {
    const code = getValidatorCode(blueprint, validatorTitle);
    return parameterizeScript(code, params);
  }

  return {
    buildIssuerAdmin(adminPkh, assetNameHex) {
      return parameterize(FES_VALIDATORS.ISSUER_ADMIN, [
        keyCredential(adminPkh),
        Data.bytearray(assetNameHex),
      ]);
    },

    buildTransfer(progLogicBaseHash, blacklistNodePolicyId) {
      return parameterize(FES_VALIDATORS.TRANSFER, [
        scriptCredential(progLogicBaseHash),
        Data.bytearray(blacklistNodePolicyId),
      ]);
    },

    buildBlacklistMint(bootstrapTxInput, adminPkh) {
      return parameterize(FES_VALIDATORS.BLACKLIST_MINT, [
        outputReference(bootstrapTxInput),
        Data.bytearray(adminPkh),
      ]);
    },

    buildBlacklistSpend(blacklistMintPolicyId) {
      return parameterize(FES_VALIDATORS.BLACKLIST_SPEND, [
        Data.bytearray(blacklistMintPolicyId),
      ]);
    },
  };
}
