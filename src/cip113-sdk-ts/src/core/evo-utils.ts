/**
 * Shared Evolution SDK utility functions.
 *
 * These are used across the SDK to build scripts, addresses, datums, and
 * perform common conversions. All use Evolution SDK types directly.
 */

import {
  Data,
  Bytes,
  ScriptHash as EvoScriptHash,
  Script,
  UPLC,
  Address as EvoAddress,
  AddressEras,
  BaseAddress,
  EnterpriseAddress,
  RewardAccount,
  Assets,
  Credential,
  InlineDatum,
  KeyHash,
  TransactionHash,
  UTxO as EvoUTxO,
  Transaction,
} from "@evolution-sdk/evolution";

import { PlutusV3 } from "@evolution-sdk/evolution/PlutusV3";
import * as Label from "@evolution-sdk/evolution/Assets/Label";

import type { HexString, PlutusScript, ScriptHash, TxInput } from "../types.js";

// ---------------------------------------------------------------------------
// Script building
// ---------------------------------------------------------------------------

/**
 * Build a PlutusV3 script object from compiled code hex.
 *
 * Handles CBOR encoding levels: if "double" (from applyParamsToScript),
 * strips outer CBOR header to get single-CBOR for PlutusV3.
 */
export function buildEvoScript(compiledCode: HexString): Script.Script {
  const level = UPLC.getCborEncodingLevel(compiledCode);

  if (level === "double") {
    const raw = Bytes.fromHex(compiledCode);
    const additionalInfo = raw[0] & 0x1f;
    const headerLen = additionalInfo < 24 ? 1 : additionalInfo === 24 ? 2 : additionalInfo === 25 ? 3 : 5;
    const innerBytes = raw.slice(headerLen);
    return new PlutusV3({ bytes: innerBytes }) as unknown as Script.Script;
  }

  return new PlutusV3({ bytes: Bytes.fromHex(compiledCode) }) as unknown as Script.Script;
}

/**
 * Parameterize a script and compute its hash.
 * Returns a PlutusScript with compiledCode and hash.
 */
export function parameterizeScript(
  compiledCode: HexString,
  params: Data.Data[]
): PlutusScript {
  const parameterized = UPLC.applyParamsToScript(compiledCode, params);
  const script = buildEvoScript(parameterized);
  const hash = EvoScriptHash.toHex(EvoScriptHash.fromScript(script));
  return { type: "PlutusV3", compiledCode: parameterized, hash };
}

/**
 * Compute script hash from compiled code.
 */
export function computeScriptHash(compiledCode: HexString): ScriptHash {
  const script = buildEvoScript(compiledCode);
  return EvoScriptHash.toHex(EvoScriptHash.fromScript(script));
}

// ---------------------------------------------------------------------------
// Address building
// ---------------------------------------------------------------------------

/**
 * Build an enterprise (script-only) address from a script hash.
 */
export function scriptAddress(networkId: number, scriptHash: ScriptHash): string {
  const cred = new EvoScriptHash.ScriptHash({ hash: Bytes.fromHex(scriptHash) });
  const addr = new EnterpriseAddress.EnterpriseAddress({ networkId, paymentCredential: cred });
  return AddressEras.toBech32(addr);
}

/**
 * Build a reward (staking) address from a script hash.
 */
export function rewardAddress(networkId: number, scriptHash: ScriptHash): string {
  const cred = new EvoScriptHash.ScriptHash({ hash: Bytes.fromHex(scriptHash) });
  const addr = new RewardAccount.RewardAccount({ networkId, stakeCredential: cred });
  return AddressEras.toBech32(addr);
}

/**
 * Build a base address with script payment credential and user's staking credential.
 */
export function baseAddress(networkId: number, scriptHash: ScriptHash, userAddress: string): string {
  const stakingHash = stakingCredentialHash(userAddress);
  const addr = new BaseAddress.BaseAddress({
    networkId,
    paymentCredential: new EvoScriptHash.ScriptHash({ hash: Bytes.fromHex(scriptHash) }),
    stakeCredential: new KeyHash.KeyHash({ hash: Bytes.fromHex(stakingHash) }),
  });
  return AddressEras.toBech32(addr);
}

/**
 * Extract the staking credential hash from a bech32 address.
 */
