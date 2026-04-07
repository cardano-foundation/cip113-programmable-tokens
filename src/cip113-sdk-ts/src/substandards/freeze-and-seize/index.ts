/**
 * Freeze-and-Seize substandard.
 *
 * Provides compliance features:
 * - Admin-controlled minting/burning
 * - Blacklist management (freeze/unfreeze addresses)
 * - Token seizure from frozen addresses
 * - Transfer validation against blacklist (non-membership proof)
 *
 * Replicates the Java FreezeAndSeizeHandler transaction flows.
 */

import type { PlutusBlueprint, PlutusScript, ScriptHash } from "../../types.js";
import type {
  SubstandardPlugin,
  SubstandardContext,
  RegisterParams,
  MintParams,
  BurnParams,
  TransferParams,
  FreezeParams,
  UnfreezeParams,
  SeizeParams,
  InitComplianceParams,
  UnsignedTx,
} from "../interface.js";
import { Data, registryNodeDatum } from "../../core/datums.js";
import {
  issuanceRedeemerFirstMint,
  issuanceRedeemerRefInput,
  registryInsertRedeemer,
  spendRedeemer,
  transferActRedeemer,
  thirdPartyActRedeemer,
  blacklistInitRedeemer,
  blacklistAddRedeemer,
  blacklistRemoveRedeemer,
} from "../../core/redeemers.js";
import {
  sortTxInputs,
  findRefInputIndex,
  findCoveringNode,
  findRegistryNode,
} from "../../core/registry.js";
import { stringToHex, MAX_NEXT } from "../../core/utils.js";
import { createFESScripts, type FESScripts } from "./scripts.js";

