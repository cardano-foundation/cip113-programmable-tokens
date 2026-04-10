/**
 * Freeze-and-Seize substandard.
 *
 * Uses Evolution SDK directly — no adapter abstraction.
 *
 * Capabilities: register, mint, burn, transfer, freeze, unfreeze, seize.
 */

import {
  Address as EvoAddress,
  Assets,
  Data,
  Transaction,
  TransactionHash as EvoTransactionHash,
  TransactionInput as EvoTransactionInput,
} from "@evolution-sdk/evolution";

import type { UTxO as EvoUTxO } from "@evolution-sdk/evolution";

import type { PlutusBlueprint, PlutusScript, DeploymentParams, HexString } from "../../types.js";
import type {
  SubstandardPlugin,
  SubstandardContext,
  EvoClient,
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
import {
  sortTxInputs,
  findRefInputIndex,
  findRegistryNode,
  findCoveringNode,
  utxoToTxInput,
} from "../../core/registry.js";
import {
  buildEvoScript,
  scriptAddress,
  rewardAddress,
  baseAddress,
  stakingCredentialHash,
  paymentCredentialHash,
  stringToHex,
  MAX_NEXT,
  voidData,
  registryNodeDatum,
  blacklistNodeDatum,
  issuanceRedeemerFirstMint,
  issuanceRedeemerRefInput,
  registryInsertRedeemer,
  transferActRedeemer,
  thirdPartyActRedeemer,
  blacklistInitRedeemer,
  blacklistAddRedeemer,
  blacklistRemoveRedeemer,
  extractConstrBytesField,
  extractCredentialField,
  getInlineDatum,
  utxoHasUnit,
  utxoUnitQty,
  utxoLovelace,
  utxoTxHash,
  utxoOutputIndex,
  outputAssets,
  mintAssetsFromMap,
  Credential,
  KeyHash,
  InlineDatum,
  labeledAssetName,
  hasCIP67Label,
  buildCIP68FTDatum,
} from "../../core/evo-utils.js";
import { createFESScripts } from "./scripts.js";
import type { FESDeploymentParams } from "./types.js";

// Stake registration check is provided via ctx.checkStakeRegistration callback.
// No direct HTTP calls from the SDK — the caller provides the implementation.

// ---------------------------------------------------------------------------
// Resolved scripts — computed once at init, reused for all operations
// ---------------------------------------------------------------------------

interface ResolvedFESScripts {
  issuerAdmin: PlutusScript;
  transfer: PlutusScript;
  blacklistMint: PlutusScript;
  blacklistSpend: PlutusScript;
  issuanceMint: PlutusScript;
  tokenPolicyId: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Build the transaction and extract unsigned CBOR + txHash.
 * Works with both ReadOnlyClient (TransactionResultBase) and SigningClient (SignBuilder).
 */
async function buildAndSerialize(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  builder: any,
  changeAddress: string,
  availableUtxos?: EvoUTxO.UTxO[],
  passAdditionalUtxos = false,
// eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<{ cbor: string; txHash: string; chainAvailable?: EvoUTxO.UTxO[]; _signBuilder?: any }> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const buildOpts: any = {
    changeAddress: EvoAddress.fromBech32(changeAddress),
  };
  if (availableUtxos) {
    buildOpts.availableUtxos = availableUtxos;
  }
  if (passAdditionalUtxos) {
    buildOpts.passAdditionalUtxos = true;
  }
  const result = await builder.build(buildOpts);

  const tx = await result.toTransaction();
  const cbor = Transaction.toCBORHex(tx);

  // Extract txHash and chainResult — SignBuilder has chainResult
  let txHash = "";
  let chainAvailable: EvoUTxO.UTxO[] | undefined;
  if (typeof result.chainResult === "function") {
    const cr = result.chainResult();
    txHash = cr.txHash;
    chainAvailable = cr.available as EvoUTxO.UTxO[];
  }

  return { cbor, txHash, chainAvailable, _signBuilder: result };
}

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

/** Find protocol params UTxO by searching for the protocol params NFT */
async function findProtocolParamsUtxo(
  client: EvoClient,
  networkId: number,
  deployment: DeploymentParams
): Promise<EvoUTxO.UTxO> {
  const ppUnit = deployment.protocolParams.policyId + stringToHex("ProtocolParams");
  const addr = EvoAddress.fromBech32(
    scriptAddress(networkId, deployment.protocolParams.alwaysFailScriptHash)
  );
  const utxos = await client.getUtxosWithUnit(addr, ppUnit);
  if (utxos.length > 0) return utxos[0];
  throw new Error(`Protocol params UTxO not found (unit: ${ppUnit})`);
}

/** Find issuance CBOR hex UTxO */
async function findIssuanceCborHexUtxo(
  client: EvoClient,
  networkId: number,
  deployment: DeploymentParams
): Promise<EvoUTxO.UTxO> {
  const icUnit = deployment.issuance.policyId + stringToHex("IssuanceCborHex");
  const addr = EvoAddress.fromBech32(
    scriptAddress(networkId, deployment.issuance.alwaysFailScriptHash)
  );
  const utxos = await client.getUtxosWithUnit(addr, icUnit);
  if (utxos.length > 0) return utxos[0];
  throw new Error(`Issuance CBOR hex UTxO not found (unit: ${icUnit})`);
}

/** Find the NFT unit in a covering node's value that belongs to a given policy */
function findCoveringNodeNftUnit(utxo: EvoUTxO.UTxO, policyId: string): string | undefined {
  const units = Assets.getUnits(utxo.assets);
  for (const unit of units) {
    if (unit === "lovelace" || unit === "") continue;
    if (unit.startsWith(policyId)) return unit;
  }
  return undefined;
}

/**
 * Find a blacklist node proving non-membership for a given staking credential.
 * Non-membership: node.key < stakingHash < node.next
 */
function findBlacklistCoveringNode(
  blacklistUtxos: EvoUTxO.UTxO[],
  stakingHash: string
): EvoUTxO.UTxO | undefined {
  return blacklistUtxos.find((utxo) => {
    const datum = getInlineDatum(utxo);
    if (!datum) return false;
    const key = extractConstrBytesField(datum, 0) ?? "";
    const next = extractConstrBytesField(datum, 1) ?? MAX_NEXT;
    return key < stakingHash && stakingHash < next;
  });
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
  let networkId: number;

  return {
    id: "freeze-and-seize",
    version: "0.1.0",
    blueprint: config.blueprint,

    init(context) {
      ctx = context;
      networkId = ctx.client.chain.id;
      const { adminPkh, assetName, blacklistNodePolicyId, blacklistInitTxInput } = config.deployment;
      const fes = createFESScripts(config.blueprint);
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;

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
    // ====================================================================
    async register(params: RegisterParams): Promise<UnsignedTx> {
      const { feePayerAddress, assetName, quantity, recipientAddress } = params;
      const recipient = recipientAddress || feePayerAddress;
      const chainedUtxos = (params.chainedUtxos ?? []) as EvoUTxO.UTxO[];
      const assetNameHex = stringToHex(assetName);
      const hasCIP68 = !!params.cip68Metadata;
      const client = ctx.client;

      // When CIP-68 is enabled, prefix asset names with CIP-67 labels
      const userAssetNameHex = hasCIP68 ? labeledAssetName(333, assetNameHex) : assetNameHex;
      const unit = scripts.tokenPolicyId + userAssetNameHex;

      // Reference token (only when CIP-68)
      const refAssetNameHex = hasCIP68 ? labeledAssetName(100, assetNameHex) : null;
      const refUnit = refAssetNameHex ? scripts.tokenPolicyId + refAssetNameHex : null;

      // 1. Find covering registry node
      const registrySpendAddr = scriptAddress(networkId, ctx.standardScripts.registrySpend.hash);
      const registryUtxos = await client.getUtxos(EvoAddress.fromBech32(registrySpendAddr));
      const coveringNodeUtxo = findCoveringNode(registryUtxos, scripts.tokenPolicyId);
      if (!coveringNodeUtxo) throw new Error("Could not find covering registry node for insertion");

      const coveringDatum = getInlineDatum(coveringNodeUtxo);
      const coveringKey = extractConstrBytesField(coveringDatum, 0) ?? "";
      const coveringNext = extractConstrBytesField(coveringDatum, 1) ?? MAX_NEXT;

      // 2. Get reference inputs
      const protocolParamsUtxo = await findProtocolParamsUtxo(client, networkId, ctx.deployment);
      const issuanceCborHexUtxo = await findIssuanceCborHexUtxo(client, networkId, ctx.deployment);

      // 3. Build datums
      const coveringTransferCred = extractCredentialField(coveringDatum, 2) ?? { type: "key" as const, hash: "" };
      const coveringThirdPartyCred = extractCredentialField(coveringDatum, 3) ?? { type: "key" as const, hash: "" };

      const updatedCoveringDatum = registryNodeDatum({
        key: coveringKey,
        next: scripts.tokenPolicyId,
        transferLogicScript: coveringTransferCred,
        thirdPartyTransferLogicScript: coveringThirdPartyCred,
        globalStateCs: extractConstrBytesField(coveringDatum, 4) ?? "",
      });

      const newRegistryNodeDatum = registryNodeDatum({
        key: scripts.tokenPolicyId,
        next: coveringNext,
        transferLogicScript: { type: "script", hash: scripts.transfer.hash },
        thirdPartyTransferLogicScript: { type: "script", hash: scripts.issuerAdmin.hash },
        globalStateCs: "",
      });

      // 4. Build redeemers — registry output index shifts when CIP-68 adds an extra output
      const registryOutputIndex = hasCIP68 ? 3 : 2;
      const issuanceRedeemer = issuanceRedeemerFirstMint(scripts.issuerAdmin.hash, registryOutputIndex);
      const registryMintRedeemer = registryInsertRedeemer(scripts.issuanceMint.hash, scripts.issuerAdmin.hash);
      const tokenDatum = voidData();

      // 5. Determine if chaining from initCompliance
      const useChaining = chainedUtxos.length > 0;

      // 6. Build addresses
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;
      const recipientPlbAddr = baseAddress(networkId, plbHash, recipient);
      const registryMintPolicyId = ctx.standardScripts.registryMint.hash;

      // 7. Build asset maps — include CIP-68 ref token in the same mint (same policy + redeemer)
      const mintEntries = new Map<string, bigint>([[unit, quantity]]);
      if (hasCIP68 && refUnit) {
        mintEntries.set(refUnit, 1n);
      }
      const tokenAssets = mintAssetsFromMap(mintEntries);
      const registryNftUnit = registryMintPolicyId + scripts.tokenPolicyId;
      const registryNftAssets = mintAssetsFromMap(new Map([[registryNftUnit, 1n]]));
      const coveringNftUnit = findCoveringNodeNftUnit(coveringNodeUtxo, registryMintPolicyId);

      // 8. Build transaction
      let tx = client.newTx();

      tx = tx.collectFrom({ inputs: [coveringNodeUtxo], redeemer: voidData() });

      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(scripts.issuerAdmin.hash, "hex"))),
        amount: 0n,
        redeemer: voidData(),
      });

      tx = tx.mintAssets({ assets: tokenAssets, redeemer: issuanceRedeemer });
      tx = tx.mintAssets({ assets: registryNftAssets, redeemer: registryMintRedeemer });

      // Output 0: user token to recipient (with label 333 prefix if CIP-68)
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(recipientPlbAddr),
        assets: outputAssets(1_300_000n, new Map([[unit, quantity]])),
        datum: new InlineDatum.InlineDatum({ data: tokenDatum }),
      });

      // Output 1 (CIP-68 only): reference token to issuer's PLB address with metadata datum
      if (hasCIP68 && refUnit) {
        const issuerPlbAddr = baseAddress(networkId, plbHash, feePayerAddress);
        const cip68Datum = buildCIP68FTDatum(params.cip68Metadata!);
        tx = tx.payToAddress({
          address: EvoAddress.fromBech32(issuerPlbAddr),
          assets: outputAssets(3_000_000n, new Map([[refUnit, 1n]])),
          datum: new InlineDatum.InlineDatum({ data: cip68Datum }),
        });
      }

      // Updated covering node (output 1 or 2)
      const coveringNodeTokenMap = new Map<string, bigint>();
      if (coveringNftUnit) coveringNodeTokenMap.set(coveringNftUnit, 1n);
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(registrySpendAddr),
        assets: outputAssets(utxoLovelace(coveringNodeUtxo), coveringNodeTokenMap),
        datum: new InlineDatum.InlineDatum({ data: updatedCoveringDatum }),
      });

      // New registry node (output 2 or 3)
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(registrySpendAddr),
        assets: outputAssets(2_000_000n, new Map([[registryNftUnit, 1n]])),
        datum: new InlineDatum.InlineDatum({ data: newRegistryNodeDatum }),
      });

      // Reference inputs
      tx = tx.readFrom({ referenceInputs: [protocolParamsUtxo, issuanceCborHexUtxo] });

      // Attach scripts
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.registrySpend.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.issuerAdmin.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.issuanceMint.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.registryMint.compiledCode) });

      // Required signer
      tx = tx.addSigner({ keyHash: KeyHash.fromHex(config.deployment.adminPkh) });

      const built = await buildAndSerialize(
        tx, feePayerAddress,
        useChaining ? chainedUtxos : undefined,
        useChaining,
      );
      return {
        cbor: built.cbor,
        txHash: built.txHash,
        _signBuilder: built._signBuilder,
        tokenPolicyId: scripts.tokenPolicyId,
        metadata: {
          issuerAdminScriptHash: scripts.issuerAdmin.hash,
          transferScriptHash: scripts.transfer.hash,
          ...(hasCIP68 && {
            cip68Enabled: true,
            userAssetNameHex,
            refAssetNameHex,
          }),
        },
      };
    },

    // ====================================================================
    // MINT — subsequent mint with RefInput proof
    // ====================================================================
    async mint(params: MintParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, quantity, recipientAddress } = params;
      const recipient = recipientAddress || feePayerAddress;
      const unit = tokenPolicyId + assetName;
      const client = ctx.client;

      if (tokenPolicyId !== scripts.tokenPolicyId) {
        throw new Error(`Token policy ${tokenPolicyId} does not match this FES instance (${scripts.tokenPolicyId})`);
      }

      // 1. Find registry node as RefInput proof
      const registrySpendAddr = scriptAddress(networkId, ctx.standardScripts.registrySpend.hash);
      const registryUtxos = await client.getUtxos(EvoAddress.fromBech32(registrySpendAddr));
      const registryUtxo = findRegistryNode(registryUtxos, tokenPolicyId);
      if (!registryUtxo) throw new Error(`Registry node not found for ${tokenPolicyId}`);

      // 2. Sort reference inputs
      const regRef = utxoToTxInput(registryUtxo);
      const sortedRefInputs = sortTxInputs([regRef]);
      const registryRefIdx = findRefInputIndex(sortedRefInputs, regRef);

      // 3. Build redeemers
      const issuanceRedeemer = issuanceRedeemerRefInput(scripts.issuerAdmin.hash, registryRefIdx);
      const tokenDatum = voidData();

      // 4. Build PLB address
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;
      const recipientPlbAddr = baseAddress(networkId, plbHash, recipient);

      // 5. Get wallet UTxOs
      const walletUtxos = await client.getUtxos(EvoAddress.fromBech32(feePayerAddress));

      // 6. Build transaction
      const tokenAssets = mintAssetsFromMap(new Map([[unit, quantity]]));

      let tx = client.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(scripts.issuerAdmin.hash, "hex"))),
        amount: 0n,
        redeemer: voidData(),
      });
      tx = tx.mintAssets({ assets: tokenAssets, redeemer: issuanceRedeemer });
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(recipientPlbAddr),
        assets: outputAssets(1_300_000n, new Map([[unit, quantity]])),
        datum: new InlineDatum.InlineDatum({ data: tokenDatum }),
      });
      tx = tx.readFrom({ referenceInputs: [registryUtxo] });
      tx = tx.attachScript({ script: buildEvoScript(scripts.issuerAdmin.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.issuanceMint.compiledCode) });
      tx = tx.addSigner({ keyHash: KeyHash.fromHex(config.deployment.adminPkh) });

      const { cbor, txHash } = await buildAndSerialize(tx, feePayerAddress, walletUtxos);
      return { cbor, txHash, tokenPolicyId };
    },

    // ====================================================================
    // BURN
    // ====================================================================
    async burn(params: BurnParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, utxoTxHash: targetTxHash, utxoOutputIndex: targetIdx } = params;
      const holder = params.holderAddress || feePayerAddress;
      const unit = tokenPolicyId + assetName;
      const client = ctx.client;

      if (tokenPolicyId !== scripts.tokenPolicyId) {
        throw new Error(`Token policy ${tokenPolicyId} does not match this FES instance`);
      }

      // 1. Find UTxO to burn at the holder's PLB address
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;
      const holderPlbAddr = baseAddress(networkId, plbHash, holder);
      const allUtxos = await client.getUtxos(EvoAddress.fromBech32(holderPlbAddr));
      const utxoToBurn = allUtxos.find(u =>
        utxoTxHash(u) === targetTxHash && utxoOutputIndex(u) === targetIdx
      );
      if (!utxoToBurn) throw new Error(`UTxO ${targetTxHash}#${targetIdx} not found`);

      const burnAmount = utxoUnitQty(utxoToBurn, unit);
      if (burnAmount <= 0n) throw new Error(`No tokens of ${unit} in UTxO`);

      // 2. Find reference inputs
      const protocolParamsUtxo = await findProtocolParamsUtxo(client, networkId, ctx.deployment);
      const registrySpendAddr = scriptAddress(networkId, ctx.standardScripts.registrySpend.hash);
      const registryUtxos = await client.getUtxos(EvoAddress.fromBech32(registrySpendAddr));
      const registryUtxo = findRegistryNode(registryUtxos, tokenPolicyId);
      if (!registryUtxo) throw new Error(`Registry node not found for ${tokenPolicyId}`);

      // 3. Sort reference inputs
      const allRefInputRefs = [utxoToTxInput(protocolParamsUtxo), utxoToTxInput(registryUtxo)];
      const sortedRefInputs = sortTxInputs(allRefInputRefs);
      const registryIdx = findRefInputIndex(sortedRefInputs, utxoToTxInput(registryUtxo));

      // 4. Build redeemers
      const issuanceRedeemer = issuanceRedeemerRefInput(scripts.issuerAdmin.hash, registryIdx);
      const plgRedeemer = thirdPartyActRedeemer(registryIdx, 0);
      const tokenDatum = voidData();

      // 5. Compute remaining assets (remove burned token's policy)
      const remainingTokens = new Map<string, bigint>();
      const allUnits = Assets.getUnits(utxoToBurn.assets);
      for (const u of allUnits) {
        if (u === "lovelace" || u === "") continue;
        if (u.startsWith(tokenPolicyId)) continue;
        const qty = Assets.getByUnit(utxoToBurn.assets, u);
        if (qty > 0n) remainingTokens.set(u, qty);
      }

      // 6. Build burn assets
      const burnAssets = mintAssetsFromMap(new Map([[unit, -burnAmount]]));

      // 7. Get wallet UTxOs
      const walletUtxos = await client.getUtxos(EvoAddress.fromBech32(feePayerAddress));

      // 8. Build transaction
      let tx = client.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.collectFrom({ inputs: [utxoToBurn], redeemer: voidData() });
      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(scripts.issuerAdmin.hash, "hex"))),
        amount: 0n,
        redeemer: voidData(),
      });
      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(ctx.standardScripts.programmableLogicGlobal.hash, "hex"))),
        amount: 0n,
        redeemer: plgRedeemer,
      });
      tx = tx.payToAddress({
        address: utxoToBurn.address,
        assets: outputAssets(utxoLovelace(utxoToBurn), remainingTokens.size > 0 ? remainingTokens : undefined),
        datum: new InlineDatum.InlineDatum({ data: tokenDatum }),
      });
      tx = tx.mintAssets({ assets: burnAssets, redeemer: issuanceRedeemer });
      tx = tx.readFrom({ referenceInputs: [protocolParamsUtxo, registryUtxo] });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.programmableLogicBase.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.programmableLogicGlobal.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.issuerAdmin.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.issuanceMint.compiledCode) });
      tx = tx.addSigner({ keyHash: KeyHash.fromHex(config.deployment.adminPkh) });

      const { cbor, txHash } = await buildAndSerialize(tx, feePayerAddress, walletUtxos);
      return { cbor, txHash };
    },

    // ====================================================================
    // TRANSFER
    // ====================================================================
    async transfer(params: TransferParams): Promise<UnsignedTx> {
      const { senderAddress, recipientAddress, tokenPolicyId, assetName, quantity } = params;
      const unit = tokenPolicyId + assetName;
      const client = ctx.client;

      if (tokenPolicyId !== scripts.tokenPolicyId) {
        throw new Error(`Token policy ${tokenPolicyId} does not match this FES instance (${scripts.tokenPolicyId})`);
      }

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
      if (!registryUtxo) throw new Error(`Registry node not found for ${tokenPolicyId}`);

      // 5. Find protocol params reference input
      const protocolParamsUtxo = await findProtocolParamsUtxo(client, networkId, ctx.deployment);

      // 6. Find blacklist non-membership proofs
      const senderStakingHash = stakingCredentialHash(senderAddress);
      const blacklistSpendAddr = scriptAddress(networkId, scripts.blacklistSpend.hash);
      const blacklistUtxos = await client.getUtxos(EvoAddress.fromBech32(blacklistSpendAddr));

      const proofUtxos: EvoUTxO.UTxO[] = [];
      for (const _inputUtxo of selected) {
        const proofUtxo = findBlacklistCoveringNode(blacklistUtxos, senderStakingHash);
        if (!proofUtxo) {
          throw new Error(`Sender ${senderStakingHash} is blacklisted — transfer denied`);
        }
        if (!proofUtxos.some(p =>
          utxoTxHash(p) === utxoTxHash(proofUtxo) && utxoOutputIndex(p) === utxoOutputIndex(proofUtxo)
        )) {
          proofUtxos.push(proofUtxo);
        }
      }

      // 7. Sort ALL reference inputs
      const allRefInputRefs = [
        ...proofUtxos.map(utxoToTxInput),
        utxoToTxInput(protocolParamsUtxo),
        utxoToTxInput(registryUtxo),
      ];
      const sortedRefInputs = sortTxInputs(allRefInputRefs);

      const proofIndices: number[] = selected.map(() =>
        findRefInputIndex(sortedRefInputs, utxoToTxInput(proofUtxos[0]))
      );

      const registryIdx = findRefInputIndex(sortedRefInputs, utxoToTxInput(registryUtxo));

      // 8. Get sender's wallet UTxOs
      const senderWalletUtxos = await client.getUtxos(EvoAddress.fromBech32(senderAddress));

      // 9. Build redeemers
      const fesTransferRedeemer = Data.list(
        proofIndices.map((idx) => Data.constr(0n, [Data.int(BigInt(idx))]))
      );
      const plgRedeemer = transferActRedeemer([{ type: "exists", nodeIdx: registryIdx }]);
      const spendRdmr = voidData();
      const tokenDatum = voidData();

      // 10. Build transaction
      let tx = client.newTx();

      tx = tx.collectFrom({ inputs: selected, redeemer: spendRdmr });

      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(ctx.standardScripts.programmableLogicGlobal.hash, "hex"))),
        amount: 0n,
        redeemer: plgRedeemer,
      });

      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(scripts.transfer.hash, "hex"))),
        amount: 0n,
        redeemer: fesTransferRedeemer,
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

      tx = tx.readFrom({ referenceInputs: [...proofUtxos, protocolParamsUtxo, registryUtxo] });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.programmableLogicBase.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.programmableLogicGlobal.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.transfer.compiledCode) });

      tx = tx.addSigner({ keyHash: KeyHash.fromHex(senderStakingHash) });

      const { cbor, txHash } = await buildAndSerialize(tx, senderAddress, senderWalletUtxos);
      return { cbor, txHash };
    },

    // ====================================================================
    // INIT COMPLIANCE — initialize blacklist
    // ====================================================================
    async initCompliance(params: InitComplianceParams): Promise<UnsignedTx> {
      const { feePayerAddress, adminAddress, assetName } = params;
      const client = ctx.client;

      // 1. Build blacklist origin node
      const originDatum = blacklistNodeDatum("", MAX_NEXT);

      // 2. Compute addresses
      const blacklistSpendAddr = scriptAddress(networkId, scripts.blacklistSpend.hash);

      // 3. Build blacklist origin NFT
      const blacklistOriginUnit = scripts.blacklistMint.hash + "";
      const blacklistOriginAssets = mintAssetsFromMap(new Map([[blacklistOriginUnit, 1n]]));

      // 4. Get the bootstrap UTxO (must be consumed for one-shot minting policy)
      let bootstrapUtxos: EvoUTxO.UTxO[];
      if (params.bootstrapUtxo) {
        bootstrapUtxos = [params.bootstrapUtxo as EvoUTxO.UTxO];
      } else {
        const { blacklistInitTxInput } = config.deployment;
        bootstrapUtxos = await client.getUtxosByOutRef([
          new EvoTransactionInput.TransactionInput({
            transactionId: EvoTransactionHash.fromHex(blacklistInitTxInput.txHash),
            index: BigInt(blacklistInitTxInput.outputIndex),
          }),
        ]);
      }
      if (bootstrapUtxos.length === 0) throw new Error("Bootstrap UTxO not found on-chain");

      // 5. Build transaction
      let tx = client.newTx();

      // Must consume bootstrap UTxO (one-shot check in blacklist mint validator)
      tx = tx.collectFrom({ inputs: bootstrapUtxos });

      tx = tx.mintAssets({ assets: blacklistOriginAssets, redeemer: blacklistInitRedeemer() });

      // Output: chain output (40 ADA for next tx)
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(feePayerAddress),
        assets: outputAssets(40_000_000n),
      });

      // Output: blacklist origin node
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(blacklistSpendAddr),
        assets: outputAssets(1_300_000n, new Map([[blacklistOriginUnit, 1n]])),
        datum: new InlineDatum.InlineDatum({ data: originDatum }),
      });

      // Register stake addresses only if not already registered on-chain.
      // Check via backend API (reliable, unlike Blockfrost getDelegation).
      const stakeScripts = [
        { hash: scripts.issuerAdmin.hash, code: scripts.issuerAdmin.compiledCode },
        { hash: scripts.transfer.hash, code: scripts.transfer.compiledCode },
      ];
      for (const s of stakeScripts) {
        const stakeAddr = rewardAddress(networkId, s.hash);
        const registered = ctx.checkStakeRegistration
          ? await ctx.checkStakeRegistration(stakeAddr)
          : false; // no callback → assume not registered → register
        console.log(`[CIP-113] Stake ${stakeAddr}: registered=${registered}`);
        if (!registered) {
          tx = tx.registerStake({
            stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(s.hash, "hex"))),
            redeemer: voidData(),
          });
          tx = tx.attachScript({ script: buildEvoScript(s.code) });
        }
      }

      tx = tx.attachScript({ script: buildEvoScript(scripts.blacklistMint.compiledCode) });

      const built = await buildAndSerialize(tx, feePayerAddress);
      return {
        cbor: built.cbor,
        txHash: built.txHash,
        chainAvailable: built.chainAvailable,
        _signBuilder: built._signBuilder,
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
    // ====================================================================
    async freeze(params: FreezeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId: _tokenPolicyId, assetName: _assetName, targetAddress } = params;
      const client = ctx.client;

      const targetStakingHash = stakingCredentialHash(targetAddress);

      const blacklistSpendAddr = scriptAddress(networkId, scripts.blacklistSpend.hash);
      const blacklistUtxos = await client.getUtxos(EvoAddress.fromBech32(blacklistSpendAddr));
      const coveringNode = findBlacklistCoveringNode(blacklistUtxos, targetStakingHash);
      if (!coveringNode) throw new Error(`Cannot find blacklist covering node for ${targetStakingHash} — may already be blacklisted`);

      const coveringDatum = getInlineDatum(coveringNode);
      const coveringKey = extractConstrBytesField(coveringDatum, 0) ?? "";
      const coveringNext = extractConstrBytesField(coveringDatum, 1) ?? MAX_NEXT;

      const updatedCoveringDatum = blacklistNodeDatum(coveringKey, targetStakingHash);
      const newNodeDatum = blacklistNodeDatum(targetStakingHash, coveringNext);

      const nftUnit = scripts.blacklistMint.hash + targetStakingHash;
      const nftAssets = mintAssetsFromMap(new Map([[nftUnit, 1n]]));

      const walletUtxos = await client.getUtxos(EvoAddress.fromBech32(feePayerAddress));

      let tx = client.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.collectFrom({ inputs: [coveringNode], redeemer: voidData() });

      tx = tx.mintAssets({ assets: nftAssets, redeemer: blacklistAddRedeemer(targetStakingHash) });

      // Output 0: updated covering node
      const coveringNftUnit = findCoveringNodeNftUnit(coveringNode, scripts.blacklistMint.hash);
      const coveringTokenMap = new Map<string, bigint>();
      if (coveringNftUnit) coveringTokenMap.set(coveringNftUnit, 1n);
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(blacklistSpendAddr),
        assets: outputAssets(utxoLovelace(coveringNode), coveringTokenMap),
        datum: new InlineDatum.InlineDatum({ data: updatedCoveringDatum }),
      });

      // Output 1: new blacklist node
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(blacklistSpendAddr),
        assets: outputAssets(2_000_000n, new Map([[nftUnit, 1n]])),
        datum: new InlineDatum.InlineDatum({ data: newNodeDatum }),
      });

      tx = tx.attachScript({ script: buildEvoScript(scripts.blacklistSpend.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.blacklistMint.compiledCode) });
      const managerPkh = paymentCredentialHash(feePayerAddress);
      tx = tx.addSigner({ keyHash: KeyHash.fromHex(managerPkh) });

      const { cbor, txHash } = await buildAndSerialize(tx, feePayerAddress, walletUtxos);
      return { cbor, txHash };
    },

    // ====================================================================
    // UNFREEZE — remove address from blacklist
    // ====================================================================
    async unfreeze(params: UnfreezeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId: _tokenPolicyId, assetName: _assetName, targetAddress } = params;
      const client = ctx.client;

      const targetStakingHash = stakingCredentialHash(targetAddress);

      const blacklistSpendAddr = scriptAddress(networkId, scripts.blacklistSpend.hash);
      const blacklistUtxos = await client.getUtxos(EvoAddress.fromBech32(blacklistSpendAddr));

      const nodeToRemove = blacklistUtxos.find(u => {
        const datum = getInlineDatum(u);
        return datum ? extractConstrBytesField(datum, 0) === targetStakingHash : false;
      });
      if (!nodeToRemove) throw new Error(`Blacklist node not found for ${targetStakingHash}`);

      const precedingNode = blacklistUtxos.find(u => {
        const datum = getInlineDatum(u);
        return datum ? extractConstrBytesField(datum, 1) === targetStakingHash : false;
      });
      if (!precedingNode) throw new Error(`Preceding blacklist node not found for ${targetStakingHash}`);

      const precedingDatum = getInlineDatum(precedingNode);
      const precedingKey = extractConstrBytesField(precedingDatum, 0) ?? "";
      const removedDatum = getInlineDatum(nodeToRemove);
      const removedNext = extractConstrBytesField(removedDatum, 1) ?? MAX_NEXT;
      const updatedPrecedingDatum = blacklistNodeDatum(precedingKey, removedNext);

      const nftUnit = scripts.blacklistMint.hash + targetStakingHash;
      const burnAssets = mintAssetsFromMap(new Map([[nftUnit, -1n]]));

      const walletUtxos = await client.getUtxos(EvoAddress.fromBech32(feePayerAddress));

      let tx = client.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.collectFrom({ inputs: [nodeToRemove], redeemer: voidData() });
      tx = tx.collectFrom({ inputs: [precedingNode], redeemer: voidData() });

      tx = tx.mintAssets({ assets: burnAssets, redeemer: blacklistRemoveRedeemer(targetStakingHash) });

      // Output: updated preceding node
      const precedingNftUnit = findCoveringNodeNftUnit(precedingNode, scripts.blacklistMint.hash);
      const precedingTokenMap = new Map<string, bigint>();
      if (precedingNftUnit) precedingTokenMap.set(precedingNftUnit, 1n);
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(blacklistSpendAddr),
        assets: outputAssets(utxoLovelace(precedingNode), precedingTokenMap),
        datum: new InlineDatum.InlineDatum({ data: updatedPrecedingDatum }),
      });

      tx = tx.attachScript({ script: buildEvoScript(scripts.blacklistSpend.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.blacklistMint.compiledCode) });
      const managerPkh = paymentCredentialHash(feePayerAddress);
      tx = tx.addSigner({ keyHash: KeyHash.fromHex(managerPkh) });

      const { cbor, txHash } = await buildAndSerialize(tx, feePayerAddress, walletUtxos);
      return { cbor, txHash };
    },

    // ====================================================================
    // SEIZE
    // ====================================================================
    async seize(params: SeizeParams): Promise<UnsignedTx> {
      const { feePayerAddress, tokenPolicyId, assetName, utxoTxHash: targetTxHash, utxoOutputIndex: targetIdx, destinationAddress } = params;
      const unit = tokenPolicyId + assetName;
      const client = ctx.client;

      if (tokenPolicyId !== scripts.tokenPolicyId) {
        throw new Error(`Token policy ${tokenPolicyId} does not match this FES instance`);
      }

      // 1. Find UTxO to seize
      const plbHash = ctx.standardScripts.programmableLogicBase.hash;
      let utxoToSeize: EvoUTxO.UTxO | undefined;

      // Search the holder's PLB address first, then fall back to feePayer and destination
      const searchAddresses: string[] = [];
      if (params.holderAddress) {
        searchAddresses.push(baseAddress(networkId, plbHash, params.holderAddress));
      }
      searchAddresses.push(
        baseAddress(networkId, plbHash, feePayerAddress),
        baseAddress(networkId, plbHash, destinationAddress),
      );
      // Deduplicate
      const uniqueAddresses = [...new Set(searchAddresses)];

      for (const addr of uniqueAddresses) {
        const utxos = await client.getUtxos(EvoAddress.fromBech32(addr));
        utxoToSeize = utxos.find(u =>
          utxoTxHash(u) === targetTxHash && utxoOutputIndex(u) === targetIdx
        );
        if (utxoToSeize) break;
      }

      if (!utxoToSeize) throw new Error(`UTxO ${targetTxHash}#${targetIdx} not found`);

      const seizedAmount = utxoUnitQty(utxoToSeize, unit);
      if (seizedAmount <= 0n) throw new Error(`No tokens of ${unit} in UTxO`);

      // 2. Find reference inputs
      const protocolParamsUtxo = await findProtocolParamsUtxo(client, networkId, ctx.deployment);
      const registrySpendAddr = scriptAddress(networkId, ctx.standardScripts.registrySpend.hash);
      const registryUtxos = await client.getUtxos(EvoAddress.fromBech32(registrySpendAddr));
      const registryUtxo = findRegistryNode(registryUtxos, tokenPolicyId);
      if (!registryUtxo) throw new Error(`Registry node not found for ${tokenPolicyId}`);

      // 3. Sort reference inputs
      const allRefInputRefs = [utxoToTxInput(protocolParamsUtxo), utxoToTxInput(registryUtxo)];
      const sortedRefInputs = sortTxInputs(allRefInputRefs);
      const registryIdx = findRefInputIndex(sortedRefInputs, utxoToTxInput(registryUtxo));

      // 4. Build redeemers
      const plgRedeemer = thirdPartyActRedeemer(registryIdx, 1);
      const tokenDatum = voidData();

      // 5. Build recipient PLB address
      const recipientPlbAddr = baseAddress(networkId, plbHash, destinationAddress);

      // 6. Compute remaining assets
      const remainingTokens = new Map<string, bigint>();
      const allUnits = Assets.getUnits(utxoToSeize.assets);
      for (const u of allUnits) {
        if (u === "lovelace" || u === "" || u === unit) continue;
        const qty = Assets.getByUnit(utxoToSeize.assets, u);
        if (qty > 0n) remainingTokens.set(u, qty);
      }

      // 7. Get wallet UTxOs
      const walletUtxos = await client.getUtxos(EvoAddress.fromBech32(feePayerAddress));

      // 8. Build transaction
      let tx = client.newTx();
      tx = tx.collectFrom({ inputs: walletUtxos.slice(0, 2) });
      tx = tx.collectFrom({ inputs: [utxoToSeize], redeemer: voidData() });

      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(scripts.issuerAdmin.hash, "hex"))),
        amount: 0n,
        redeemer: voidData(),
      });
      tx = tx.withdraw({
        stakeCredential: Credential.makeScriptHash(new Uint8Array(Buffer.from(ctx.standardScripts.programmableLogicGlobal.hash, "hex"))),
        amount: 0n,
        redeemer: plgRedeemer,
      });

      // Output 0: seized tokens to recipient
      tx = tx.payToAddress({
        address: EvoAddress.fromBech32(recipientPlbAddr),
        assets: outputAssets(1_300_000n, new Map([[unit, seizedAmount]])),
        datum: new InlineDatum.InlineDatum({ data: tokenDatum }),
      });

      // Output 1: remaining value to original address
      tx = tx.payToAddress({
        address: utxoToSeize.address,
        assets: outputAssets(utxoLovelace(utxoToSeize), remainingTokens.size > 0 ? remainingTokens : undefined),
        datum: new InlineDatum.InlineDatum({ data: tokenDatum }),
      });

      tx = tx.readFrom({ referenceInputs: [protocolParamsUtxo, registryUtxo] });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.programmableLogicBase.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(ctx.standardScripts.programmableLogicGlobal.compiledCode) });
      tx = tx.attachScript({ script: buildEvoScript(scripts.issuerAdmin.compiledCode) });
      tx = tx.addSigner({ keyHash: KeyHash.fromHex(config.deployment.adminPkh) });

      const { cbor, txHash } = await buildAndSerialize(tx, feePayerAddress, walletUtxos);
      return { cbor, txHash };
    },
  };
}

// Re-export types and utilities
export type { FESDeploymentParams } from "./types.js";
export { createFESScripts } from "./scripts.js";
