/**
 * Evolution SDK adapter.
 *
 * Implements CIP113Adapter by delegating to @evolution-sdk/evolution.
 * This is the ONLY file in the SDK that imports Evolution SDK directly.
 */

import {
  client as evoClient,
  Data,
  Bytes,
  ScriptHash as EvoScriptHash,
  Script,
  UPLC,
  Address as EvoAddress,
  AddressEras,
  BaseAddress,
  Assets,
  Credential,
  InlineDatum,
  KeyHash,
  UTxO as EvoUTxO,
  TransactionHash,
  RewardAccount,
  EnterpriseAddress,
} from "@evolution-sdk/evolution";

// Import Chain presets for proper network context
import {
  mainnet as mainnetChain,
  preprod as preprodChain,
  preview as previewChain,
} from "@evolution-sdk/evolution/sdk/client/Chain";

// Import PlutusV3 class for proper script construction
import { PlutusV3 } from "@evolution-sdk/evolution/PlutusV3";

import type {
  CIP113Adapter,
  BuiltTx,
  TxPlan,
  ProtocolParameters,
  PayToAddressParams,
  CollectFromParams,
  MintAssetsParams,
  ReadFromParams,
  WithdrawParams,
  RegisterStakeParams,
  AttachScriptParams,
  AddSignerParams,
  ValidityParams,
} from "./interface.js";

import type {
  Address,
  HexString,
  Network,
  PlutusData,
  ScriptHash,
  TxHash,
  UTxO,
  Value,
} from "../types.js";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

export interface EvolutionAdapterConfig {
  network: Network;
  provider:
    | { type: "blockfrost"; projectId: string; baseUrl?: string }
    | { type: "maestro"; apiKey: string; baseUrl?: string }
    | { type: "koios"; baseUrl?: string };
  wallet?: {
    type: "seed";
    mnemonic: string;
    accountIndex?: number;
  };
}

// ---------------------------------------------------------------------------
// Internal helpers: CIP113 <-> Evolution type conversions
// ---------------------------------------------------------------------------

/** Map our network type to Evolution SDK chain name */
function toEvoChain(network: Network) {
  switch (network) {
    case "preview":
      return "Preview" as const;
    case "preprod":
      return "Preprod" as const;
    case "mainnet":
      return "Mainnet" as const;
  }
}

/**
 * Convert a CIP113 adapter-agnostic PlutusData object (from core/datums.ts)
 * to Evolution SDK's Data representation.
 *
 * Our Data module produces plain JS objects:
 *   { constr: number, fields: unknown[] }
 *   { bytes: string }
 *   { int: bigint }
 *   { list: unknown[] }
 *   { map: [unknown, unknown][] }
 */
function toEvoData(d: unknown): Data.Data {
  if (d == null) {
    throw new Error("Cannot convert null/undefined to Evolution Data");
  }

  const obj = d as Record<string, unknown>;

  if ("constr" in obj && "fields" in obj) {
    return Data.constr(
      BigInt(obj.constr as number),
      (obj.fields as unknown[]).map(toEvoData)
    );
  }
  if ("bytes" in obj) {
    return Data.bytearray(obj.bytes as string);
  }
  if ("int" in obj) {
    return Data.int(BigInt(obj.int as bigint));
  }
  if ("list" in obj) {
    return Data.list((obj.list as unknown[]).map(toEvoData));
  }
  if ("map" in obj) {
    return Data.map(
      (obj.map as [unknown, unknown][]).map(
        ([k, v]) => [toEvoData(k), toEvoData(v)] as [Data.Data, Data.Data]
      )
    );
  }

  throw new Error(`Unknown PlutusData shape: ${JSON.stringify(d)}`);
}

/**
 * Build a PlutusV3 script object from compiled code hex.
 *
 * Constructs a PlutusV3 tagged object that satisfies the Script union type.
 * The _tag discriminator and bytes field match the TaggedClass shape that
 * ScriptHash.fromScript and the transaction builder's attachScript expect.
 *
 * We construct the object manually rather than importing PlutusV3 from a
 * subpath, because the subpath export does not resolve type declarations
 * under all moduleResolution settings.
 */
