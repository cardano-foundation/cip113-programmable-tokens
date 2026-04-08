/**
 * Dummy substandard — minimal programmable token.
 *
 * Uses simple withdraw validators:
 * - issue: redeemer == 100
 * - transfer: redeemer == 200
 *
 * No compliance features, no blacklist.
 */

import type { PlutusBlueprint, PlutusScript, ScriptHash } from "../../types.js";
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
  transferActRedeemer,
  spendRedeemer,
} from "../../core/redeemers.js";
import {
  sortTxInputs,
  findRefInputIndex,
  findRegistryNode,
} from "../../core/registry.js";
import { stringToHex } from "../../core/utils.js";

const DUMMY_VALIDATORS = {
  ISSUE: "transfer.issue.withdraw",
  TRANSFER: "transfer.transfer.withdraw",
} as const;

export function dummySubstandard(config: {
  blueprint: PlutusBlueprint;
}): SubstandardPlugin {
  let ctx: SubstandardContext;
  let issueScript: PlutusScript;
  let transferScript: PlutusScript;

  function buildScript(validatorTitle: string): PlutusScript {
    const code = getValidatorCode(config.blueprint, validatorTitle);
    const hash = ctx.adapter.scriptHash(code);
    return { type: "PlutusV3", compiledCode: code, hash };
  }

  return {
    id: "dummy",
    version: "0.1.0",
    blueprint: config.blueprint,

    init(context) {
      ctx = context;
      issueScript = buildScript(DUMMY_VALIDATORS.ISSUE);
      transferScript = buildScript(DUMMY_VALIDATORS.TRANSFER);
    },

    async register(_params: RegisterParams): Promise<UnsignedTx> {
      throw new Error("dummy.register: not yet implemented");
    },

    async mint(_params: MintParams): Promise<UnsignedTx> {
      throw new Error("dummy.mint: not yet implemented");
    },

    async burn(_params: BurnParams): Promise<UnsignedTx> {
      throw new Error("dummy.burn: not yet implemented");
    },

    async transfer(params: TransferParams): Promise<UnsignedTx> {
      const { senderAddress, recipientAddress, tokenPolicyId, assetName, quantity } = params;
      const assetNameHex = stringToHex(assetName);
      const unit = tokenPolicyId + assetNameHex;

      const adapter = ctx.adapter;
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;

      // 1. Build PLB addresses for sender and recipient
      const senderPlbAddress = adapter.baseAddress(plbHash, senderAddress);
      const recipientPlbAddress = adapter.baseAddress(plbHash, recipientAddress);

      // 2. Find sender's token UTxOs at PLB address
      const allUtxos = await adapter.getUtxos(senderPlbAddress);
      const tokenUtxos = allUtxos.filter(
        (u) => u.value.assets?.has(unit) && (u.value.assets.get(unit) ?? 0n) > 0n
      );

      if (tokenUtxos.length === 0) {
        throw new Error(`No token UTxOs found at ${senderPlbAddress} for ${unit}`);
      }

      // 3. Select enough UTxOs to cover the transfer amount
      const { selected, totalTokenAmount } = selectUtxosForAmount(tokenUtxos, unit, quantity);
      const returningAmount = totalTokenAmount - quantity;

      // 4. Find registry node as reference input
      const registrySpendAddress = adapter.scriptAddress(ctx.standardScripts.registrySpend.hash);
      const registryUtxo = await findRegistryNode(adapter, registrySpendAddress, tokenPolicyId);
      if (!registryUtxo) {
        throw new Error(`Registry node not found for policy ${tokenPolicyId}`);
      }

      // 5. Get protocol params UTxO as reference input
      // Protocol params NFT was locked at an always-fail address during bootstrap.
      // Look it up by its unique unit (policyId + "ProtocolParams") across all UTxOs
      // at the bootstrap tx output (index 0).
      const ppUnit = ctx.deployment.protocolParams.policyId + stringToHex("ProtocolParams");
      // Try fetching by the bootstrap tx output first (most reliable)
      let protocolParamsUtxo: import("../../types.js").UTxO | undefined;
      const bootstrapUtxos = await adapter.getUtxos(
        adapter.scriptAddress(ctx.deployment.directorySpend.scriptHash)
      );
      // Search more broadly — the protocol params live at the always-fail script address
      // which is parameterized and may differ from registrySpend
      const allPossibleAddresses = [
        // The protocol params are at bootstrap tx output 0, which is at the
        // always-fail address. We need to find them.
      ];
      // Simplest approach: search by unit across known addresses
      for (const utxo of bootstrapUtxos) {
        if (utxo.value.assets?.has(ppUnit)) {
          protocolParamsUtxo = utxo;
          break;
        }
      }
      // If not found at registry address, try the programmable base ref input
      if (!protocolParamsUtxo) {
        // The bootstrap params tell us exactly where the protocol params are
        const ppRefInput = ctx.deployment.programmableBaseRefInput;
        // Fetch UTxOs at every possible address until we find the NFT
        // Last resort: use getUtxosWithUnit if the adapter supports it
        const ppSearch = await adapter.getUtxosWithUnit(
          adapter.scriptAddress(ctx.deployment.protocolParams.alwaysFailScriptHash),
          ppUnit
        );
        protocolParamsUtxo = ppSearch[0];
      }
      if (!protocolParamsUtxo) {
        throw new Error(`Protocol params UTxO not found (unit: ${ppUnit})`);
      }

      // 6. Sort reference inputs and compute registry index
      const refInputs = [
        { txHash: protocolParamsUtxo.txHash, outputIndex: protocolParamsUtxo.outputIndex },
        { txHash: registryUtxo.txHash, outputIndex: registryUtxo.outputIndex },
      ];
      const sortedRefInputs = sortTxInputs(refInputs);
      const registryIdx = findRefInputIndex(sortedRefInputs, {
        txHash: registryUtxo.txHash,
        outputIndex: registryUtxo.outputIndex,
      });

      // 7. Build redeemers
      const plgRedeemer = transferActRedeemer([
        { type: "exists", nodeIdx: registryIdx },
      ]);
      const dummyTransferRedeemer = Data.integer(200); // Dummy: redeemer == 200
      const spendRdmr = spendRedeemer();
      const tokenDatum = Data.void();

      // 8. Get sender's staking credential for required signer
      const senderStakingHash = adapter.stakingCredentialHash(senderAddress);

      // 9. Get sender's wallet UTxOs for fee coverage
      const senderWalletUtxos = await adapter.getUtxos(senderAddress);

      // 10. Compute output values
      // Sum ADA from all selected token UTxOs (to preserve in outputs)
      const totalInputLovelace = selected.reduce((acc, u) => acc + u.value.lovelace, 0n);
      const minUtxoLovelace = 1_300_000n;

      // 11. Build transaction (matching Java DummySubstandardHandler order)
      let tx = adapter.newTx();

      // Collect wallet UTxOs for fees (no redeemer — regular UTxOs)
      tx = tx.collectFrom({ inputs: senderWalletUtxos.slice(0, 2) });

      // Collect script-locked token UTxOs (with spend redeemer)
      tx = tx.collectFrom({ inputs: selected, redeemer: spendRdmr });

      // Withdraw-zero: dummy transfer logic (redeemer = 200)
      tx = tx.withdraw({
        stakeCredential: transferScript.hash,
        amount: 0n,
        redeemer: dummyTransferRedeemer,
      });

      // Withdraw-zero: PLGlobal (TransferAct with registry proof)
      tx = tx.withdraw({
        stakeCredential: ctx.standardScripts.programmableLogicGlobal.hash,
        amount: 0n,
        redeemer: plgRedeemer,
      });

      // Output: remaining tokens back to sender (if any)
      if (returningAmount > 0n) {
        const senderAssets = new Map<string, bigint>();
        senderAssets.set(unit, returningAmount);
        tx = tx.payToAddress({
          address: senderPlbAddress,
          value: { lovelace: totalInputLovelace > minUtxoLovelace ? totalInputLovelace : minUtxoLovelace, assets: senderAssets },
          datum: tokenDatum,
          inlineDatum: true,
        });
      }

      // Output: transferred tokens to recipient
      const recipientAssets = new Map<string, bigint>();
      recipientAssets.set(unit, quantity);
      tx = tx.payToAddress({
        address: recipientPlbAddress,
        value: { lovelace: minUtxoLovelace, assets: recipientAssets },
        datum: tokenDatum,
        inlineDatum: true,
      });

      // Reference inputs
      tx = tx.readFrom({ referenceInputs: [protocolParamsUtxo, registryUtxo] });

      // Attach scripts (Java order: reward validators first, then spending)
      tx = tx.attachScript({ script: ctx.standardScripts.programmableLogicGlobal });
      tx = tx.attachScript({ script: transferScript });
      tx = tx.attachScript({ script: ctx.standardScripts.programmableLogicBase });

      // Required signer: sender's staking credential
      tx = tx.addSigner({ keyHash: senderStakingHash });

      // Provide remaining wallet UTxOs for coin selection + collateral
      tx = tx.provideUtxos(senderWalletUtxos);

      // Change address: sender's wallet address (not PLB address)
      tx = tx.setChangeAddress(senderAddress);

      // Debug: log tx structure before building
      console.log("[CIP113 DEBUG] Transfer tx structure:", {
        selectedInputs: selected.length,
        senderPlbAddress,
        recipientPlbAddress,
        registrySpendAddress: adapter.scriptAddress(ctx.standardScripts.registrySpend.hash),
        registryUtxoRef: `${registryUtxo.txHash}#${registryUtxo.outputIndex}`,
        protocolParamsRef: `${protocolParamsUtxo.txHash}#${protocolParamsUtxo.outputIndex}`,
        registryIdx,
        plbHash,
        plgHash: ctx.standardScripts.programmableLogicGlobal.hash,
        transferScriptHash: transferScript.hash,
        senderStakingHash,
        quantity: quantity.toString(),
        returningAmount: returningAmount.toString(),
      });

      // Build
      const built = await tx.build();
      const cbor = built.toCbor();

      console.log("[CIP113 DEBUG] Unsigned tx CBOR hex:", cbor);

      return {
        cbor,
        txHash: built.txHash(),
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function selectUtxosForAmount(
  utxos: import("../../types.js").UTxO[],
  unit: string,
  requiredAmount: bigint
): { selected: import("../../types.js").UTxO[]; totalTokenAmount: bigint } {
  const selected: import("../../types.js").UTxO[] = [];
  let total = 0n;

  for (const utxo of utxos) {
    const amount = utxo.value.assets?.get(unit) ?? 0n;
    if (amount <= 0n) continue;
    selected.push(utxo);
    total += amount;
    if (total >= requiredAmount) break;
  }

  if (total < requiredAmount) {
    throw new Error(
      `Insufficient token balance: have ${total}, need ${requiredAmount}`
    );
  }

  return { selected, totalTokenAmount: total };
}
