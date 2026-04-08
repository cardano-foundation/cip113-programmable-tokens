/**
 * Substandard plugin interface.
 *
 * Each substandard (dummy, freeze-and-seize, CMTAT, etc.) implements this
 * interface to provide transaction builders for its operations.
 *
 * Substandards are initialized with the standard scripts and provider,
 * then registered with the CIP113 protocol instance.
 */

import type { CIP113Adapter } from "../provider/interface.js";
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
  adapter: CIP113Adapter;
  standardScripts: ResolvedStandardScripts;
  deployment: DeploymentParams;
  network: string;
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
}

// ---------------------------------------------------------------------------
// Factory function type
// ---------------------------------------------------------------------------

export type SubstandardFactory = (config: {
  blueprint: PlutusBlueprint;
}) => SubstandardPlugin;