function buildEvoScript(compiledCode: HexString): Script.Script {
  // Blueprint compiledCode is "single" CBOR (one bytestring wrapper).
  // applyParamsToScript output is "double" CBOR (two bytestring wrappers).
  //
  // PlutusV3.bytes must contain the single-CBOR version:
  // - Script.toCBORHex adds one CBOR layer → producing double-CBOR in the witness set
  // - Double-CBOR in the witness set is what Cardano expects on-chain
  //
  // For "double" (applyParamsToScript output): strip the outer CBOR header.
  // For "single"/"none" (blueprint compiledCode): use as-is.
  const level = UPLC.getCborEncodingLevel(compiledCode);

  if (level === "double") {
    // Strip outer CBOR bytestring header to get the inner single-CBOR bytes
    const raw = Bytes.fromHex(compiledCode);
    const additionalInfo = raw[0] & 0x1f;
    const headerLen = additionalInfo < 24 ? 1 : additionalInfo === 24 ? 2 : additionalInfo === 25 ? 3 : 5;
    const innerBytes = raw.slice(headerLen);
    return new PlutusV3({ bytes: innerBytes }) as unknown as Script.Script;
  }

  // "single" or "none": the compiledCode bytes go directly to PlutusV3
  return new PlutusV3({ bytes: Bytes.fromHex(compiledCode) }) as unknown as Script.Script;
}

/** Convert a CIP113 Value to Evolution Assets */
function toEvoAssets(value: Value): Assets.Assets {
  let assets = Assets.fromLovelace(value.lovelace);
  if (value.assets) {
    for (const [unit, qty] of value.assets) {
      // unit = policyId (56 hex chars) + assetName (remainder)
      const policyId = unit.slice(0, 56);
      const assetName = unit.slice(56);
      assets = Assets.addByHex(assets, policyId, assetName, qty);
    }
  }
  return assets;
}

/**
 * Convert Evolution Assets to CIP113 Value.
 *
 * Evolution Assets exposes:
 *   Assets.lovelaceOf(a) -> bigint
 *   Assets.hasMultiAsset(a) -> boolean
 *   Assets.getUnits(a) -> string[]  (each unit = policyId hex + assetName hex)
 *   Assets.getByUnit(a, unit) -> bigint
 */
function fromEvoAssets(evoAssets: Assets.Assets): Value {
  const lovelace = Assets.lovelaceOf(evoAssets);
  const result: Value = { lovelace };

  if (Assets.hasMultiAsset(evoAssets)) {
    const assetMap = new Map<string, bigint>();
    const units = Assets.getUnits(evoAssets);
    for (const unit of units) {
      if (unit === "lovelace" || unit === "") continue;
      const qty = Assets.getByUnit(evoAssets, unit);
      if (qty !== 0n) {
        assetMap.set(unit, qty);
      }
    }
    if (assetMap.size > 0) {
      result.assets = assetMap;
    }
  }

  return result;
}

/**
 * Convert an Evolution SDK UTxO to CIP113 UTxO.
 *
 * Evolution UTxO fields (from UTxO.d.ts):
 *   transactionId: TransactionHash (tagged class with .hash: string)
 *   index: bigint
 *   address: Address (tagged class with networkId, paymentCredential, etc.)
 *   assets: Assets
 *   datumOption?: InlineDatum | DatumHash
 *   scriptRef?: Script (NativeScript | PlutusV1 | PlutusV2 | PlutusV3)
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function fromEvoUtxo(evoUtxo: any): UTxO {
  // Extract transaction hash using Evolution SDK's TransactionHash.toHex
  let txHash: string;
  if (evoUtxo.transactionId?._tag === "TransactionHash") {
    txHash = TransactionHash.toHex(evoUtxo.transactionId);
  } else if (typeof evoUtxo.transactionId === "string") {
    txHash = evoUtxo.transactionId;
  } else {
    txHash = "";
  }

  const outputIndex = Number(evoUtxo.index ?? 0);

  // Convert address to bech32 string
  let address: string;
  if (typeof evoUtxo.address === "string") {
    address = evoUtxo.address;
  } else {
    try {
      address = EvoAddress.toBech32(evoUtxo.address);
    } catch {
      address = String(evoUtxo.address ?? "");
    }
  }

  // Convert assets to CIP113 Value
  const value = fromEvoAssets(evoUtxo.assets);

  const utxo: UTxO = { txHash, outputIndex, address, value };

  // Preserve the raw Evolution UTxO for pass-through to tx builder
  // This avoids lossy round-trip conversion
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (utxo as any)._evoUtxo = evoUtxo;

  // Extract datum if present
  if (evoUtxo.datumOption != null) {
    const datumOpt = evoUtxo.datumOption;
    if (datumOpt._tag === "InlineDatum" && datumOpt.data != null) {
      // Store the raw Evolution Data -- our PlutusData type is opaque (unknown)
      utxo.datum = datumOpt.data as PlutusData;
    } else if (datumOpt._tag === "DatumHash" && datumOpt.hash != null) {
      utxo.datumHash = String(datumOpt.hash);
    }
  }

  // Extract reference script if present
  if (evoUtxo.scriptRef != null) {
    const ref = evoUtxo.scriptRef;
    if (ref._tag === "PlutusV3") {
      const code = Bytes.toHex(ref.bytes);
      const hash = EvoScriptHash.toHex(
        EvoScriptHash.fromScript(buildEvoScript(code))
      );
      utxo.referenceScript = { type: "PlutusV3", compiledCode: code, hash };
    }
  }

  return utxo;
}

/**
 * Convert a CIP113 UTxO to an Evolution SDK UTxO for use in tx builder.
 *
 * If the UTxO was originally fetched via this adapter, uses the preserved
 * raw Evolution UTxO (avoids lossy round-trip). Otherwise constructs one.
 */
