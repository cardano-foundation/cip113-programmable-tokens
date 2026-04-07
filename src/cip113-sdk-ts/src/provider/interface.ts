/**
 * Provider and TxBuilder interfaces.
 *
 * These define the adapter seam between CIP-113 logic and the underlying
 * transaction builder (Evolution SDK, Mesh SDK, etc.).
 *
 * CIP-113 core logic NEVER imports the concrete SDK — only these interfaces.
 */

import type {
  Address,
  HexString,
  PlutusData,
  PlutusScript,
  ScriptHash,
  TxHash,
  UTxO,
  Value,
} from "../types.js";

// ---------------------------------------------------------------------------
// Provider — blockchain queries
// ---------------------------------------------------------------------------

export interface CardanoProvider {
  /** Get all UTxOs at an address */
  getUtxos(address: Address): Promise<UTxO[]>;

  /** Get UTxOs at an address that contain a specific unit (policyId + assetName) */
  getUtxosWithUnit(address: Address, unit: string): Promise<UTxO[]>;

  /** Get protocol parameters */
  getProtocolParameters(): Promise<ProtocolParameters>;

  /** Submit a signed transaction (CBOR hex) */
  submitTx(signedTxCbor: HexString): Promise<TxHash>;

  /** Wait for a transaction to be confirmed */
  awaitTx(txHash: TxHash, timeout?: number): Promise<boolean>;

  /** Apply parameters to a compiled script */
  applyParamsToScript(
    compiledCode: HexString,
    params: PlutusData[]
  ): HexString;

  /** Compute script hash from compiled code */
  scriptHash(compiledCode: HexString): ScriptHash;

  /** Derive an enterprise (script) address from a script hash */
  scriptAddress(scriptHash: ScriptHash): Address;

  /** Derive a reward (staking) address from a script hash */
  rewardAddress(scriptHash: ScriptHash): Address;
}

export interface ProtocolParameters {
  minFeeA: number;
  minFeeB: number;
  maxTxSize: number;
  stakeKeyDeposit: bigint;
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// Transaction Builder — declarative tx construction
// ---------------------------------------------------------------------------

export interface TxBuilder {
  newTx(): TxPlan;
}

export interface TxPlan {
  /** Add a payment output */
  payToAddress(params: PayToAddressParams): TxPlan;

  /** Spend UTxOs (with optional script redeemer) */
  collectFrom(params: CollectFromParams): TxPlan;

  /** Mint or burn tokens */
  mintAssets(params: MintAssetsParams): TxPlan;

  /** Add reference inputs (not consumed) */
  readFrom(params: ReadFromParams): TxPlan;

  /** Invoke a staking/reward validator (withdraw-zero trick) */
  withdraw(params: WithdrawParams): TxPlan;

  /** Register a stake address */
  registerStake(params: RegisterStakeParams): TxPlan;

  /** Attach a script to the transaction */
  attachScript(params: AttachScriptParams): TxPlan;

  /** Add a required signer */
  addSigner(params: AddSignerParams): TxPlan;

  /** Set transaction validity interval */
  setValidity(params: ValidityParams): TxPlan;

  /** Build the transaction (returns unsigned CBOR) */
  build(): Promise<BuiltTx>;
}

// ---------------------------------------------------------------------------
// Parameter types for TxPlan methods
// ---------------------------------------------------------------------------

export interface PayToAddressParams {
  address: Address;
  value: Value;
  datum?: PlutusData;
  inlineDatum?: boolean;
  referenceScript?: PlutusScript;
}

export interface CollectFromParams {
  inputs: UTxO[];
  redeemer?: PlutusData;
}

export interface MintAssetsParams {
  /** Map of unit (policyId + assetName hex) -> quantity */
  assets: Map<string, bigint>;
  redeemer: PlutusData;
}

export interface ReadFromParams {
  referenceInputs: UTxO[];
}

export interface WithdrawParams {
  stakeCredential: ScriptHash;
  amount: bigint;
  redeemer?: PlutusData;
}

export interface RegisterStakeParams {
  stakeCredential: ScriptHash;
}

export interface AttachScriptParams {
  script: PlutusScript;
}

export interface AddSignerParams {
  keyHash: HexString;
}

export interface ValidityParams {
  from?: bigint;
  to?: bigint;
}

export interface BuiltTx {
  /** Unsigned transaction CBOR hex */
  toCbor(): HexString;

  /** Transaction hash (derived from body) */
  txHash(): TxHash;
}

// ---------------------------------------------------------------------------
// Combined adapter (provider + tx builder)
// ---------------------------------------------------------------------------

export interface CIP113Adapter extends CardanoProvider, TxBuilder {}
