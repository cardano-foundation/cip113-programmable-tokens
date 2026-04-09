/**
 * Dummy substandard — minimal programmable token.
 *
 * Uses simple withdraw validators:
 * - issue: redeemer == 100
 * - transfer: redeemer == 200
 *
 * No compliance features, no blacklist.
 * Uses Evolution SDK directly — no adapter abstraction.
 */

import {
  Address as EvoAddress,
  Data,
  Transaction,
} from "@evolution-sdk/evolution";

import type { UTxO as EvoUTxO } from "@evolution-sdk/evolution";

import type { PlutusBlueprint, PlutusScript } from "../../types.js";
import type {
  SubstandardPlugin,
  SubstandardContext,
  EvoClient,
  RegisterParams,
  MintParams,
  BurnParams,
  TransferParams,
  UnsignedTx,
} from "../interface.js";
import { getValidatorCode } from "../../standard/blueprint.js";
import {
  sortTxInputs,
  findRefInputIndex,
  findRegistryNode,
  utxoToTxInput,
} from "../../core/registry.js";
import {
  buildEvoScript,
  computeScriptHash,
  scriptAddress,
  baseAddress,
  stakingCredentialHash,
  stringToHex,
  voidData,
  transferActRedeemer,
  utxoUnitQty,
  outputAssets,
  Credential,
  KeyHash,
  InlineDatum,
} from "../../core/evo-utils.js";

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
  let networkId: number;

  function buildScript(validatorTitle: string): PlutusScript {
    const code = getValidatorCode(config.blueprint, validatorTitle);
    const hash = computeScriptHash(code);
    return { type: "PlutusV3", compiledCode: code, hash };
  }

  return {
    id: "dummy",
    version: "0.1.0",
    blueprint: config.blueprint,

    init(context) {
      ctx = context;
      networkId = ctx.client.chain.id;
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
      const client = ctx.client;

      const plbHash = ctx.standardScripts.programmableLogicBase.hash;

      // 1. Build PLB addresses
      const senderPlbAddr = baseAddress(networkId, plbHash, senderAddress);
      const recipientPlbAddr = baseAddress(networkId, plbHash, recipientAddress);

      // 2. Find sender's token UTxOs
      const allUtxos = await client.getUtxos(EvoAddress.fromBech32(senderPlbAddr));
      const tokenUtxos = allUtxos.filter(u => utxoUnitQty(u, unit) > 0n);

      if (tokenUtxos.length === 0) {
        throw new Error(`No token UTxOs found at ${senderPlbAddr} for ${unit}`);
      }

      // 3. Select enough UTxOs
      const { selected, totalTokenAmount } = selectUtxosForAmount(tokenUtxos, unit, quantity);
      const returningAmount = totalTokenAmount - quantity;

      // 4. Find registry node reference input
      const registrySpendAddr = scriptAddress(networkId, ctx.standardScripts.registrySpend.hash);
      const registryUtxos = await client.getUtxos(EvoAddress.fromBech32(registrySpendAddr));
      const registryUtxo = findRegistryNode(registryUtxos, tokenPolicyId);
      if (!registryUtxo) {
        throw new Error(`Registry node not found for policy ${tokenPolicyId}`);
      }

      // 5. Get protocol params UTxO
      const ppUnit = ctx.deployment.protocolParams.policyId + stringToHex("ProtocolParams");
      const ppAddr = EvoAddress.fromBech32(
        scriptAddress(networkId, ctx.deployment.protocolParams.alwaysFailScriptHash)
      );
      const ppUtxos = await client.getUtxosWithUnit(ppAddr, ppUnit);
      if (ppUtxos.length === 0) throw new Error(`Protocol params UTxO not found (unit: ${ppUnit})`);
      const protocolParamsUtxo = ppUtxos[0];

      // 6. Sort reference inputs
      const refInputs = [utxoToTxInput(protocolParamsUtxo), utxoToTxInput(registryUtxo)];
      const sortedRefInputs = sortTxInputs(refInputs);
      const registryIdx = findRefInputIndex(sortedRefInputs, utxoToTxInput(registryUtxo));

      // 7. Build redeemers
      const plgRedeemer = transferActRedeemer([{ type: "exists", nodeIdx: registryIdx }]);
      const dummyTransferRedeemer = Data.int(200n);
      const spendRdmr = voidData();
      const tokenDatum = voidData();

      // 8. Get sender's staking credential
      const senderStakingHash = stakingCredentialHash(senderAddress);

      // 9. Get sender's wallet UTxOs
      const senderWalletUtxos = await client.getUtxos(EvoAddress.fromBech32(senderAddress));

      // 10. Build transaction
      let tx = client.newTx();

      tx = tx.collectFrom({ inputs: senderWalletUtxos.slice(0, 2) });
      tx = tx.collectFrom({ inputs: selected, redeemer: spendRdmr });

      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(transferScript.hash, "hex"))),
        amount: 0n,
        redeemer: dummyTransferRedeemer,
      });

      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(ctx.standardScripts.programmableLogicGlobal.hash, "hex"))),
        amount: 0n,
        redeemer: plgRedeemer,
      });

      if (returningAmount > 0n) {
        tx = tx.payToAddress({
          address: EvoAddress.fromBech32(senderPlbAddr),
          assets: outputAssets(1_300_000n, new Map([[unit, returningAmount]])),
          datum: new InlineDatum.InlineDatum({ data: tokenDatum }),
        });
      }

      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(recipientPlbAddr),
        assets: outputAssets(1_300_000n, new Map([[unit, quantity]])),
        datum: new InlineDatum.InlineDatum({ data: tokenDatum }),
      });

      tx = tx.readFrom({ referenceInputs: [protocolParamsUtxo, registryUtxo] });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.programmableLogicGlobal.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(transferScript.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.programmableLogicBase.compiledCode) });

      tx = tx.addSigner({ keyHash: KeyHash.fromHex(senderStakingHash) });

      // Build
      const result = await (tx as any).build({
        changeAddress: EvoAddress.fromBech32(senderAddress),
        availableUtxos: senderWalletUtxos,
      });

      const txObj = await result.toTransaction();
      const cbor = Transaction.toCBORHex(txObj);

      let txHash = "";
      if (typeof result.chainResult === "function") {
        txHash = result.chainResult().txHash;
      }

      return { cbor, txHash };
    },
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function selectUtxosForAmount(
  utxos: EvoUTxO.UTxO[],
  unit: string,
  requiredAmount: bigint
): { selected: EvoUTxO.UTxO[]; totalTokenAmount: bigint } {
  const selected: EvoUTxO.UTxO[] = [];
  let total = 0n;

  for (const utxo of utxos) {
    const amount = utxoUnitQty(utxo, unit);
    if (amount <= 0n) continue;
    selected.push(utxo);
    total += amount;
    if (total >= requiredAmount) break;
  }

  if (total < requiredAmount) {
    throw new Error(`Insufficient token balance: have ${total}, need ${requiredAmount}`);
  }

  return { selected, totalTokenAmount: total };
}