function toEvoUtxo(utxo: UTxO): EvoUTxO.UTxO {
  // Fast path: use preserved raw Evolution UTxO if available
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const raw = (utxo as any)._evoUtxo;
  if (raw instanceof EvoUTxO.UTxO) return raw;

  const evoAddress = EvoAddress.fromBech32(utxo.address);
  const evoAssets = toEvoAssets(utxo.value);

  // Build params for the UTxO constructor
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const params: any = {
    transactionId: new TransactionHash.TransactionHash({
      hash: Bytes.fromHex(utxo.txHash),
    }),
    index: BigInt(utxo.outputIndex),
    address: evoAddress,
    assets: evoAssets,
  };

  if (utxo.datum != null) {
    params.datumOption = new InlineDatum.InlineDatum({
      data: toEvoData(utxo.datum),
    });
  }

  if (utxo.referenceScript != null) {
    params.scriptRef = buildEvoScript(utxo.referenceScript.compiledCode);
  }

  return new EvoUTxO.UTxO(params);
}

// ---------------------------------------------------------------------------
// TxPlan wrapper
// ---------------------------------------------------------------------------

/**
 * Wraps an Evolution SDK transaction builder to implement the CIP113 TxPlan
 * interface. Each method delegates to the underlying builder and returns
 * `this` for chaining.
 */
class EvolutionTxPlan implements TxPlan {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private builder: any;
  private changeAddr?: string;
  private availableUtxos?: EvoUTxO.UTxO[];
  private networkId: number;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  constructor(builder: any, networkId: number) {
    this.builder = builder;
    this.networkId = networkId;
  }

  payToAddress(params: PayToAddressParams): TxPlan {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const payParams: any = {
      address: EvoAddress.fromBech32(params.address),
      assets: toEvoAssets(params.value),
    };

    if (params.datum != null && params.inlineDatum !== false) {
      payParams.datum = new InlineDatum.InlineDatum({
        data: toEvoData(params.datum),
      });
    }

    if (params.referenceScript != null) {
      payParams.script = buildEvoScript(params.referenceScript.compiledCode);
    }

    this.builder = this.builder.payToAddress(payParams);
    return this;
  }

  collectFrom(params: CollectFromParams): TxPlan {
    const inputs = params.inputs.map(toEvoUtxo);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const evoParams: any = { inputs };

    if (params.redeemer != null) {
      evoParams.redeemer = toEvoData(params.redeemer);
    }

    this.builder = this.builder.collectFrom(evoParams);
    return this;
  }

  mintAssets(params: MintAssetsParams): TxPlan {
    // Build Evolution Assets from our Map<unit, qty>
    let assets = Assets.fromLovelace(0n);
    for (const [unit, qty] of params.assets) {
      const policyId = unit.slice(0, 56);
      const assetName = unit.slice(56);
      assets = Assets.addByHex(assets, policyId, assetName, qty);
    }
    // Strip the placeholder lovelace -- mint only affects native tokens
    assets = Assets.withoutLovelace(assets);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const evoParams: any = { assets };
    if (params.redeemer != null) {
      evoParams.redeemer = toEvoData(params.redeemer);
    }

    this.builder = this.builder.mintAssets(evoParams);
    return this;
  }

