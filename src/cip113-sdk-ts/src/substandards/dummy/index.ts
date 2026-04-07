/**
 * Dummy substandard — minimal programmable token.
 *
 * Uses simple withdraw validators:
 * - issue: redeemer == 100
 * - transfer: redeemer == 200
 *
 * No compliance features, no blacklist.
 */

import type { PlutusBlueprint, ScriptHash } from "../../types.js";
import type {
  SubstandardPlugin,
  SubstandardContext,
  RegisterParams,
  MintParams,
  BurnParams,
  TransferParams,
  UnsignedTx,
} from "../interface.js";
import { getValidatorCode } from "../../standard/blueprint.js";
import { Data } from "../../core/datums.js";
import {
  issuanceRedeemerFirstMint,
  issuanceRedeemerRefInput,
  registryInsertRedeemer,
  spendRedeemer,
  transferActRedeemer,
} from "../../core/redeemers.js";
import {
  sortTxInputs,
  findRefInputIndex,
  findCoveringNode,
  findRegistryNode,
} from "../../core/registry.js";
import { registryNodeDatum } from "../../core/datums.js";
import { stringToHex, MAX_NEXT } from "../../core/utils.js";

const DUMMY_VALIDATORS = {
  ISSUE: "issue.issue.withdraw",
  TRANSFER: "transfer.transfer.withdraw",
} as const;

export function dummySubstandard(config: {
  blueprint: PlutusBlueprint;
}): SubstandardPlugin {
  let ctx: SubstandardContext;

  // Cached substandard scripts (built during init)
  let issueScript: { compiledCode: string; hash: ScriptHash };
  let transferScript: { compiledCode: string; hash: ScriptHash };

  function buildIssueScript(): typeof issueScript {
    const code = getValidatorCode(config.blueprint, DUMMY_VALIDATORS.ISSUE);
    const hash = ctx.adapter.scriptHash(code);
    return { compiledCode: code, hash };
  }

  function buildTransferScript(): typeof transferScript {
    const code = getValidatorCode(config.blueprint, DUMMY_VALIDATORS.TRANSFER);
    const hash = ctx.adapter.scriptHash(code);
    return { compiledCode: code, hash };
  }

  return {
    id: "dummy",
    version: "0.1.0",
    blueprint: config.blueprint,

    init(context) {
      ctx = context;
      issueScript = buildIssueScript();
      transferScript = buildTransferScript();
    },

    async register(params: RegisterParams): Promise<UnsignedTx> {
      const {
        feePayerAddress,
        assetName,
        quantity,
        recipientAddress,
      } = params;

      const recipient = recipientAddress || feePayerAddress;
      const assetNameHex = stringToHex(assetName);

      // 1. Build issuance_mint script for this token
      const issuanceMintScript = ctx.standardScripts.buildIssuanceMint(issueScript.hash);
      const tokenPolicyId = issuanceMintScript.hash;

      // 2. Compute registry spend address
      const registrySpendAddress = ctx.adapter.scriptAddress(
        ctx.standardScripts.registrySpend.hash
      );

      // 3. Find covering node for insertion
      const coveringNodeUtxo = await findCoveringNode(
        ctx.adapter,
        registrySpendAddress,
        tokenPolicyId
      );
      if (!coveringNodeUtxo) {
        throw new Error("Could not find covering registry node for insertion");
      }

      // 4. Build reference inputs (protocol params + issuance cbor hex)
      const protocolParamsRefInput = {
        txHash: ctx.deployment.protocolParams.txInput.txHash,
        outputIndex: ctx.deployment.protocolParams.txInput.outputIndex,
      };
      const issuanceCborHexRefInput = {
        txHash: ctx.deployment.issuance.txInput.txHash,
        outputIndex: ctx.deployment.issuance.txInput.outputIndex,
      };

      // Fetch UTxOs for reference inputs
      // TODO: The adapter needs a method to fetch UTxOs by outref
      // For now, this is a placeholder - the actual implementation will
      // need to fetch these from the provider

      // 5. Build redeemers
      // Registry output will be at index 2: [0] PLB token output, [1] updated node, [2] new node
      const issuanceRedeemer = issuanceRedeemerFirstMint(issueScript.hash, 2);

      const registryMintRedeemer = registryInsertRedeemer(
        issuanceMintScript.hash, // key = token policy ID
        issueScript.hash // hashed_param = minting logic hash
      );

      // 6. Build datums for registry outputs
      const newRegistryNode = registryNodeDatum({
        key: tokenPolicyId,
        next: MAX_NEXT, // TODO: get from covering node's next
        transferLogicScript: { type: "script", hash: transferScript.hash },
        thirdPartyTransferLogicScript: { type: "script", hash: issueScript.hash },
        globalStateCs: "",
      });

      // 7. Build transaction
      // TODO: Implement full tx building using ctx.adapter.newTx()
      // This requires:
      // - collectFrom(coveringNode, spendRedeemer)
      // - withdraw(issueScript address, 0, Data.integer(100))
      // - mintAsset(issuanceMintScript, token, issuanceRedeemer)
      // - mintAsset(registryMintScript, nft, registryMintRedeemer)
      // - payToContract(PLB address + recipient stake cred, token value, void datum)
      // - payToContract(registry spend address, updated covering node value, updated datum)
      // - payToContract(registry spend address, new node value, new node datum)
      // - readFrom(protocolParams, issuanceCborHex)
      // - attachSpendingValidator(registrySpend)
      // - attachRewardValidator(issueScript)

      throw new Error(
        "dummy.register: Transaction building not yet implemented. " +
        `Token policy would be: ${tokenPolicyId}`
      );
    },

    async mint(params: MintParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, quantity, recipientAddress } = params;
      const recipient = recipientAddress || feePayerAddress;
      const assetNameHex = stringToHex(assetName);

      // 1. Find registry node for this token (RefInput proof)
      const registrySpendAddress = ctx.adapter.scriptAddress(
        ctx.standardScripts.registrySpend.hash
      );
      const registryNodeUtxo = await findRegistryNode(
        ctx.adapter,
        registrySpendAddress,
        tokenPolicyId
      );
      if (!registryNodeUtxo) {
        throw new Error(`Registry node not found for policy ${tokenPolicyId}`);
      }

      // 2. Compute reference input index
      const registryRefInput = {
        txHash: registryNodeUtxo.txHash,
        outputIndex: registryNodeUtxo.outputIndex,
      };
      const sortedRefInputs = sortTxInputs([registryRefInput]);
      const registryRefIdx = findRefInputIndex(sortedRefInputs, registryRefInput);

      // 3. Build redeemer with RefInput proof
      const issuanceMintScript = ctx.standardScripts.buildIssuanceMint(issueScript.hash);
      const issuanceRedeemer = issuanceRedeemerRefInput(issueScript.hash, registryRefIdx);

      // 4. Build transaction
      // TODO: Full tx building
      throw new Error(
        "dummy.mint: Transaction building not yet implemented. " +
        `Would mint ${quantity} of ${assetNameHex} under ${tokenPolicyId}`
      );
    },

    async burn(params: BurnParams): Promise<UnsignedTx> {
      // Burns require spending PLB UTxOs → PLGlobal validates
      throw new Error("dummy.burn: not yet implemented");
    },

    async transfer(params: TransferParams): Promise<UnsignedTx> {
      // Transfer requires PLGlobal TransferAct + dummy transfer logic (redeemer = 200)
      throw new Error("dummy.transfer: not yet implemented");
    },
  };
}
