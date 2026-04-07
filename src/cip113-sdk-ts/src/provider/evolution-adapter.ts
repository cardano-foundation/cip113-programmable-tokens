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
  Assets,
  Credential,
  InlineDatum,
  KeyHash,
} from "@evolution-sdk/evolution";

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
  return {
    _tag: "PlutusV3",
    bytes: Bytes.fromHex(compiledCode),
  } as Script.Script;
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
  // Extract transaction hash from TransactionHash tagged class
  const txHash: string =
    typeof evoUtxo.transactionId === "object" && evoUtxo.transactionId?.hash
      ? String(evoUtxo.transactionId.hash)
      : String(evoUtxo.transactionId ?? "");

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
 * Needed by collectFrom and readFrom to pass properly typed inputs.
 * We construct the object shape that Evolution's TransactionBuilder expects.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function toEvoUtxo(utxo: UTxO): any {
  const evoAddress = EvoAddress.fromBech32(utxo.address);
  const evoAssets = toEvoAssets(utxo.value);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const result: any = {
    _tag: "UTxO",
    transactionId: { _tag: "TransactionHash", hash: utxo.txHash },
    index: BigInt(utxo.outputIndex),
    address: evoAddress,
    assets: evoAssets,
  };

  if (utxo.datum != null) {
    result.datumOption = new InlineDatum.InlineDatum({
      data: toEvoData(utxo.datum),
    });
  } else if (utxo.datumHash != null) {
    result.datumOption = { _tag: "DatumHash", hash: utxo.datumHash };
  }

  if (utxo.referenceScript != null) {
    result.scriptRef = buildEvoScript(utxo.referenceScript.compiledCode);
  }

  return result;
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

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  constructor(builder: any) {
    this.builder = builder;
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

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const evoParams: any = {
      stakeCredential,
      amount: params.amount,
    };

    if (params.redeemer != null) {
      evoParams.redeemer = toEvoData(params.redeemer);
    }

    this.builder = this.builder.withdraw(evoParams);
    return this;
  }

  registerStake(params: RegisterStakeParams): TxPlan {
    const stakeCredential = Credential.makeScriptHash(
      Bytes.fromHex(params.stakeCredential)
    );
    this.builder = this.builder.registerStake({ stakeCredential });
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
    // Evolution build() returns a SignBuilder which provides sign/submit chain.
    // For unsigned CBOR access, we extract it from the result.
    const result = await this.builder.build();

    return {
      toCbor(): HexString {
        if (typeof result.toCBOR === "function") return result.toCBOR();
        if (typeof result.toCBORHex === "function") return result.toCBORHex();
        if (typeof result.toCbor === "function") return result.toCbor();
        throw new Error("Cannot extract CBOR from built transaction");
      },
      txHash(): TxHash {
        if (typeof result.txHash === "function") return result.txHash();
        if (typeof result.hash === "function") return result.hash();
        if (typeof result.txHash === "string") return result.txHash;
        throw new Error("Cannot extract txHash from built transaction");
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
  const chainName = toEvoChain(config.network);

  // Step 1: Create chain-scoped assembly
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let builder: any = evoClient(chainName as any);

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

  // Step 3: Attach wallet if provided (produces SigningClient)
  if (config.wallet) {
    builder = builder.withSeed({
      mnemonic: config.wallet.mnemonic,
      ...(config.wallet.accountIndex != null
        ? { accountIndex: config.wallet.accountIndex }
        : {}),
    });
  }

  // The final client: ReadClient (no wallet) or SigningClient (with wallet)
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
      // Enterprise address: header 0x70 (testnet) or 0x71 (mainnet) + 28-byte script hash
      const headerByte = config.network === "mainnet" ? "71" : "70";
      return EvoAddress.toBech32(EvoAddress.fromHex(headerByte + scriptHash));
    },

    rewardAddress(scriptHash: ScriptHash): Address {
      // Reward address: header 0xf0 (testnet script) or 0xf1 (mainnet script) + 28-byte script hash
      const headerByte = config.network === "mainnet" ? "f1" : "f0";
      return EvoAddress.toBech32(EvoAddress.fromHex(headerByte + scriptHash));
    },

    // -- TxBuilder --

    newTx(): TxPlan {
      const txBuilder = evoClient_.newTx();
      return new EvolutionTxPlan(txBuilder);
    },
  };
}