  readFrom(params: ReadFromParams): TxPlan {
    const referenceInputs = params.referenceInputs.map(toEvoUtxo);
    this.builder = this.builder.readFrom({ referenceInputs });
    return this;
  }

  withdraw(params: WithdrawParams): TxPlan {
    const stakeCredential = Credential.makeScriptHash(
      Bytes.fromHex(params.stakeCredential)
    );

    // Debug: log what we're passing
    console.log("[CIP113 DEBUG] withdraw stakeCredential:", JSON.stringify({
      type: stakeCredential?.constructor?.name ?? typeof stakeCredential,
      _tag: (stakeCredential as any)?._tag,
      hash: (stakeCredential as any)?.hash ? "present" : "missing",
      networkId: this.networkId,
      stakeCredHex: params.stakeCredential,
    }));

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const evoParams: any = {
      stakeCredential,
      amount: params.amount,
    };

    if (params.redeemer != null) {
      evoParams.redeemer = toEvoData(params.redeemer);
    }

    console.log("[CIP113 DEBUG] calling builder.withdraw with:", Object.keys(evoParams));
    try {
      this.builder = this.builder.withdraw(evoParams);
    } catch (e) {
      console.error("[CIP113 DEBUG] builder.withdraw THREW:", e);
      throw e;
    }
    return this;
  }

  registerStake(params: RegisterStakeParams): TxPlan {
    const stakeCredential = Credential.makeScriptHash(
      Bytes.fromHex(params.stakeCredential)
    );
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const evoParams: any = { stakeCredential };
    if (params.redeemer != null) {
      evoParams.redeemer = toEvoData(params.redeemer);
    }
    this.builder = this.builder.registerStake(evoParams);
    return this;
  }

  attachScript(params: AttachScriptParams): TxPlan {
    // PlutusV3 is a valid member of the Script union type
    const script = buildEvoScript(params.script.compiledCode);
    this.builder = this.builder.attachScript({ script });
    return this;
  }

  addSigner(params: AddSignerParams): TxPlan {
    // Evolution expects KeyHash.KeyHash, construct from hex string
    const keyHash = KeyHash.fromHex(params.keyHash);
    this.builder = this.builder.addSigner({ keyHash });
    return this;
  }

  provideUtxos(utxos: UTxO[]): TxPlan {
    this.availableUtxos = utxos.map(toEvoUtxo);
    return this;
  }

  setChangeAddress(address: string): TxPlan {
    this.changeAddr = address;
    return this;
  }

  setValidity(params: ValidityParams): TxPlan {
    // Evolution ValidityParams uses { from?: UnixTime, to?: UnixTime }
    // Both are Unix time in milliseconds, converted to slots internally
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const evoParams: any = {};
    if (params.from != null) evoParams.from = params.from;
    if (params.to != null) evoParams.to = params.to;
    this.builder = this.builder.setValidity(evoParams);
    return this;
  }

