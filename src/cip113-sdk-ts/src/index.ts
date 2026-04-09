/**
 * CIP-113 Programmable Tokens SDK
 *
 * @example
 * ```ts
 * import { CIP113 } from '@cip113/sdk';
 * import { dummySubstandard } from '@cip113/sdk/dummy';
 * import { freezeAndSeizeSubstandard } from '@cip113/sdk/freeze-and-seize';
 *
 * // Create Evolution SDK client
 * const evoClient = client(preprod)
 *   .withBlockfrost({ projectId: '...' })
 *   .withAddress(walletAddress);
 *
 * const protocol = CIP113.init({
 *   client: evoClient,
 *   standard: { blueprint: standardBlueprint, deployment: deploymentParams },
 *   substandards: [dummySubstandard({ blueprint: dummyBlueprint })],
 * });
 *
 * const tx = await protocol.register('freeze-and-seize', { ... });
 * ```
 */

import type { DeploymentParams, PlutusBlueprint, PolicyId } from "./types.js";
import type {
  EvoClient,
  SubstandardPlugin,
  RegisterParams,
  MintParams,
  BurnParams,
  TransferParams,
  FreezeParams,
  UnfreezeParams,
  SeizeParams,
  InitComplianceParams,
  UnsignedTx,
} from "./substandards/interface.js";
import { validateStandardBlueprint } from "./standard/blueprint.js";
import { buildDeploymentScripts, type ResolvedStandardScripts } from "./standard/scripts.js";

// ---------------------------------------------------------------------------
// Init configuration
// ---------------------------------------------------------------------------

export interface CIP113Config {
  /** Evolution SDK client (ReadOnlyClient or SigningClient) */
  client: EvoClient;

  /** Standard protocol configuration */
  standard: {
    blueprint: PlutusBlueprint;
    deployment: DeploymentParams;
  };

  /** Substandard plugins to register */
  substandards?: SubstandardPlugin[];
}

// ---------------------------------------------------------------------------
// Protocol instance
// ---------------------------------------------------------------------------

export interface CIP113Protocol {
  /** The resolved standard scripts (cached, reusable) */
  readonly scripts: ResolvedStandardScripts;

  /** The deployment parameters */
  readonly deployment: DeploymentParams;

  /** The Evolution SDK client */
  readonly client: EvoClient;

  // -- Operations (delegated to substandards) --

  /** Register a new programmable token */
  register(substandardId: string, params: RegisterParams): Promise<UnsignedTx>;

  /** Mint additional tokens */
  mint(params: MintParams): Promise<UnsignedTx>;

  /** Burn tokens */
  burn(params: BurnParams): Promise<UnsignedTx>;

  /** Transfer tokens */
  transfer(params: TransferParams): Promise<UnsignedTx>;

  // -- Compliance operations --

  compliance: {
    /** Initialize compliance infrastructure (e.g., blacklist) */
    init(substandardId: string, params: InitComplianceParams): Promise<UnsignedTx>;

    /** Freeze an address */
    freeze(params: FreezeParams): Promise<UnsignedTx>;

    /** Unfreeze an address */
    unfreeze(params: UnfreezeParams): Promise<UnsignedTx>;

    /** Seize tokens */
    seize(params: SeizeParams): Promise<UnsignedTx>;
  };

  // -- Runtime extensibility --

  /** Register a new substandard plugin at runtime */
  registerSubstandard(plugin: SubstandardPlugin): void;

  /** Get a registered substandard by ID */
  getSubstandard(id: string): SubstandardPlugin | undefined;

