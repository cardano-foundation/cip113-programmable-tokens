/**
 * Freeze-and-Seize substandard.
 *
 * Each instance manages ONE programmable token. The deployment params
 * (adminPkh, assetName, blacklistNodePolicyId) are provided at init
 * and used to parameterize all FES scripts once.
 *
 * Capabilities: register, mint, burn, transfer, freeze, unfreeze, seize.
 */

import type { PlutusBlueprint, PlutusScript, UTxO } from "../../types.js";
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
import { createFESScripts } from "./scripts.js";
import type { FESDeploymentParams } from "./types.js";

// ---------------------------------------------------------------------------
// Resolved scripts — computed once at init, reused for all operations
// ---------------------------------------------------------------------------

interface ResolvedFESScripts {
  issuerAdmin: PlutusScript;
  transfer: PlutusScript;
  blacklistMint: PlutusScript;
  blacklistSpend: PlutusScript;
  /** The issuance_mint policy for this token */
  issuanceMint: PlutusScript;
  /** Token's policy ID (= issuanceMint hash) */
  tokenPolicyId: string;
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

export function freezeAndSeizeSubstandard(config: {
  blueprint: PlutusBlueprint;
  deployment: FESDeploymentParams;
}): SubstandardPlugin {
  let ctx: SubstandardContext;
  let scripts: ResolvedFESScripts;

  return {
    id: "freeze-and-seize",
    version: "0.1.0",
    blueprint: config.blueprint,

    init(context) {
      ctx = context;
      const { adminPkh, assetName, blacklistNodePolicyId, blacklistInitTxInput } = config.deployment;
      const fes = createFESScripts(config.blueprint, ctx.adapter);
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;

      // Parameterize ALL FES scripts once
      const issuerAdmin = fes.buildIssuerAdmin(adminPkh, assetName);
      const transfer = fes.buildTransfer(plbHash, blacklistNodePolicyId);
      const blacklistMint = fes.buildBlacklistMint(blacklistInitTxInput, adminPkh);
      const blacklistSpend = fes.buildBlacklistSpend(blacklistNodePolicyId);
      const issuanceMint = ctx.standardScripts.buildIssuanceMint(issuerAdmin.hash);

      scripts = {
        issuerAdmin,
        transfer,
        blacklistMint,
        blacklistSpend,
        issuanceMint,
        tokenPolicyId: issuanceMint.hash,
      };
    },

    // ====================================================================
    // REGISTER
    // ====================================================================
    async register(_params: RegisterParams): Promise<UnsignedTx> {
      // TODO: replicate FreezeAndSeizeHandler.buildRegistrationTransaction
      throw new Error("freeze-and-seize.register: not yet implemented");
    },

    // ====================================================================
    // MINT
    // ====================================================================
    async mint(_params: MintParams): Promise<UnsignedTx> {
      // TODO: replicate FreezeAndSeizeHandler.buildMintingTransaction
      throw new Error("freeze-and-seize.mint: not yet implemented");
    },

    // ====================================================================
    // BURN
    // ====================================================================
    async burn(_params: BurnParams): Promise<UnsignedTx> {
      // TODO: replicate FreezeAndSeizeHandler.buildBurnTransaction
      throw new Error("freeze-and-seize.burn: not yet implemented");
    },

    // ====================================================================
    // TRANSFER — with blacklist non-membership proofs
    // ====================================================================
    async transfer(params: TransferParams): Promise<UnsignedTx> {
      const { senderAddress, recipientAddress, tokenPolicyId, assetName, quantity } = params;
      const assetNameHex = stringToHex(assetName);
      const unit = tokenPolicyId + assetNameHex;

      // Sanity check: the token must match this substandard instance
      if (tokenPolicyId !== scripts.tokenPolicyId) {
        throw new Error(
          `Token policy ${tokenPolicyId} does not match this FES instance (${scripts.tokenPolicyId})`
        );
      }

      const adapter = ctx.adapter;
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;

      // 1. Build PLB addresses
      const senderPlbAddress = adapter.baseAddress(plbHash, senderAddress);
      const recipientPlbAddress = adapter.baseAddress(plbHash, recipientAddress);

      // 2. Find sender's token UTxOs
      const allUtxos = await adapter.getUtxos(senderPlbAddress);
      const tokenUtxos = allUtxos.filter(
        (u) => u.value.assets?.has(unit) && (u.value.assets.get(unit) ?? 0n) > 0n
      );
      if (tokenUtxos.length === 0) {
        throw new Error(`No token UTxOs found at ${senderPlbAddress} for ${unit}`);
      }

      // 3. Select enough UTxOs
      const { selected, totalTokenAmount } = selectUtxosForAmount(tokenUtxos, unit, quantity);
      const returningAmount = totalTokenAmount - quantity;

      // 4. Find registry node reference input
      const registrySpendAddress = adapter.scriptAddress(ctx.standardScripts.registrySpend.hash);
      const registryUtxo = await findRegistryNode(adapter, registrySpendAddress, tokenPolicyId);
      if (!registryUtxo) throw new Error(`Registry node not found for ${tokenPolicyId}`);

      // 5. Find protocol params reference input
      const protocolParamsUtxos = await adapter.getUtxos(
        adapter.scriptAddress(ctx.deployment.protocolParams.alwaysFailScriptHash)
      );
      const ppUnit = ctx.deployment.protocolParams.policyId + stringToHex("ProtocolParams");
      const protocolParamsUtxo = protocolParamsUtxos.find((u) => u.value.assets?.has(ppUnit));
      if (!protocolParamsUtxo) throw new Error("Protocol params UTxO not found");

      // 6. Find blacklist non-membership proofs
      const senderStakingHash = adapter.stakingCredentialHash(senderAddress);
      const blacklistSpendAddress = adapter.scriptAddress(scripts.blacklistSpend.hash);
      const blacklistUtxos = await adapter.getUtxos(blacklistSpendAddress);

      // For each selected input, find covering node proving sender is NOT blacklisted
      const proofUtxos: UTxO[] = [];
      for (const _inputUtxo of selected) {
        const proofUtxo = findBlacklistCoveringNode(blacklistUtxos, senderStakingHash);
        if (!proofUtxo) {
          throw new Error(`Sender ${senderStakingHash} is blacklisted — transfer denied`);
        }
        // Deduplicate: same proof covers all inputs from same sender
        if (!proofUtxos.some(
          (p) => p.txHash === proofUtxo.txHash && p.outputIndex === proofUtxo.outputIndex
        )) {
          proofUtxos.push(proofUtxo);
        }
      }

      // 7. Sort ALL reference inputs and compute indices
      const allRefInputRefs = [
        ...proofUtxos.map((u) => ({ txHash: u.txHash, outputIndex: u.outputIndex })),
        { txHash: protocolParamsUtxo.txHash, outputIndex: protocolParamsUtxo.outputIndex },
        { txHash: registryUtxo.txHash, outputIndex: registryUtxo.outputIndex },
      ];
      const sortedRefInputs = sortTxInputs(allRefInputRefs);

      // Proof indices: one per selected input
      const proofIndices: number[] = selected.map(() =>
        findRefInputIndex(sortedRefInputs, {
          txHash: proofUtxos[0].txHash,
          outputIndex: proofUtxos[0].outputIndex,
        })
      );

      const registryIdx = findRefInputIndex(sortedRefInputs, {
        txHash: registryUtxo.txHash,
        outputIndex: registryUtxo.outputIndex,
      });

      // 8. Get sender's wallet UTxOs for fee coverage + collateral
      const senderWalletUtxos = await adapter.getUtxos(senderAddress);

      // 9. Build redeemers
      const fesTransferRedeemer = Data.list(
        proofIndices.map((idx) => Data.constr(0, [Data.integer(idx)]))
      );
      const plgRedeemer = transferActRedeemer([
        { type: "exists", nodeIdx: registryIdx },
      ]);
      const spendRdmr = spendRedeemer();
      const tokenDatum = Data.void();

      // 9. Build transaction
      let tx = adapter.newTx();

      // Spend token UTxOs
      tx = tx.collectFrom({ inputs: selected, redeemer: spendRdmr });

      // Withdraw-zero: PLGlobal (TransferAct)
      tx = tx.withdraw({
        stakeCredential: ctx.standardScripts.programmableLogicGlobal.hash,
        amount: 0n,
        redeemer: plgRedeemer,
      });

      // Withdraw-zero: FES transfer logic (blacklist proofs)
      tx = tx.withdraw({
        stakeCredential: scripts.transfer.hash,
        amount: 0n,
        redeemer: fesTransferRedeemer,
      });

      // Output: remaining tokens back to sender (if any)
      if (returningAmount > 0n) {
        const senderAssets = new Map<string, bigint>();
        senderAssets.set(unit, returningAmount);
        tx = tx.payToAddress({
          address: senderPlbAddress,
          value: { lovelace: 1_300_000n, assets: senderAssets },
          datum: tokenDatum,
          inlineDatum: true,
        });
      }

      // Output: transferred tokens to recipient
      const recipientAssets = new Map<string, bigint>();
      recipientAssets.set(unit, quantity);
      tx = tx.payToAddress({
        address: recipientPlbAddress,
        value: { lovelace: 1_300_000n, assets: recipientAssets },
        datum: tokenDatum,
        inlineDatum: true,
      });

      // Reference inputs
      const allRefUtxos = [...proofUtxos, protocolParamsUtxo, registryUtxo];
      tx = tx.readFrom({ referenceInputs: allRefUtxos });

      // Attach scripts
      tx = tx.attachScript({ script: ctx.standardScripts.programmableLogicBase });
      tx = tx.attachScript({ script: ctx.standardScripts.programmableLogicGlobal });
      tx = tx.attachScript({ script: scripts.transfer });

      // Required signer: sender's staking credential
      tx = tx.addSigner({ keyHash: senderStakingHash });

      // Provide wallet UTxOs for coin selection + collateral
      tx = tx.provideUtxos(senderWalletUtxos);

      // Change address: sender's wallet address
      tx = tx.setChangeAddress(senderAddress);

      const built = await tx.build();
      return {
        cbor: built.toCbor(),
        txHash: built.txHash(),
      };
    },

    // ====================================================================
    // COMPLIANCE: Init blacklist
    // ====================================================================
    async initCompliance(_params: InitComplianceParams): Promise<UnsignedTx> {
      throw new Error("freeze-and-seize.initCompliance: not yet implemented");
    },

    async freeze(_params: FreezeParams): Promise<UnsignedTx> {
      throw new Error("freeze-and-seize.freeze: not yet implemented");
    },

    async unfreeze(_params: UnfreezeParams): Promise<UnsignedTx> {
      throw new Error("freeze-and-seize.unfreeze: not yet implemented");
    },

    async seize(_params: SeizeParams): Promise<UnsignedTx> {
      throw new Error("freeze-and-seize.seize: not yet implemented");
    },
  };
}

// Re-export types
export type { FESDeploymentParams } from "./types.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function selectUtxosForAmount(
  utxos: UTxO[],
  unit: string,
  requiredAmount: bigint
): { selected: UTxO[]; totalTokenAmount: bigint } {
  const selected: UTxO[] = [];
  let total = 0n;

  for (const utxo of utxos) {
    const amount = utxo.value.assets?.get(unit) ?? 0n;
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

/**
 * Find a blacklist node proving non-membership for a given staking credential.
 * Non-membership: node.key < stakingHash < node.next
 */
function findBlacklistCoveringNode(
  blacklistUtxos: UTxO[],
  stakingHash: string
): UTxO | undefined {
  return blacklistUtxos.find((utxo) => {
    if (!utxo.datum) return false;

    const datum = utxo.datum as { constr?: number; fields?: unknown[] };
    if (!datum.fields || datum.fields.length < 2) return false;

    const keyField = datum.fields[0] as { bytes?: string };
    const nextField = datum.fields[1] as { bytes?: string };
    if (!keyField || !nextField) return false;

    const key = keyField.bytes ?? "";
    const next = nextField.bytes ?? "";

    return key < stakingHash && stakingHash < next;
  });
}