  async build(): Promise<BuiltTx> {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const buildOptions: any = {};
    if (this.changeAddr) {
      buildOptions.changeAddress = EvoAddress.fromBech32(this.changeAddr);
    }
    if (this.availableUtxos) {
      buildOptions.availableUtxos = this.availableUtxos;
    }

    // Use buildEither to capture errors without throwing — lets us log the tx
    const either = await this.builder.buildEither(buildOptions);

    // Either is { _tag: "Right", right: result } or { _tag: "Left", left: error }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const eitherAny = either as any;

    if (eitherAny._tag === "Left") {
      const error = eitherAny.left;
      console.error("[CIP113] Transaction build failed:", error?.message ?? error);
      // Log full error cause chain for Blockfrost details
      let cause = error?.cause;
      while (cause) {
        console.error("[CIP113] Caused by:", cause?.message ?? cause);
        // Check for Blockfrost response details
        if (cause?.response) console.error("[CIP113] Response:", JSON.stringify(cause.response)?.slice(0, 500));
        if (cause?.body) console.error("[CIP113] Body:", JSON.stringify(cause.body)?.slice(0, 500));
        if (cause?.details) console.error("[CIP113] Details:", JSON.stringify(cause.details)?.slice(0, 500));
        cause = cause?.cause;
      }

      // DEBUG: Retry with dummy evaluator to extract CBOR for comparison
      try {
        const { Effect } = await import("effect");
        const { Transaction: TxModule } = await import("@evolution-sdk/evolution");
        const debugEither = await this.builder.buildEither({
          ...buildOptions,
          evaluator: {
            evaluate: (tx: any) => {
              // Log the raw tx CBOR
              try { console.log("[CIP113 DEBUG] Pre-eval tx CBOR:", TxModule.toCBORHex(tx)); } catch {}
              // Return dummy redeemers for ALL spend + reward purposes
              const r: any[] = [];
              const eu = { mem: 14000000n, steps: 10000000000n };
              let spendIdx = 0;
              for (const _inp of tx?.body?.inputs ?? []) r.push({ redeemer_tag: "spend", redeemer_index: spendIdx++, ex_units: eu });
              let rewIdx = 0;
              for (const [_k] of tx?.body?.withdrawals ?? new Map()) r.push({ redeemer_tag: "reward", redeemer_index: rewIdx++, ex_units: eu });
              console.log("[CIP113 DEBUG] Dummy evaluator:", r.length, "redeemers");
              return Effect.succeed(r);
            },
          },
        });
        if ((debugEither as any)._tag === "Right") {
          const debugTx = await (debugEither as any).right.toTransaction();
          console.log("[CIP113 DEBUG] Unsigned tx CBOR:", TxModule.toCBORHex(debugTx));
        }
      } catch (e2: any) {
        console.error("[CIP113 DEBUG] Debug build also failed:", e2?.message);
      }

      throw error;
    }

    const result = eitherAny.right;

    // Extract transaction for CBOR serialization
    const { Transaction: TxModule } = await import("@evolution-sdk/evolution");
    const tx = await result.toTransaction();
    const cbor = TxModule.toCBORHex(tx);
    console.log("[CIP113 DEBUG] Unsigned tx CBOR hex:", cbor);

    return {
      toCbor(): HexString {
        return cbor;
      },
      txHash(): TxHash {
        // Transaction hash from the serialized body
        if (typeof result.txHash === "function") return result.txHash();
        // Derive from CBOR if needed
        return "";
      },
    };
  }
}

// ---------------------------------------------------------------------------
// Adapter factory
// ---------------------------------------------------------------------------

/**
 * Create a CIP113Adapter backed by Evolution SDK.
 *
 * The client assembly order follows Evolution SDK's builder pattern:
 *   client(chain) -> .withBlockfrost(config) -> ReadClient -> .withSeed(config) -> SigningClient
 *
 * Usage:
 * ```ts
 * const adapter = evolutionAdapter({
 *   network: 'preprod',
 *   provider: { type: 'blockfrost', projectId: 'preprodXXXXX' },
 *   wallet: { type: 'seed', mnemonic: 'your 24 words ...' },
 * });
 * ```
 */
