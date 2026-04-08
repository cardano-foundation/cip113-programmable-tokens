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
import { Data, registryNodeDatum, blacklistNodeDatum } from "../../core/datums.js";
import {
  issuanceRedeemerFirstMint,
  issuanceRedeemerRefInput,
  registryInsertRedeemer,
  transferActRedeemer,
  thirdPartyActRedeemer,
  blacklistInitRedeemer,
  blacklistAddRedeemer,
  blacklistRemoveRedeemer,
  spendRedeemer,
} from "../../core/redeemers.js";
import {
  sortTxInputs,
  findRefInputIndex,
  findRegistryNode,
  findCoveringNode,
} from "../../core/registry.js";
import { stringToHex, MAX_NEXT } from "../../core/utils.js";
import { createFESScripts } from "./scripts.js";
import type { FESDeploymentParams } from "./types.js";

import type { CardanoProvider } from "../../provider/interface.js";
import type { Address, DeploymentParams, HexString } from "../../types.js";

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
    // REGISTER — first mint + registry insert
    // Java ref: FreezeAndSeizeHandler.buildRegistrationTransaction()
    // ====================================================================
    async register(params: RegisterParams): Promise<UnsignedTx> {
      const { feePayerAddress, assetName, quantity, recipientAddress } = params;
      const recipient = recipientAddress || feePayerAddress;
      const assetNameHex = stringToHex(assetName);
      const unit = scripts.tokenPolicyId + assetNameHex;
      const adapter = ctx.adapter;

      // 1. Find covering registry node for insertion
      const registrySpendAddress = adapter.scriptAddress(ctx.standardScripts.registrySpend.hash);
      const coveringNodeUtxo = await findCoveringNode(adapter, registrySpendAddress, scripts.tokenPolicyId);
      if (!coveringNodeUtxo) throw new Error("Could not find covering registry node for insertion");

      // Parse covering node datum to get its key and next
      const coveringDatum = coveringNodeUtxo.datum;
      const coveringKey = extractConstrBytesField(coveringDatum, 0) ?? "";
      const coveringNext = extractConstrBytesField(coveringDatum, 1) ?? MAX_NEXT;

      // 2. Get reference inputs (protocol params + issuance CBOR hex)
      const protocolParamsUtxo = await findProtocolParamsUtxo(adapter, ctx.deployment);
      const issuanceCborHexUtxo = await findIssuanceCborHexUtxo(adapter, ctx.deployment);

      // 3. Build registry node datums
      const updatedCoveringDatum = registryNodeDatum({
        key: coveringKey,
        next: scripts.tokenPolicyId,
        transferLogicScript: { type: "script", hash: extractConstrBytesField(coveringDatum, 2, true) ?? "" },
        thirdPartyTransferLogicScript: { type: "script", hash: extractConstrBytesField(coveringDatum, 3, true) ?? "" },
        globalStateCs: extractConstrBytesField(coveringDatum, 4) ?? "",
      });

      const newRegistryNodeDatum = registryNodeDatum({
        key: scripts.tokenPolicyId,
        next: coveringNext,
        transferLogicScript: { type: "script", hash: scripts.transfer.hash },
        thirdPartyTransferLogicScript: { type: "script", hash: scripts.issuerAdmin.hash },
        globalStateCs: "",
      });

      // 4. Build redeemers
      // Output layout: [0] token, [1] updated covering node, [2] new registry node
      const issuanceRedeemer = issuanceRedeemerFirstMint(scripts.issuerAdmin.hash, 2);
      const registryMintRedeemer = registryInsertRedeemer(scripts.issuanceMint.hash, scripts.issuerAdmin.hash);
      const tokenDatum = Data.void();

      // 5. Get wallet UTxOs
      const walletUtxos = await adapter.getUtxos(feePayerAddress);

      // 6. Build PLB recipient address
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;
      const recipientPlbAddress = adapter.baseAddress(plbHash, recipient);

      // 7. Build registry spend address for outputs
      const registryMintPolicyId = ctx.standardScripts.registryMint.hash;

      // 8. Build token + NFT assets
      const tokenAssets = new Map<string, bigint>();
      tokenAssets.set(unit, quantity);

      const registryNftUnit = registryMintPolicyId + scripts.tokenPolicyId;
      const registryNftAssets = new Map<string, bigint>();
      registryNftAssets.set(registryNftUnit, 1n);

      // Get the covering node's existing NFT unit for the updated output
      const coveringNftUnit = findCoveringNodeNftUnit(coveringNodeUtxo, registryMintPolicyId);

      // 9. Build transaction
      let tx = adapter.newTx();

      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 3) }); // fee payer
      tx = tx.collectFrom({ inputs: [coveringNodeUtxo], redeemer: spendRedeemer() }); // spend covering node

      tx = tx.withdraw({ stakeCredential: scripts.issuerAdmin.hash, amount: 0n, redeemer: Data.void() }); // issuer admin

      // Mint programmable token
      tx = tx.mintAssets({ assets: tokenAssets, redeemer: issuanceRedeemer });
      // Mint registry NFT
      tx = tx.mintAssets({ assets: registryNftAssets, redeemer: registryMintRedeemer });

      // Output 0: token to recipient
      tx = tx.payToAddress({
        address: recipientPlbAddress,
        value: { lovelace: 1_300_000n, assets: tokenAssets },
        datum: tokenDatum,
        inlineDatum: true,
      });

      // Output 1: updated covering node
      const coveringNodeAssets = new Map<string, bigint>();
      if (coveringNftUnit) coveringNodeAssets.set(coveringNftUnit, 1n);
      tx = tx.payToAddress({
        address: registrySpendAddress,
        value: { lovelace: coveringNodeUtxo.value.lovelace, assets: coveringNodeAssets },
        datum: updatedCoveringDatum,
        inlineDatum: true,
      });

      // Output 2: new registry node
      const newNodeAssets = new Map<string, bigint>();
      newNodeAssets.set(registryNftUnit, 1n);
      tx = tx.payToAddress({
        address: registrySpendAddress,
        value: { lovelace: 1_300_000n, assets: newNodeAssets },
        datum: newRegistryNodeDatum,
        inlineDatum: true,
      });

      // Reference inputs
      tx = tx.readFrom({ referenceInputs: [protocolParamsUtxo, issuanceCborHexUtxo] });

      // Attach scripts
      tx = tx.attachScript({ script: ctx.standardScripts.registrySpend });
      tx = tx.attachScript({ script: scripts.issuerAdmin });
      tx = tx.attachScript({ script: scripts.issuanceMint });
      tx = tx.attachScript({ script: ctx.standardScripts.registryMint });

      // Required signer
      tx = tx.addSigner({ keyHash: config.deployment.adminPkh });

      tx = tx.provideUtxos(walletUtxos);
      tx = tx.setChangeAddress(feePayerAddress);

      const built = await tx.build();
      return {
        cbor: built.toCbor(),
        txHash: built.txHash(),
        tokenPolicyId: scripts.tokenPolicyId,
        metadata: {
          issuerAdminScriptHash: scripts.issuerAdmin.hash,
          transferScriptHash: scripts.transfer.hash,
        },
      };
    },

    // ====================================================================
    // MINT — subsequent mint with RefInput proof
    // Java ref: FreezeAndSeizeHandler.buildMintingTransaction()
    // ====================================================================
    async mint(params: MintParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, quantity, recipientAddress } = params;
      const recipient = recipientAddress || feePayerAddress;
      const assetNameHex = stringToHex(assetName);
      const unit = tokenPolicyId + assetNameHex;
      const adapter = ctx.adapter;

      if (tokenPolicyId !== scripts.tokenPolicyId) {
        throw new Error(`Token policy ${tokenPolicyId} does not match this FES instance (${scripts.tokenPolicyId})`);
      }

      // 1. Find registry node as RefInput proof
      const registrySpendAddress = adapter.scriptAddress(ctx.standardScripts.registrySpend.hash);
      const registryUtxo = await findRegistryNode(adapter, registrySpendAddress, tokenPolicyId);
      if (!registryUtxo) throw new Error(`Registry node not found for ${tokenPolicyId}`);

      // 2. Sort reference inputs and compute index
      const refInputs = [{ txHash: registryUtxo.txHash, outputIndex: registryUtxo.outputIndex }];
      const sortedRefInputs = sortTxInputs(refInputs);
      const registryRefIdx = findRefInputIndex(sortedRefInputs, { txHash: registryUtxo.txHash, outputIndex: registryUtxo.outputIndex });

      // 3. Build redeemers
      const issuanceRedeemer = issuanceRedeemerRefInput(scripts.issuerAdmin.hash, registryRefIdx);
      const tokenDatum = Data.void();

      // 4. Build PLB address
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;
      const recipientPlbAddress = adapter.baseAddress(plbHash, recipient);

      // 5. Get wallet UTxOs
      const walletUtxos = await adapter.getUtxos(feePayerAddress);

      // 6. Build transaction
      const tokenAssets = new Map<string, bigint>();
      tokenAssets.set(unit, quantity);

      let tx = adapter.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.withdraw({ stakeCredential: scripts.issuerAdmin.hash, amount: 0n, redeemer: Data.void() });
      tx = tx.mintAssets({ assets: tokenAssets, redeemer: issuanceRedeemer });
      tx = tx.payToAddress({
        address: recipientPlbAddress,
        value: { lovelace: 1_300_000n, assets: tokenAssets },
        datum: tokenDatum,
        inlineDatum: true,
      });
      tx = tx.readFrom({ referenceInputs: [registryUtxo] });
      tx = tx.attachScript({ script: scripts.issuerAdmin });
      tx = tx.attachScript({ script: scripts.issuanceMint });
      tx = tx.addSigner({ keyHash: config.deployment.adminPkh });
      tx = tx.provideUtxos(walletUtxos);
      tx = tx.setChangeAddress(feePayerAddress);

      const built = await tx.build();
      return { cbor: built.toCbor(), txHash: built.txHash(), tokenPolicyId };
    },

    // ====================================================================
    // BURN — burn + PLGlobal ThirdPartyAct
    // Java ref: FreezeAndSeizeHandler.buildBurnTransaction()
    // ====================================================================
    async burn(params: BurnParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, utxoTxHash, utxoOutputIndex } = params;
      const assetNameHex = stringToHex(assetName);
      const unit = tokenPolicyId + assetNameHex;
      const adapter = ctx.adapter;

      if (tokenPolicyId !== scripts.tokenPolicyId) {
        throw new Error(`Token policy ${tokenPolicyId} does not match this FES instance`);
      }

      // 1. Find UTxO to burn
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;
      // Search at the PLB address derived from the fee payer's staking cred
      const senderPlbAddress = adapter.baseAddress(plbHash, feePayerAddress);
      const allUtxos = await adapter.getUtxos(senderPlbAddress);
      const utxoToBurn = allUtxos.find(u => u.txHash === utxoTxHash && u.outputIndex === utxoOutputIndex);
      if (!utxoToBurn) throw new Error(`UTxO ${utxoTxHash}#${utxoOutputIndex} not found`);

      // 2. Get burn amount (entire policy from UTxO, as per Java handler)
      const burnAmount = utxoToBurn.value.assets?.get(unit) ?? 0n;
      if (burnAmount <= 0n) throw new Error(`No tokens of ${unit} in UTxO`);

      // 3. Find reference inputs
      const protocolParamsUtxo = await findProtocolParamsUtxo(adapter, ctx.deployment);
      const registrySpendAddress = adapter.scriptAddress(ctx.standardScripts.registrySpend.hash);
      const registryUtxo = await findRegistryNode(adapter, registrySpendAddress, tokenPolicyId);
      if (!registryUtxo) throw new Error(`Registry node not found for ${tokenPolicyId}`);

      // 4. Sort reference inputs
      const allRefInputRefs = [
        { txHash: protocolParamsUtxo.txHash, outputIndex: protocolParamsUtxo.outputIndex },
        { txHash: registryUtxo.txHash, outputIndex: registryUtxo.outputIndex },
      ];
      const sortedRefInputs = sortTxInputs(allRefInputRefs);
      const registryIdx = findRefInputIndex(sortedRefInputs, { txHash: registryUtxo.txHash, outputIndex: registryUtxo.outputIndex });

      // 5. Build redeemers
      const issuanceRedeemer = issuanceRedeemerRefInput(scripts.issuerAdmin.hash, registryIdx);
      const plgRedeemer = thirdPartyActRedeemer(registryIdx, 0); // outputs_start_idx = 0
      const tokenDatum = Data.void();

      // 6. Compute remaining value (remove entire policy from UTxO)
      const remainingAssets = new Map<string, bigint>();
      if (utxoToBurn.value.assets) {
        for (const [u, qty] of utxoToBurn.value.assets) {
          // Skip all assets under the burned policy
          if (!u.startsWith(tokenPolicyId)) {
            remainingAssets.set(u, qty);
          }
        }
      }

      // 7. Build burn assets (negative quantity)
      const burnAssets = new Map<string, bigint>();
      burnAssets.set(unit, -burnAmount);

      // 8. Get wallet UTxOs
      const walletUtxos = await adapter.getUtxos(feePayerAddress);

      // 9. Build transaction
      let tx = adapter.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.collectFrom({ inputs: [utxoToBurn], redeemer: spendRedeemer() });
      tx = tx.withdraw({ stakeCredential: scripts.issuerAdmin.hash, amount: 0n, redeemer: Data.void() });
      tx = tx.withdraw({ stakeCredential: ctx.standardScripts.programmableLogicGlobal.hash, amount: 0n, redeemer: plgRedeemer });
      tx = tx.payToAddress({
        address: utxoToBurn.address, // Return to original address
        value: { lovelace: utxoToBurn.value.lovelace, assets: remainingAssets.size > 0 ? remainingAssets : undefined },
        datum: tokenDatum,
        inlineDatum: true,
      });
      tx = tx.mintAssets({ assets: burnAssets, redeemer: issuanceRedeemer });
      tx = tx.readFrom({ referenceInputs: [protocolParamsUtxo, registryUtxo] });
      tx = tx.attachScript({ script: ctx.standardScripts.programmableLogicBase });
      tx = tx.attachScript({ script: ctx.standardScripts.programmableLogicGlobal });
      tx = tx.attachScript({ script: scripts.issuerAdmin });
      tx = tx.attachScript({ script: scripts.issuanceMint });
      tx = tx.addSigner({ keyHash: config.deployment.adminPkh });
      tx = tx.provideUtxos(walletUtxos);
      tx = tx.setChangeAddress(feePayerAddress);

      const built = await tx.build();
      return { cbor: built.toCbor(), txHash: built.txHash() };
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
    // INIT COMPLIANCE — initialize blacklist
    // Java ref: FreezeAndSeizeHandler.buildBlacklistInitTransaction()
    // ====================================================================
    async initCompliance(params: InitComplianceParams): Promise<UnsignedTx> {
      const { feePayerAddress, adminAddress, assetName } = params;
      const adapter = ctx.adapter;
      const assetNameHex = stringToHex(assetName);

      // 1. Get bootstrap UTxO from fee payer
      const walletUtxos = await adapter.getUtxos(feePayerAddress);
      if (walletUtxos.length === 0) throw new Error("No UTxOs at fee payer address");

      // 2. Build blacklist origin node
      const originDatum = blacklistNodeDatum("", MAX_NEXT);

      // 3. Compute blacklist spend address
      const blacklistSpendAddress = adapter.scriptAddress(scripts.blacklistSpend.hash);

      // 4. Compute stake addresses for registration
      const issuerAdminRewardAddr = adapter.rewardAddress(scripts.issuerAdmin.hash);
      const transferRewardAddr = adapter.rewardAddress(scripts.transfer.hash);

      // 5. Build blacklist origin NFT
      const blacklistOriginUnit = scripts.blacklistMint.hash + ""; // empty token name
      const blacklistOriginAssets = new Map<string, bigint>();
      blacklistOriginAssets.set(blacklistOriginUnit, 1n);

      // 6. Build transaction
      let tx = adapter.newTx();

      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 3) }); // wallet UTxOs including bootstrap

      // Mint blacklist origin NFT
      tx = tx.mintAssets({ assets: blacklistOriginAssets, redeemer: blacklistInitRedeemer() });

      // Output: chain output (40 ADA for next tx)
      tx = tx.payToAddress({
        address: feePayerAddress,
        value: { lovelace: 40_000_000n },
      });

      // Output: blacklist origin node
      const originNodeAssets = new Map<string, bigint>();
      originNodeAssets.set(blacklistOriginUnit, 1n);
      tx = tx.payToAddress({
        address: blacklistSpendAddress,
        value: { lovelace: 1_300_000n, assets: originNodeAssets },
        datum: originDatum,
        inlineDatum: true,
      });

      // Register stake addresses (issuer admin + transfer) unless skipped
      // Uses simple stake registration (no script witness) — same as Java backend
      if (!params.skipStakeRegistration) {
        tx = tx.registerStake({ stakeCredential: scripts.issuerAdmin.hash });
        tx = tx.registerStake({ stakeCredential: scripts.transfer.hash });
      }

      // Only the blacklist mint script needs to be attached for init
      tx = tx.attachScript({ script: scripts.blacklistMint });
      tx = tx.provideUtxos(walletUtxos);
      tx = tx.setChangeAddress(feePayerAddress);

      const built = await tx.build();
      return {
        cbor: built.toCbor(),
        txHash: built.txHash(),
        metadata: {
          blacklistNodePolicyId: scripts.blacklistMint.hash,
          blacklistSpendScriptHash: scripts.blacklistSpend.hash,
          issuerAdminScriptHash: scripts.issuerAdmin.hash,
          transferScriptHash: scripts.transfer.hash,
        },
      };
    },

    // ====================================================================
    // FREEZE — add address to blacklist
    // Java ref: FreezeAndSeizeHandler.buildAddToBlacklistTransaction()
    // ====================================================================
    async freeze(params: FreezeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, targetAddress } = params;
      const adapter = ctx.adapter;

      // 1. Get target's staking credential hash
      const targetStakingHash = adapter.stakingCredentialHash(targetAddress);

      // 2. Find covering node in blacklist
      const blacklistSpendAddress = adapter.scriptAddress(scripts.blacklistSpend.hash);
      const blacklistUtxos = await adapter.getUtxos(blacklistSpendAddress);
      const coveringNode = findBlacklistCoveringNode(blacklistUtxos, targetStakingHash);
      if (!coveringNode) throw new Error(`Cannot find blacklist covering node for ${targetStakingHash} — may already be blacklisted`);

      // Parse covering node datum
      const coveringKey = extractConstrBytesField(coveringNode.datum, 0) ?? "";
      const coveringNext = extractConstrBytesField(coveringNode.datum, 1) ?? MAX_NEXT;

      // 3. Build updated covering node (next → target) and new node (key = target, next = old next)
      const updatedCoveringDatum = blacklistNodeDatum(coveringKey, targetStakingHash);
      const newNodeDatum = blacklistNodeDatum(targetStakingHash, coveringNext);

      // 4. Build blacklist NFT (token name = target staking hash)
      const nftUnit = scripts.blacklistMint.hash + targetStakingHash;
      const nftAssets = new Map<string, bigint>();
      nftAssets.set(nftUnit, 1n);

      // 5. Get wallet UTxOs
      const walletUtxos = await adapter.getUtxos(feePayerAddress);

      // 6. Build transaction
      let tx = adapter.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) }); // fee payer
      tx = tx.collectFrom({ inputs: [coveringNode], redeemer: spendRedeemer() }); // spend covering node

      tx = tx.mintAssets({ assets: nftAssets, redeemer: blacklistAddRedeemer(targetStakingHash) });

      // Output 0: updated covering node
      const coveringNftUnit = findCoveringNodeNftUnit(coveringNode, scripts.blacklistMint.hash);
      const coveringAssets = new Map<string, bigint>();
      if (coveringNftUnit) coveringAssets.set(coveringNftUnit, 1n);
      tx = tx.payToAddress({
        address: blacklistSpendAddress,
        value: { lovelace: coveringNode.value.lovelace, assets: coveringAssets },
        datum: updatedCoveringDatum,
        inlineDatum: true,
      });

      // Output 1: new blacklist node
      const newNodeAssets = new Map<string, bigint>();
      newNodeAssets.set(nftUnit, 1n);
      tx = tx.payToAddress({
        address: blacklistSpendAddress,
        value: { lovelace: 1_300_000n, assets: newNodeAssets },
        datum: newNodeDatum,
        inlineDatum: true,
      });

      tx = tx.attachScript({ script: scripts.blacklistSpend });
      tx = tx.attachScript({ script: scripts.blacklistMint });
      // Manager signs (payment key hash of fee payer)
      const managerPkh = extractPaymentKeyHash(adapter, feePayerAddress);
      tx = tx.addSigner({ keyHash: managerPkh });
      tx = tx.provideUtxos(walletUtxos);
      tx = tx.setChangeAddress(feePayerAddress);

      const built = await tx.build();
      return { cbor: built.toCbor(), txHash: built.txHash() };
    },

    // ====================================================================
    // UNFREEZE — remove address from blacklist
    // Java ref: FreezeAndSeizeHandler.buildRemoveFromBlacklistTransaction()
    // ====================================================================
    async unfreeze(params: UnfreezeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, targetAddress } = params;
      const adapter = ctx.adapter;

      const targetStakingHash = adapter.stakingCredentialHash(targetAddress);

      // 1. Find the node to remove (key = target) and the preceding node (next = target)
      const blacklistSpendAddress = adapter.scriptAddress(scripts.blacklistSpend.hash);
      const blacklistUtxos = await adapter.getUtxos(blacklistSpendAddress);

      const nodeToRemove = blacklistUtxos.find(u => extractConstrBytesField(u.datum, 0) === targetStakingHash);
      if (!nodeToRemove) throw new Error(`Blacklist node not found for ${targetStakingHash}`);

      const precedingNode = blacklistUtxos.find(u => extractConstrBytesField(u.datum, 1) === targetStakingHash);
      if (!precedingNode) throw new Error(`Preceding blacklist node not found for ${targetStakingHash}`);

      // 2. Build updated preceding node (next skips removed node)
      const precedingKey = extractConstrBytesField(precedingNode.datum, 0) ?? "";
      const removedNext = extractConstrBytesField(nodeToRemove.datum, 1) ?? MAX_NEXT;
      const updatedPrecedingDatum = blacklistNodeDatum(precedingKey, removedNext);

      // 3. Build burn NFT (negative quantity)
      const nftUnit = scripts.blacklistMint.hash + targetStakingHash;
      const burnAssets = new Map<string, bigint>();
      burnAssets.set(nftUnit, -1n);

      // 4. Get wallet UTxOs
      const walletUtxos = await adapter.getUtxos(feePayerAddress);

      // 5. Build transaction
      let tx = adapter.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.collectFrom({ inputs: [nodeToRemove], redeemer: spendRedeemer() });
      tx = tx.collectFrom({ inputs: [precedingNode], redeemer: spendRedeemer() });

      tx = tx.mintAssets({ assets: burnAssets, redeemer: blacklistRemoveRedeemer(targetStakingHash) });

      // Output: updated preceding node
      const precedingNftUnit = findCoveringNodeNftUnit(precedingNode, scripts.blacklistMint.hash);
      const precedingAssets = new Map<string, bigint>();
      if (precedingNftUnit) precedingAssets.set(precedingNftUnit, 1n);
      tx = tx.payToAddress({
        address: blacklistSpendAddress,
        value: { lovelace: precedingNode.value.lovelace, assets: precedingAssets },
        datum: updatedPrecedingDatum,
        inlineDatum: true,
      });

      tx = tx.attachScript({ script: scripts.blacklistSpend });
      tx = tx.attachScript({ script: scripts.blacklistMint });
      const managerPkh = extractPaymentKeyHash(adapter, feePayerAddress);
      tx = tx.addSigner({ keyHash: managerPkh });
      tx = tx.provideUtxos(walletUtxos);
      tx = tx.setChangeAddress(feePayerAddress);

      const built = await tx.build();
      return { cbor: built.toCbor(), txHash: built.txHash() };
    },

    // ====================================================================
    // SEIZE — seize tokens via PLGlobal ThirdPartyAct
    // Java ref: FreezeAndSeizeHandler.buildSeizeTransaction()
    // ====================================================================
    async seize(params: SeizeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, utxoTxHash, utxoOutputIndex, destinationAddress } = params;
      const assetNameHex = stringToHex(assetName);
      const unit = tokenPolicyId + assetNameHex;
      const adapter = ctx.adapter;

      if (tokenPolicyId !== scripts.tokenPolicyId) {
        throw new Error(`Token policy ${tokenPolicyId} does not match this FES instance`);
      }

      // 1. Find UTxO to seize
      // We need to search broadly — the UTxO could be at any PLB address
      // Use the specific txHash + outputIndex from params
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;

      // Try to find the UTxO — it might be at various PLB addresses
      // The most reliable: query by the exact output reference
      // For now, search at a few likely addresses
      let utxoToSeize: UTxO | undefined;

      // Search across known addresses or use a broad search
      const searchAddresses = [
        adapter.baseAddress(plbHash, feePayerAddress),
        adapter.baseAddress(plbHash, destinationAddress),
      ];

      for (const addr of searchAddresses) {
        const utxos = await adapter.getUtxos(addr);
        utxoToSeize = utxos.find(u => u.txHash === utxoTxHash && u.outputIndex === utxoOutputIndex);
        if (utxoToSeize) break;
      }

      if (!utxoToSeize) throw new Error(`UTxO ${utxoTxHash}#${utxoOutputIndex} not found`);

      // 2. Get seized token amount
      const seizedAmount = utxoToSeize.value.assets?.get(unit) ?? 0n;
      if (seizedAmount <= 0n) throw new Error(`No tokens of ${unit} in UTxO`);

      // 3. Find reference inputs
      const protocolParamsUtxo = await findProtocolParamsUtxo(adapter, ctx.deployment);
      const registrySpendAddress = adapter.scriptAddress(ctx.standardScripts.registrySpend.hash);
      const registryUtxo = await findRegistryNode(adapter, registrySpendAddress, tokenPolicyId);
      if (!registryUtxo) throw new Error(`Registry node not found for ${tokenPolicyId}`);

      // 4. Sort reference inputs
      const allRefInputRefs = [
        { txHash: protocolParamsUtxo.txHash, outputIndex: protocolParamsUtxo.outputIndex },
        { txHash: registryUtxo.txHash, outputIndex: registryUtxo.outputIndex },
      ];
      const sortedRefInputs = sortTxInputs(allRefInputRefs);
      const registryIdx = findRefInputIndex(sortedRefInputs, { txHash: registryUtxo.txHash, outputIndex: registryUtxo.outputIndex });

      // 5. Build redeemers
      const plgRedeemer = thirdPartyActRedeemer(registryIdx, 1); // outputs_start_idx = 1
      const tokenDatum = Data.void();

      // 6. Build recipient PLB address
      const recipientPlbAddress = adapter.baseAddress(plbHash, destinationAddress);

      // 7. Compute seized + remaining values
      const seizedAssets = new Map<string, bigint>();
      seizedAssets.set(unit, seizedAmount);

      const remainingAssets = new Map<string, bigint>();
      if (utxoToSeize.value.assets) {
        for (const [u, qty] of utxoToSeize.value.assets) {
          if (u === unit) continue; // Remove seized token
          remainingAssets.set(u, qty);
        }
      }

      // 8. Get wallet UTxOs
      const walletUtxos = await adapter.getUtxos(feePayerAddress);

      // 9. Build transaction
      let tx = adapter.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.collectFrom({ inputs: [utxoToSeize], redeemer: spendRedeemer() });

      tx = tx.withdraw({ stakeCredential: scripts.issuerAdmin.hash, amount: 0n, redeemer: Data.void() });
      tx = tx.withdraw({ stakeCredential: ctx.standardScripts.programmableLogicGlobal.hash, amount: 0n, redeemer: plgRedeemer });

      // Output 0: seized tokens to recipient
      tx = tx.payToAddress({
        address: recipientPlbAddress,
        value: { lovelace: 1_300_000n, assets: seizedAssets },
        datum: tokenDatum,
        inlineDatum: true,
      });

      // Output 1: remaining value to original address
      tx = tx.payToAddress({
        address: utxoToSeize.address,
        value: { lovelace: utxoToSeize.value.lovelace, assets: remainingAssets.size > 0 ? remainingAssets : undefined },
        datum: tokenDatum,
        inlineDatum: true,
      });

      tx = tx.readFrom({ referenceInputs: [protocolParamsUtxo, registryUtxo] });
      tx = tx.attachScript({ script: ctx.standardScripts.programmableLogicBase });
      tx = tx.attachScript({ script: ctx.standardScripts.programmableLogicGlobal });
      tx = tx.attachScript({ script: scripts.issuerAdmin });
      tx = tx.addSigner({ keyHash: config.deployment.adminPkh });
      tx = tx.provideUtxos(walletUtxos);
      tx = tx.setChangeAddress(feePayerAddress);

      const built = await tx.build();
      return { cbor: built.toCbor(), txHash: built.txHash() };
    },
  };
}

