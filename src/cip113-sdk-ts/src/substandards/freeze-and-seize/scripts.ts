/**
 * Freeze-and-Seize script builders.
 *
 * Replicates FreezeAndSeizeScriptBuilderService.java.
 * Each function parameterizes a FES validator with its required params.
 */

import type { CardanoProvider } from "../../provider/interface.js";
import type { HexString, PlutusBlueprint, PlutusScript, ScriptHash, TxInput } from "../../types.js";
import { getValidatorCode } from "../../standard/blueprint.js";
import { Data } from "../../core/datums.js";

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
  /**
   * Build Issuer Admin Contract.
   * Params: [admin_credential, asset_name]
   * The asset_name differentiates the script per token.
   */
  buildIssuerAdmin(adminPkh: HexString, assetNameHex: HexString): PlutusScript;

  /**
   * Build Transfer Contract.
   * Params: [prog_logic_base_credential, blacklist_node_policy_id]
   */
  buildTransfer(progLogicBaseHash: ScriptHash, blacklistNodePolicyId: HexString): PlutusScript;

  /**
   * Build Blacklist Mint Contract.
   * Params: [bootstrap_utxo, admin_pkh]
   */
  buildBlacklistMint(bootstrapTxInput: TxInput, adminPkh: HexString): PlutusScript;

  /**
   * Build Blacklist Spend Contract.
   * Params: [blacklist_mint_policy_id]
   */
  buildBlacklistSpend(blacklistMintPolicyId: HexString): PlutusScript;
}

/**
 * Create FES script builders from a blueprint.
 */
export function createFESScripts(
  blueprint: PlutusBlueprint,
  provider: CardanoProvider
): FESScripts {
  function parameterize(validatorTitle: string, params: unknown[]): PlutusScript {
    const code = getValidatorCode(blueprint, validatorTitle);
    const parameterized = provider.applyParamsToScript(code, params);
    const hash = provider.scriptHash(parameterized);
    return { type: "PlutusV3", compiledCode: parameterized, hash };
  }

  return {
    buildIssuerAdmin(adminPkh, assetNameHex) {
      return parameterize(FES_VALIDATORS.ISSUER_ADMIN, [
        Data.keyCredential(adminPkh),
        Data.bytes(assetNameHex),
      ]);
    },

    buildTransfer(progLogicBaseHash, blacklistNodePolicyId) {
      return parameterize(FES_VALIDATORS.TRANSFER, [
        Data.scriptCredential(progLogicBaseHash),
        Data.bytes(blacklistNodePolicyId),
      ]);
    },

    buildBlacklistMint(bootstrapTxInput, adminPkh) {
      return parameterize(FES_VALIDATORS.BLACKLIST_MINT, [
        Data.outputReference(bootstrapTxInput),
        Data.bytes(adminPkh),
      ]);
    },

    buildBlacklistSpend(blacklistMintPolicyId) {
      return parameterize(FES_VALIDATORS.BLACKLIST_SPEND, [
        Data.bytes(blacklistMintPolicyId),
      ]);
    },
  };
}