export function evolutionAdapter(
  config: EvolutionAdapterConfig
): CIP113Adapter {
  const chain = config.network === "mainnet" ? mainnetChain
    : config.network === "preprod" ? preprodChain
    : previewChain;
  const networkId = chain.id;

  // Step 1: Create chain-scoped assembly with proper Chain preset
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let builder: any = evoClient(chain);

  // Step 2: Attach provider (produces ReadClient)
  switch (config.provider.type) {
    case "blockfrost":
      builder = builder.withBlockfrost({
        projectId: config.provider.projectId,
        ...(config.provider.baseUrl
          ? { baseUrl: config.provider.baseUrl }
          : {}),
      });
      break;
    case "maestro":
      builder = builder.withMaestro({
        apiKey: config.provider.apiKey,
        ...(config.provider.baseUrl
          ? { baseUrl: config.provider.baseUrl }
          : {}),
      });
      break;
    case "koios":
      builder = builder.withKoios({
        ...(config.provider.baseUrl
          ? { baseUrl: config.provider.baseUrl }
          : {}),
      });
      break;
  }

  // Step 3: Attach wallet
  if (config.wallet) {
    // Full signing wallet (seed phrase)
    builder = builder.withSeed({
      mnemonic: config.wallet.mnemonic,
      ...(config.wallet.accountIndex != null
        ? { accountIndex: config.wallet.accountIndex }
        : {}),
    });
  } else {
    // Read-only wallet with a dummy address — gives the builder network context
    // (required for withdrawal RewardAccount construction)
    const dummyAddr = networkId === 1
      ? "addr1qx2kd28nq8ac5prwg32hhvudlwggpgfp8utlyqxu6wqgz62f79qsdmm5dsknt9ecr5w468r9ey0fxwkdrwh08ly3tu9sy0f4qd"
      : "addr_test1qzx9hu8j4ah3auytk0mwcupd69hpc52t0cw39a65ndrah86djs784u92a3m5w475w3w35tyd6v3qumkze80j8a6h5tuqq5xe8y";
    builder = builder.withAddress(dummyAddr);
  }

  // The final client: ReadOnlyClient or SigningClient
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const evoClient_: any = builder;

  return {
    // -- CardanoProvider --

    async getUtxos(address: Address): Promise<UTxO[]> {
      const evoAddr = EvoAddress.fromBech32(address);
      const evoUtxos = await evoClient_.getUtxos(evoAddr);
      return (evoUtxos as unknown[]).map(fromEvoUtxo);
    },

    async getUtxosWithUnit(address: Address, unit: string): Promise<UTxO[]> {
      // Fetch all UTxOs and filter client-side by unit
      const all = await this.getUtxos(address);
      return all.filter((utxo) => utxo.value.assets?.has(unit) ?? false);
    },

    async getProtocolParameters(): Promise<ProtocolParameters> {
      const pp = await evoClient_.getProtocolParameters();
      return pp as ProtocolParameters;
    },

    async submitTx(signedTxCbor: HexString): Promise<TxHash> {
      const txHash = await evoClient_.submitTx(signedTxCbor);
      return txHash as TxHash;
    },

    async awaitTx(txHash: TxHash, _timeout?: number): Promise<boolean> {
      if (typeof evoClient_.awaitTx === "function") {
        return evoClient_.awaitTx(txHash) as Promise<boolean>;
      }
      // Evolution SDK may not expose awaitTx -- caller should poll externally
      return true;
    },

    applyParamsToScript(
      compiledCode: HexString,
      params: PlutusData[]
    ): HexString {
      const evoParams = params.map(toEvoData);
      return UPLC.applyParamsToScript(compiledCode, evoParams);
    },

    scriptHash(compiledCode: HexString): ScriptHash {
      const script = buildEvoScript(compiledCode);
      const hash = EvoScriptHash.fromScript(script);
      return EvoScriptHash.toHex(hash);
    },

    scriptAddress(scriptHash: ScriptHash): Address {
      const cred = new EvoScriptHash.ScriptHash({ hash: Bytes.fromHex(scriptHash) });
      const addr = new EnterpriseAddress.EnterpriseAddress({ networkId, paymentCredential: cred });
      return AddressEras.toBech32(addr);
    },

    rewardAddress(scriptHash: ScriptHash): Address {
      const cred = new EvoScriptHash.ScriptHash({ hash: Bytes.fromHex(scriptHash) });
      const addr = new RewardAccount.RewardAccount({ networkId, stakeCredential: cred });
      return AddressEras.toBech32(addr);
    },

    baseAddress(scriptHash: ScriptHash, userAddress: Address): Address {
      // Build a base address: script payment credential + user's key staking credential
      // Uses Evolution SDK's BaseAddress constructor for correct header byte computation
      const stakingHash = this.stakingCredentialHash(userAddress);

      const addr = new BaseAddress.BaseAddress({
        networkId,
        paymentCredential: new EvoScriptHash.ScriptHash({
          hash: Bytes.fromHex(scriptHash),
        }),
        stakeCredential: new KeyHash.KeyHash({
          hash: Bytes.fromHex(stakingHash),
        }),
      });

      return AddressEras.toBech32(addr);
    },

    stakingCredentialHash(address: Address): HexString {
      const evoAddr = EvoAddress.fromBech32(address);
      const baseAddr = BaseAddress.fromHex(EvoAddress.toHex(evoAddr));
      return Bytes.toHex(baseAddr.stakeCredential.hash);
    },

    paymentCredentialHash(address: Address): HexString {
      const evoAddr = EvoAddress.fromBech32(address);
      const baseAddr = BaseAddress.fromHex(EvoAddress.toHex(evoAddr));
      return Bytes.toHex(baseAddr.paymentCredential.hash);
    },

    // -- TxBuilder --

    newTx(): TxPlan {
      const txBuilder = evoClient_.newTx();
      return new EvolutionTxPlan(txBuilder, networkId);
    },
  };
}