export function stakingCredentialHash(address: string): HexString {
  const evoAddr = EvoAddress.fromBech32(address);
  const ba = BaseAddress.fromHex(EvoAddress.toHex(evoAddr));
  return Bytes.toHex(ba.stakeCredential.hash);
}

/**
 * Extract the payment credential hash from a bech32 address.
 */
export function paymentCredentialHash(address: string): HexString {
  const evoAddr = EvoAddress.fromBech32(address);
  const ba = BaseAddress.fromHex(EvoAddress.toHex(evoAddr));
  return Bytes.toHex(ba.paymentCredential.hash);
}

// ---------------------------------------------------------------------------
// Data construction helpers (Cardano-specific)
// ---------------------------------------------------------------------------

/** OutputReference: Constr(0, [txHash, outputIndex]) */
export function outputReference(ref: TxInput): Data.Data {
  return Data.constr(0n, [
    Data.bytearray(ref.txHash),
    Data.int(BigInt(ref.outputIndex)),
  ]);
}

/** Script credential: Constr(1, [scriptHash]) */
export function scriptCredential(hash: ScriptHash): Data.Data {
  return Data.constr(1n, [Data.bytearray(hash)]);
}

/** Verification key credential: Constr(0, [keyHash]) */
export function keyCredential(hash: HexString): Data.Data {
  return Data.constr(0n, [Data.bytearray(hash)]);
}

/** Void / unit: Constr(0, []) */
export function voidData(): Data.Data {
  return Data.constr(0n, []);
}

// ---------------------------------------------------------------------------
// Datum parsing (from on-chain Evolution SDK UTxO datums)
// ---------------------------------------------------------------------------

/**
 * Extract a bytes field from a Constr datum at a given index.
 * Works with Evolution SDK's Data.Constr format.
 */
export function extractConstrBytesField(datum: unknown, fieldIndex: number): string | undefined {
  if (!datum || typeof datum !== "object") return undefined;

  // Evolution SDK Constr: check with Data.isConstr
  if (Data.isConstr(datum as Data.Data)) {
    const constr = datum as unknown as { index: bigint; fields: readonly Data.Data[] };
    const field = constr.fields[fieldIndex];
    if (field == null) return undefined;

    if (Data.isBytes(field)) {
      return Bytes.toHex(field as unknown as Uint8Array);
    }
    return undefined;
  }

  return undefined;
}

/**
 * Extract a credential (type + hash) from a constr datum field.
 * Credential is Constr(0|1, [bytes]) — 0 = key, 1 = script.
 */
export function extractCredentialField(
  datum: unknown,
  fieldIndex: number
): { type: "key" | "script"; hash: string } | undefined {
  if (!datum || typeof datum !== "object") return undefined;

  if (Data.isConstr(datum as Data.Data)) {
    const constr = datum as unknown as { index: bigint; fields: readonly Data.Data[] };
    const field = constr.fields[fieldIndex];
    if (!field || !Data.isConstr(field)) return undefined;

    const credConstr = field as unknown as { index: bigint; fields: readonly Data.Data[] };
    const type = credConstr.index === 0n ? "key" as const : "script" as const;
    const inner = credConstr.fields[0];
    if (!inner) return { type, hash: "" };

    if (Data.isBytes(inner)) {
      return { type, hash: Bytes.toHex(inner as unknown as Uint8Array) };
    }
    return { type, hash: "" };
  }

  return undefined;
}

// ---------------------------------------------------------------------------
// Datum builders (CIP-113 domain types)
// ---------------------------------------------------------------------------

export interface RegistryNodeData {
  key: HexString;
  next: HexString;
  transferLogicScript: { type: "key" | "script"; hash: ScriptHash };
  thirdPartyTransferLogicScript: { type: "key" | "script"; hash: ScriptHash };
  globalStateCs: HexString;
}

/** Build a RegistryNode datum */
export function registryNodeDatum(node: RegistryNodeData): Data.Data {
  const credToData = (cred: { type: "key" | "script"; hash: ScriptHash }) =>
    cred.type === "script"
      ? scriptCredential(cred.hash)
      : keyCredential(cred.hash);

  return Data.constr(0n, [
    Data.bytearray(node.key),
    Data.bytearray(node.next),
    credToData(node.transferLogicScript),
    credToData(node.thirdPartyTransferLogicScript),
    Data.bytearray(node.globalStateCs),
  ]);
}