// Re-export types and utilities
export type { FESDeploymentParams } from "./types.js";
export { createFESScripts } from "./scripts.js";

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

/** Find protocol params UTxO by searching for the protocol params NFT */
async function findProtocolParamsUtxo(
  adapter: CardanoProvider,
  deployment: DeploymentParams
): Promise<UTxO> {
  const ppUnit = deployment.protocolParams.policyId + stringToHex("ProtocolParams");

  // Search at the always-fail script address
  const utxos = await adapter.getUtxosWithUnit(
    adapter.scriptAddress(deployment.protocolParams.alwaysFailScriptHash),
    ppUnit
  );
  if (utxos.length > 0) return utxos[0];

  throw new Error(`Protocol params UTxO not found (unit: ${ppUnit})`);
}

/** Find issuance CBOR hex UTxO */
async function findIssuanceCborHexUtxo(
  adapter: CardanoProvider,
  deployment: DeploymentParams
): Promise<UTxO> {
  const icUnit = deployment.issuance.policyId + stringToHex("IssuanceCborHex");
  const utxos = await adapter.getUtxosWithUnit(
    adapter.scriptAddress(deployment.issuance.alwaysFailScriptHash),
    icUnit
  );
  if (utxos.length > 0) return utxos[0];

  throw new Error(`Issuance CBOR hex UTxO not found (unit: ${icUnit})`);
}