  /** List all registered substandard IDs */
  listSubstandards(): string[];
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export const CIP113 = {
  /**
   * Initialize a CIP-113 protocol instance.
   *
   * This validates the standard blueprint, parameterizes all standard scripts,
   * and initializes registered substandards.
   */
  init(config: CIP113Config): CIP113Protocol {
    // Validate standard blueprint has all required validators
    validateStandardBlueprint(config.standard.blueprint);

    // Build parameterized standard scripts (uses Evolution SDK directly)
    const scripts = buildDeploymentScripts(
      config.standard.blueprint,
      config.standard.deployment,
    );

    // Registry of substandard plugins
    const substandards = new Map<string, SubstandardPlugin>();

    // Build the substandard context
    const substandardContext = {
      client: config.client,
      standardScripts: scripts,
      deployment: config.standard.deployment,
      network: config.client.chain.id === 1 ? "mainnet" : "preprod",
    };

    // Initialize and register provided substandards
    if (config.substandards) {
      for (const plugin of config.substandards) {
        plugin.init(substandardContext);
        substandards.set(plugin.id, plugin);
      }
    }

    // Helper: try all substandards
    async function tryAllSubstandards(
      operation: string,
      policyId: string,
      fn: (plugin: SubstandardPlugin) => Promise<UnsignedTx>
    ): Promise<UnsignedTx> {
      let lastError: unknown;
      for (const plugin of substandards.values()) {
        try {
          return await fn(plugin);
        } catch (e) {
          lastError = e;
          continue;
        }
      }
      throw new Error(
        `No substandard can handle ${operation} for policy ${policyId}. ` +
        `Available: [${[...substandards.keys()].join(", ")}]. ` +
        `Last error: ${lastError instanceof Error ? lastError.message : String(lastError)}. ` +
        `Hint: pass substandardId to route directly.`
      );
    }

    function requireSubstandard(id: string): SubstandardPlugin {
      const plugin = substandards.get(id);
      if (!plugin) {
        throw new Error(
          `Substandard "${id}" not registered. Available: ${[...substandards.keys()].join(", ")}`
        );
      }
      return plugin;
    }

    return {
      scripts,
      deployment: config.standard.deployment,
      client: config.client,

      async register(substandardId, params) {
        return requireSubstandard(substandardId).register(params);
      },

      async mint(params) {
        if (params.substandardId) {
          return requireSubstandard(params.substandardId).mint(params);
        }
        return tryAllSubstandards("mint", params.tokenPolicyId, (p) => p.mint(params));
      },

      async burn(params) {
        if (params.substandardId) {
          return requireSubstandard(params.substandardId).burn(params);
        }
        return tryAllSubstandards("burn", params.tokenPolicyId, (p) => p.burn(params));
      },

      async transfer(params) {
        if (params.substandardId) {
          return requireSubstandard(params.substandardId).transfer(params);
        }
        return tryAllSubstandards("transfer", params.tokenPolicyId, (p) => p.transfer(params));
      },

      compliance: {
        async init(substandardId, params) {
          const plugin = requireSubstandard(substandardId);
          if (!plugin.initCompliance) {
            throw new Error(`Substandard "${substandardId}" does not support compliance initialization`);
          }
          return plugin.initCompliance(params);
        },

        async freeze(params) {
          return tryAllSubstandards("freeze", params.tokenPolicyId, (p) => {
            if (!p.freeze) throw new Error(`${p.id} does not support freeze`);
            return p.freeze(params);
          });
        },

        async unfreeze(params) {
          return tryAllSubstandards("unfreeze", params.tokenPolicyId, (p) => {
            if (!p.unfreeze) throw new Error(`${p.id} does not support unfreeze`);
            return p.unfreeze(params);
          });
        },

        async seize(params) {
          return tryAllSubstandards("seize", params.tokenPolicyId, (p) => {
            if (!p.seize) throw new Error(`${p.id} does not support seize`);
            return p.seize(params);
          });
        },
      },

      registerSubstandard(plugin) {
        plugin.init(substandardContext);
        substandards.set(plugin.id, plugin);
      },

      getSubstandard(id) {
        return substandards.get(id);
      },

      listSubstandards() {
        return [...substandards.keys()];
      },
    };
  },
};

// ---------------------------------------------------------------------------
// Re-exports
// ---------------------------------------------------------------------------

export type {
  EvoClient,
  SubstandardPlugin,
  SubstandardFactory,
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
  CIP68MetadataInput,
} from "./substandards/interface.js";
export type {
  DeploymentParams,
  PlutusBlueprint,
  PlutusScript,
  TxInput,
  UTxO,
  Network,
  PolicyId,
  ScriptHash,
  HexString,
  Assets,
} from "./types.js";
export {
  buildEvoScript,
  computeScriptHash,
  parameterizeScript,
  scriptAddress,
  rewardAddress,
  baseAddress,
  stakingCredentialHash,
  paymentCredentialHash,
  stringToHex,
  MAX_NEXT,
  voidData,
  outputReference,
  scriptCredential,
  keyCredential,
  labeledAssetName,
  buildCIP68FTDatum,
} from "./core/evo-utils.js";
export { sortTxInputs, findRefInputIndex } from "./core/registry.js";
export { addressHexToBech32 } from "./provider/address-utils.js";
export { assembleSignedTx } from "./provider/tx-utils.js";
export type { FESDeploymentParams } from "./substandards/freeze-and-seize/types.js";

// Re-export Evolution SDK essentials so consumers don't need a direct dependency
export {
  client as evoClient,
  preview as previewChain,
  preprod as preprodChain,
  mainnet as mainnetChain,
  Address as EvoAddress,
  Assets as EvoAssets,
  TransactionHash as EvoTransactionHash,
  Transaction as EvoTransaction,
  Data as EvoData,
} from "@evolution-sdk/evolution";
