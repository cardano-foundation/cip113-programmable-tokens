/**
 * Substandard plugin interface.
 *
 * Each substandard (dummy, freeze-and-seize, CMTAT, etc.) implements this
 * interface to provide transaction builders for its operations.
 *
 * Substandards receive the Evolution SDK client directly — no adapter layer.
 */

import type { ReadOnlyClient, SigningClient } from "@evolution-sdk/evolution/sdk/client/Client";
import type { ResolvedStandardScripts } from "../standard/scripts.js";
import type {
  Address,
  DeploymentParams,
  HexString,
  PlutusBlueprint,
  PolicyId,
  ScriptHash,
} from "../types.js";

// ---------------------------------------------------------------------------
// Client type — either ReadOnlyClient or SigningClient
// ---------------------------------------------------------------------------

/**
 * The SDK accepts either a ReadOnlyClient (for CIP-30 wallets) or a
 * SigningClient (for seed-phrase / private-key wallets).
 *
 * Both have getUtxos(), getUtxosWithUnit(), newTx(), chain, etc.
 * The difference is build() return type: TransactionResultBase vs SignBuilder.
 */
export type EvoClient = ReadOnlyClient | SigningClient;

// ---------------------------------------------------------------------------
// Plugin interface
// ---------------------------------------------------------------------------

export interface SubstandardPlugin {
  /** Unique identifier (e.g., "dummy", "freeze-and-seize") */
  readonly id: string;

  /** Version of this substandard implementation */
  readonly version: string;

  /** The substandard's blueprint */
  readonly blueprint: PlutusBlueprint;

  /**
   * Initialize the plugin with the protocol context.
   * Called once when the substandard is registered with CIP113.init().
   */
  init(context: SubstandardContext): void;

  // -- Core operations (required) --

  /** Register a new programmable token with this substandard */
  register(params: RegisterParams): Promise<UnsignedTx>;

  /** Mint additional tokens (already registered) */
  mint(params: MintParams): Promise<UnsignedTx>;

  /** Burn tokens */
  burn(params: BurnParams): Promise<UnsignedTx>;

  /** Transfer tokens between addresses */
  transfer(params: TransferParams): Promise<UnsignedTx>;

  // -- Optional capabilities --

  /** Freeze an address (blacklist) */
  freeze?(params: FreezeParams): Promise<UnsignedTx>;

  /** Unfreeze an address (remove from blacklist) */
  unfreeze?(params: UnfreezeParams): Promise<UnsignedTx>;

  /** Seize tokens from an address */
  seize?(params: SeizeParams): Promise<UnsignedTx>;

  /** Initialize compliance infrastructure (e.g., blacklist) */
  initCompliance?(params: InitComplianceParams): Promise<UnsignedTx>;
}

// ---------------------------------------------------------------------------
// Context provided to plugins at init
// ---------------------------------------------------------------------------

export interface SubstandardContext {
  /** Evolution SDK client (ReadOnlyClient or SigningClient) */
  client: EvoClient;
  standardScripts: ResolvedStandardScripts;
  deployment: DeploymentParams;
  network: string;
  /** Check if a stake address is registered on-chain. If not provided, assumes not registered. */
  checkStakeRegistration?: (stakeAddress: string) => Promise<boolean>;
}

// ---------------------------------------------------------------------------
// CIP-68 metadata
// ---------------------------------------------------------------------------

/** CIP-68 FT metadata fields provided by the caller. */
export interface CIP68MetadataInput {
  /** Display name (required, stored as byte string in datum) */
  name: string;
  /** Token description */
  description?: string;
  /** Short ticker symbol, e.g. "MYTKN" */
  ticker?: string;
  /** Number of decimal places for display (default: 0) */
  decimals?: number;
  /** Project or token URL */
  url?: string;
  /** URI pointing to the token logo image */
  logo?: string;
}

// ---------------------------------------------------------------------------
// Operation parameters
// ---------------------------------------------------------------------------

export interface RegisterParams {
  feePayerAddress: Address;
  assetName: string;
  quantity: bigint;
  recipientAddress?: Address;
  /** Substandard-specific config (e.g., adminPkh for FES) */
  config?: Record<string, unknown>;
  /** Available UTxOs from a chained transaction (e.g., initCompliance) */
  chainedUtxos?: unknown[];
  /** Optional CIP-68 metadata. When provided, mints ref token (label 100) + FT user token (label 333). */
  cip68Metadata?: CIP68MetadataInput;
}

export interface MintParams {
  feePayerAddress: Address;
  tokenPolicyId: PolicyId;
  assetName: string;
  quantity: bigint;
  recipientAddress?: Address;
  /** Optional: route directly to this substandard instead of trying all */
  substandardId?: string;
}

export interface BurnParams {
  feePayerAddress: Address;
  tokenPolicyId: PolicyId;
  assetName: string;
  utxoTxHash: HexString;
  utxoOutputIndex: number;
  /** Optional: route directly to this substandard instead of trying all */
  substandardId?: string;
}

export interface TransferParams {
  senderAddress: Address;
  recipientAddress: Address;
  tokenPolicyId: PolicyId;
  assetName: string;
  quantity: bigint;
  /** Optional: route directly to this substandard instead of trying all */
  substandardId?: string;
}

export interface FreezeParams {
  feePayerAddress: Address;
  tokenPolicyId: PolicyId;
  assetName: string;
  targetAddress: Address;
}

export interface UnfreezeParams {
  feePayerAddress: Address;
  tokenPolicyId: PolicyId;
  assetName: string;
  targetAddress: Address;
}

export interface SeizeParams {
  feePayerAddress: Address;
  tokenPolicyId: PolicyId;
  assetName: string;
  utxoTxHash: HexString;
  utxoOutputIndex: number;
  destinationAddress: Address;
}

export interface InitComplianceParams {
  feePayerAddress: Address;
  adminAddress: Address;
  assetName: string;
  /** The bootstrap UTxO to consume (one-shot). If provided, skips fetching. */
  bootstrapUtxo?: unknown;
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

export interface UnsignedTx {
  /** Unsigned transaction CBOR hex */
  cbor: HexString;
  /** Transaction hash (derived from body) */
  txHash: HexString;
  /** Policy ID of the minted token (for register/mint operations) */
  tokenPolicyId?: PolicyId;
  /** Additional metadata from the operation */
  metadata?: Record<string, unknown>;
  /** Available UTxOs for chaining (from SignBuilder.chainResult().available) */
  chainAvailable?: unknown[];
  /** Internal: the SignBuilder for direct sign+submit (seed wallets) */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  _signBuilder?: any;
}

// ---------------------------------------------------------------------------
// Factory function type
// ---------------------------------------------------------------------------

export type SubstandardFactory = (config: {
  blueprint: PlutusBlueprint;
}) => SubstandardPlugin;