/** Build a BlacklistNode datum */
export function blacklistNodeDatum(key: HexString, next: HexString): Data.Data {
  return Data.constr(0n, [Data.bytearray(key), Data.bytearray(next)]);
}

// ---------------------------------------------------------------------------
// Redeemer builders (CIP-113 validators)
// ---------------------------------------------------------------------------

/**
 * SmartTokenMintingAction redeemer for first mint (OutputIndex).
 */
export function issuanceRedeemerFirstMint(
  mintingLogicHash: ScriptHash,
  registryOutputIndex: number
): Data.Data {
  return Data.constr(0n, [
    scriptCredential(mintingLogicHash),
    Data.constr(1n, [Data.int(BigInt(registryOutputIndex))]),
  ]);
}

/**
 * SmartTokenMintingAction redeemer for subsequent mint/burn (RefInput).
 */
export function issuanceRedeemerRefInput(
  mintingLogicHash: ScriptHash,
  registryRefInputIndex: number
): Data.Data {
  return Data.constr(0n, [
    scriptCredential(mintingLogicHash),
    Data.constr(0n, [Data.int(BigInt(registryRefInputIndex))]),
  ]);
}

export interface RegistryProof {
  type: "exists" | "not-exists";
  nodeIdx: number;
}

/** Build a TransferAct redeemer for PLGlobal. */
export function transferActRedeemer(proofs: RegistryProof[]): Data.Data {
  return Data.constr(0n, [
    Data.list(
      proofs.map((p) =>
        p.type === "exists"
          ? Data.constr(0n, [Data.int(BigInt(p.nodeIdx))])
          : Data.constr(1n, [Data.int(BigInt(p.nodeIdx))])
      )
    ),
  ]);
}

/** Build a ThirdPartyAct redeemer for PLGlobal. */
export function thirdPartyActRedeemer(
  registryNodeIdx: number,
  outputsStartIdx: number
): Data.Data {
  return Data.constr(1n, [
    Data.int(BigInt(registryNodeIdx)),
    Data.int(BigInt(outputsStartIdx)),
  ]);
}

/** RegistryInsert redeemer */
export function registryInsertRedeemer(key: HexString, hashedParam: HexString): Data.Data {
  return Data.constr(1n, [Data.bytearray(key), Data.bytearray(hashedParam)]);
}

/** Blacklist init (constructor 0) */
export function blacklistInitRedeemer(): Data.Data {
  return Data.constr(0n, []);
}

/** Blacklist add (constructor 1) */
export function blacklistAddRedeemer(stakingPkh: HexString): Data.Data {
  return Data.constr(1n, [Data.bytearray(stakingPkh)]);
}

/** Blacklist remove (constructor 2) */
export function blacklistRemoveRedeemer(stakingPkh: HexString): Data.Data {
  return Data.constr(2n, [Data.bytearray(stakingPkh)]);
}

// ---------------------------------------------------------------------------
// Asset helpers
// ---------------------------------------------------------------------------

/** Build an Assets object with a single native token unit + min lovelace */
export function singleTokenAssets(policyId: string, assetName: string, qty: bigint): Assets.Assets {
  let assets = Assets.fromLovelace(0n);
  assets = Assets.addByHex(assets, policyId, assetName, qty);
  return Assets.withoutLovelace(assets);
}

/** Build mint assets map from unit -> qty entries (Evolution SDK format) */
export function mintAssetsFromMap(entries: Map<string, bigint>): Assets.Assets {
  let assets = Assets.fromLovelace(0n);
  for (const [unit, qty] of entries) {
    const policyId = unit.slice(0, 56);
    const assetName = unit.slice(56);
    assets = Assets.addByHex(assets, policyId, assetName, qty);
  }
  return Assets.withoutLovelace(assets);
}

/** Build output assets: lovelace + optional token map */
export function outputAssets(lovelace: bigint, tokenMap?: Map<string, bigint>): Assets.Assets {
  let assets = Assets.fromLovelace(lovelace);
  if (tokenMap) {
    for (const [unit, qty] of tokenMap) {
      const policyId = unit.slice(0, 56);
      const assetName = unit.slice(56);
      assets = Assets.addByHex(assets, policyId, assetName, qty);
    }
  }
  return assets;
}

// ---------------------------------------------------------------------------
// UTxO datum extraction
// ---------------------------------------------------------------------------