export function freezeAndSeizeSubstandard(config: {
  blueprint: PlutusBlueprint;
}): SubstandardPlugin {
  let ctx: SubstandardContext;
  let fesScripts: FESScripts;

  return {
    id: "freeze-and-seize",
    version: "0.1.0",
    blueprint: config.blueprint,

    init(context) {
      ctx = context;
      fesScripts = createFESScripts(config.blueprint, ctx.adapter);
    },

    // ====================================================================
    // REGISTER — First mint + registry insert
    // ====================================================================
    async register(params: RegisterParams): Promise<UnsignedTx> {
      const { feePayerAddress, assetName, quantity, recipientAddress, config: subConfig } = params;
      const recipient = recipientAddress || feePayerAddress;
      const assetNameHex = stringToHex(assetName);

      // Extract FES-specific config
      const adminPkh = (subConfig?.adminPkh as string) || "";
      const blacklistNodePolicyId = (subConfig?.blacklistNodePolicyId as string) || "";

      if (!adminPkh) throw new Error("freeze-and-seize.register: adminPkh required in config");
      if (!blacklistNodePolicyId) throw new Error("freeze-and-seize.register: blacklistNodePolicyId required in config");

      // 1. Build substandard scripts
      const issuerAdminScript = fesScripts.buildIssuerAdmin(adminPkh, assetNameHex);
      const transferScript = fesScripts.buildTransfer(
        ctx.standardScripts.programmableLogicBase.hash,
        blacklistNodePolicyId
      );

      // 2. Build issuance_mint script
      const issuanceMintScript = ctx.standardScripts.buildIssuanceMint(issuerAdminScript.hash);
      const tokenPolicyId = issuanceMintScript.hash;

      // 3. Find covering registry node
      const registrySpendAddress = ctx.adapter.scriptAddress(ctx.standardScripts.registrySpend.hash);
      const coveringNodeUtxo = await findCoveringNode(ctx.adapter, registrySpendAddress, tokenPolicyId);
      if (!coveringNodeUtxo) throw new Error("Could not find covering registry node");

      // 4. Build redeemers
      // Output layout: [0] PLB token, [1] updated covering node, [2] new registry node
      const issuanceRedeemer = issuanceRedeemerFirstMint(issuerAdminScript.hash, 2);
      const registryMintRedeemer = registryInsertRedeemer(
        issuanceMintScript.hash,
        issuerAdminScript.hash
      );

      // 5. Build new registry node datum
      const newNodeDatum = registryNodeDatum({
        key: tokenPolicyId,
        next: MAX_NEXT, // TODO: get from covering node
        transferLogicScript: { type: "script", hash: transferScript.hash },
        thirdPartyTransferLogicScript: { type: "script", hash: issuerAdminScript.hash },
        globalStateCs: "",
      });

      // 6. Build transaction
      // TODO: Full tx building with ctx.adapter.newTx()
      // Pattern from FreezeAndSeizeHandler.buildRegistrationTransaction:
      //   collectFrom(feePayerUtxos)
      //   collectFrom(coveringNode, spendRedeemer)
      //   withdraw(issuerAdmin, 0, ConstrPlutusData.of(0))
      //   mintAsset(issuanceMint, token, issuanceRedeemer)
      //   mintAsset(registryMint, nft, registryMintRedeemer)
      //   payToContract(PLB+recipientStake, tokenValue, void)
      //   payToContract(registrySpend, updatedCoveringNode)
      //   payToContract(registrySpend, newNode)
      //   readFrom(protocolParams, issuanceCborHex)
      //   attachSpendingValidator(registrySpend)
      //   attachRewardValidator(issuerAdmin)
      //   addSigner(adminPkh)

      return {
        cbor: "", // TODO
        txHash: "",
        tokenPolicyId,
        metadata: {
          issuerAdminScriptHash: issuerAdminScript.hash,
          transferScriptHash: transferScript.hash,
        },
      };
    },

    // ====================================================================
    // MINT — Subsequent mint with RefInput proof
    // ====================================================================
    async mint(params: MintParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, quantity, recipientAddress } = params;
      const recipient = recipientAddress || feePayerAddress;
      const assetNameHex = stringToHex(assetName);

      // TODO: Need adminPkh from context to rebuild issuerAdmin script
      // For now this demonstrates the flow
      throw new Error(
        "freeze-and-seize.mint: Need adminPkh to rebuild issuer admin script. " +
        "Pass via MintParams.config or resolve from on-chain registry."
      );
    },

    // ====================================================================
    // BURN — Burn with PLGlobal ThirdPartyAct
    // ====================================================================
    async burn(params: BurnParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, utxoTxHash, utxoOutputIndex } = params;

      // Pattern from FreezeAndSeizeHandler.buildBurnTransaction:
      //   Find registry node (RefInput)
      //   Find protocol params (RefInput)
      //   Sort reference inputs, compute indices
      //   Build issuance redeemer (RefInput)
      //   Build PLGlobal redeemer (ThirdPartyAct, registry_node_idx, outputs_start_idx=0)
      //   collectFrom(adminUtxos)
      //   collectFrom(utxoToBurn, spendRedeemer)
      //   withdraw(issuerAdmin, 0, void)
      //   withdraw(PLGlobal, 0, plgRedeemer)
      //   mintAsset(issuanceMint, -quantity, issuanceRedeemer)
      //   payToContract(original address, value minus policy)
      //   readFrom(protocolParams, registryNode)
      //   attachSpendingValidator(PLB)
      //   attachRewardValidator(PLGlobal, issuerAdmin)
      //   addSigner(adminPkh)

      throw new Error("freeze-and-seize.burn: not yet implemented");
    },

    // ====================================================================
    // TRANSFER — Transfer with blacklist non-membership proof
    // ====================================================================
    async transfer(params: TransferParams): Promise<UnsignedTx> {
      const { senderAddress, recipientAddress, tokenPolicyId, assetName, quantity } = params;

      // Pattern from FreezeAndSeizeHandler.buildTransferTransaction:
      //   Find token UTxOs at sender's PLB address
      //   Find registry node (RefInput)
      //   Find blacklist covering nodes for sender stake cred (non-membership proof)
      //   Find protocol params (RefInput)
      //   Sort all reference inputs, compute indices
      //   Build FES transfer redeemer (list of blacklist proofs)
      //   Build PLGlobal TransferAct redeemer
      //   collectFrom(senderUtxos for fees)
      //   collectFrom(tokenUtxos, spendRedeemer)
      //   withdraw(transferScript, 0, fesRedeemer)
      //   withdraw(PLGlobal, 0, plgRedeemer)
      //   payToContract(sender PLB address, remainingValue)
      //   payToContract(recipient PLB address, transferValue)
      //   readFrom(blacklistNodes, protocolParams, registryNode)
      //   attachSpendingValidator(PLB)
      //   attachRewardValidator(PLGlobal, transferScript)
      //   addSigner(sender staking cred)

      throw new Error("freeze-and-seize.transfer: not yet implemented");
    },

    // ====================================================================
    // INIT COMPLIANCE — Initialize blacklist
    // ====================================================================
    async initCompliance(params: InitComplianceParams): Promise<UnsignedTx> {
      const { feePayerAddress, adminAddress, assetName } = params;
      const assetNameHex = stringToHex(assetName);

      // 1. Get a bootstrap UTxO from fee payer
      const feePayerUtxos = await ctx.adapter.getUtxos(feePayerAddress);
      if (feePayerUtxos.length === 0) throw new Error("No UTxOs at fee payer address");

      const bootstrapUtxo = feePayerUtxos[0];
      const bootstrapTxInput = {
        txHash: bootstrapUtxo.txHash,
        outputIndex: bootstrapUtxo.outputIndex,
      };

      // 2. Extract admin PKH from address
      // TODO: proper address parsing
      const adminPkh = ""; // Would be extracted from adminAddress

      // 3. Build blacklist scripts
      const blacklistMintScript = fesScripts.buildBlacklistMint(bootstrapTxInput, adminPkh);
      const blacklistSpendScript = fesScripts.buildBlacklistSpend(blacklistMintScript.hash);

      // 4. Build issuer admin + transfer scripts
      const issuerAdminScript = fesScripts.buildIssuerAdmin(adminPkh, assetNameHex);
      const transferScript = fesScripts.buildTransfer(
        ctx.standardScripts.programmableLogicBase.hash,
        blacklistMintScript.hash
      );

      // 5. Build blacklist init transaction
      // Pattern from FreezeAndSeizeHandler.buildBlacklistInitTransaction:
      //   collectFrom(utilityUtxos) — must include bootstrap UTxO
      //   mintAsset(blacklistMint, originNft, blacklistInitRedeemer)
      //   payToAddress(feePayerAddress, 40 ADA) — chain output
      //   payToContract(blacklistSpendAddress, blacklistOriginNode)
      //   registerStake(issuerAdminAddress)
      //   registerStake(transferScriptAddress)

      return {
        cbor: "", // TODO
        txHash: "",
        metadata: {
          blacklistNodePolicyId: blacklistMintScript.hash,
          blacklistSpendScriptHash: blacklistSpendScript.hash,
          issuerAdminScriptHash: issuerAdminScript.hash,
          transferScriptHash: transferScript.hash,
        },
      };
    },

    // ====================================================================
    // FREEZE — Add address to blacklist
    // ====================================================================
    async freeze(params: FreezeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, targetAddress } = params;

      // Pattern from FreezeAndSeizeHandler.buildAddToBlacklistTransaction:
      //   Find blacklist covering node (key < target_cred < next)
      //   Build blacklist add redeemer
      //   collectFrom(managerUtxos)
      //   collectFrom(coveringBlacklistNode, spendRedeemer)
      //   mintAsset(blacklistMint, newNft, blacklistAddRedeemer)
      //   payToContract(blacklistSpend, updatedCoveringNode) — next = target
      //   payToContract(blacklistSpend, newNode) — key = target, next = old_next
      //   attachSpendingValidator(blacklistSpend)
      //   addSigner(managerPkh)

      throw new Error("freeze-and-seize.freeze: not yet implemented");
    },

    // ====================================================================
    // UNFREEZE — Remove address from blacklist
    // ====================================================================
    async unfreeze(params: UnfreezeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, targetAddress } = params;

      // Pattern from FreezeAndSeizeHandler.buildRemoveFromBlacklistTransaction:
      //   Find blacklist node to remove (key = target_cred)
      //   Find blacklist node to update (next = target_cred)
      //   Build blacklist remove redeemer
      //   collectFrom(managerUtxos)
      //   collectFrom(nodeToRemove, spendRedeemer)
      //   collectFrom(nodeToUpdate, spendRedeemer)
      //   mintAsset(blacklistMint, -1 nft, blacklistRemoveRedeemer) — burn
      //   payToContract(blacklistSpend, updatedNode) — next skips removed
      //   attachSpendingValidator(blacklistSpend)
      //   addSigner(managerPkh)

      throw new Error("freeze-and-seize.unfreeze: not yet implemented");
    },

    // ====================================================================
    // SEIZE — Seize tokens from a frozen address
    // ====================================================================
    async seize(params: SeizeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, utxoTxHash, utxoOutputIndex, destinationAddress } = params;

      // Pattern from FreezeAndSeizeHandler.buildSeizeTransaction:
      //   Find registry node (RefInput)
      //   Find protocol params (RefInput)
      //   Sort reference inputs, compute indices
      //   Build PLGlobal ThirdPartyAct redeemer (registry_node_idx, outputs_start_idx=1)
      //   collectFrom(adminUtxos)
      //   collectFrom(utxoToSeize, spendRedeemer)
      //   withdraw(issuerAdmin, 0, void)
      //   withdraw(PLGlobal, 0, plgRedeemer)
      //   payToContract(recipient PLB address, seizedValue)
      //   payToContract(original address, remainingValue)
      //   readFrom(protocolParams, registryNode)
      //   attachSpendingValidator(PLB)
      //   attachRewardValidator(PLGlobal, issuerAdmin)
      //   addSigner(adminPkh)

      throw new Error("freeze-and-seize.seize: not yet implemented");
    },
  };
}