/** Extract a bytes field from a constr datum at a given index */
function extractConstrBytesField(datum: unknown, fieldIndex: number, isCredential = false): string | undefined {
  if (!datum || typeof datum !== "object") return undefined;

  // Evolution SDK format: { index: bigint, fields: Data[] } or { constr: number, fields: [] }
  const d = datum as any;
  const fields = d.fields ?? [];
  const field = fields[fieldIndex];
  if (!field) return undefined;

  if (isCredential) {
    // Credential is Constr(0|1, [bytes]) — extract the inner bytes
    const innerFields = field.fields ?? [];
    const inner = innerFields[0];
    if (!inner) return undefined;
    if (inner instanceof Uint8Array) return Array.from(inner).map((b: number) => b.toString(16).padStart(2, "0")).join("");
    if (typeof inner === "object" && "bytes" in inner) return inner.bytes;
    return undefined;
  }

  // Direct bytes field
  if (field instanceof Uint8Array) return Array.from(field).map((b: number) => b.toString(16).padStart(2, "0")).join("");
  if (typeof field === "object" && "bytes" in field) return field.bytes;
  if (typeof field === "string") return field;
  return undefined;
}

/** Find the NFT unit in a covering node's value that belongs to a given policy */
function findCoveringNodeNftUnit(utxo: UTxO, policyId: string): string | undefined {
  if (!utxo.value.assets) return undefined;
  for (const [unit] of utxo.value.assets) {
    if (unit.startsWith(policyId)) return unit;
  }
  return undefined;
}

/** Extract payment key hash from a Cardano address */
function extractPaymentKeyHash(adapter: CardanoProvider, address: Address): HexString {
  return adapter.paymentCredentialHash(address);
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