/**
 * Get the inline datum from a UTxO. Returns undefined if no inline datum.
 */
export function getInlineDatum(utxo: EvoUTxO.UTxO): Data.Data | undefined {
  const datumOpt = (utxo as any).datumOption;
  if (datumOpt?._tag === "InlineDatum" && datumOpt.data != null) {
    return datumOpt.data as Data.Data;
  }
  return undefined;
}

/**
 * Get the UTxO's value as a check for a specific unit.
 */
export function utxoHasUnit(utxo: EvoUTxO.UTxO, unit: string): boolean {
  try {
    const qty = Assets.getByUnit(utxo.assets, unit);
    return qty > 0n;
  } catch {
    return false;
  }
}

/**
 * Get the quantity of a specific unit in a UTxO.
 */
export function utxoUnitQty(utxo: EvoUTxO.UTxO, unit: string): bigint {
  try {
    return Assets.getByUnit(utxo.assets, unit);
  } catch {
    return 0n;
  }
}

/**
 * Get the lovelace amount from a UTxO.
 */
export function utxoLovelace(utxo: EvoUTxO.UTxO): bigint {
  return Assets.lovelaceOf(utxo.assets);
}

/**
 * Get the txHash of a UTxO as a hex string.
 */
export function utxoTxHash(utxo: EvoUTxO.UTxO): string {
  return TransactionHash.toHex(utxo.transactionId);
}

/**
 * Get the output index of a UTxO as a number.
 */
export function utxoOutputIndex(utxo: EvoUTxO.UTxO): number {
  return Number(utxo.index);
}

/**
 * Get the bech32 address of a UTxO.
 */
export function utxoAddress(utxo: EvoUTxO.UTxO): string {
  return EvoAddress.toBech32(utxo.address);
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Max next pointer for linked list sentinel (30 bytes, matches Aiken #"ff"*30) */
export const MAX_NEXT = "ff".repeat(30);

/** Convert a UTF-8 string to hex */
export function stringToHex(str: string): string {
  return Buffer.from(str, "utf-8").toString("hex");
}

// ---------------------------------------------------------------------------
// CIP-68 / CIP-67 helpers
// ---------------------------------------------------------------------------

import type { CIP68MetadataInput } from "../substandards/interface.js";

/** Prefix an asset name hex with a CIP-67 label (e.g., 333 → "000f4141" + assetNameHex). */
export function labeledAssetName(label: number, assetNameHex: HexString): HexString {
  return Label.toLabel(label) + assetNameHex;
}

/**
 * Build CIP-68 FT metadata datum: Constr(0, [metadata_map, version, extra]).
 *
 * Keys and text values are byte strings (standard CIP-68 convention).
 * Matches real-world CIP-68 FT datums (e.g., FLDT token).
 */
export function buildCIP68FTDatum(meta: CIP68MetadataInput): Data.Data {
  const entries: Array<[Data.Data, Data.Data]> = [];

  entries.push([Data.bytearray(stringToHex("name")), Data.bytearray(stringToHex(meta.name))]);

  if (meta.description) {
    entries.push([Data.bytearray(stringToHex("description")), Data.bytearray(stringToHex(meta.description))]);
  }
  if (meta.ticker) {
    entries.push([Data.bytearray(stringToHex("ticker")), Data.bytearray(stringToHex(meta.ticker))]);
  }
  if (meta.decimals !== undefined) {
    entries.push([Data.bytearray(stringToHex("decimals")), Data.int(BigInt(meta.decimals))]);
  }
  if (meta.url) {
    entries.push([Data.bytearray(stringToHex("url")), Data.bytearray(stringToHex(meta.url))]);
  }
  if (meta.logo) {
    entries.push([Data.bytearray(stringToHex("logo")), Data.bytearray(stringToHex(meta.logo))]);
  }

  return Data.constr(0n, [
    Data.map(entries),
    Data.int(1n),       // version
    Data.int(1n),       // extra (matches real-world CIP-68 datums)
  ]);
}

// ---------------------------------------------------------------------------
// Re-exports for convenience
// ---------------------------------------------------------------------------

export {
  Data,
  Bytes,
  Assets,
  Credential,
  InlineDatum,
  KeyHash,
  EvoAddress,
  EvoScriptHash,
  TransactionHash,
  Transaction,
  UPLC,
};
