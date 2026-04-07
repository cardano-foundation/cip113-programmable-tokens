/**
 * CIP-113 Programmable Tokens SDK
 *
 * @example
 * ```ts
 * import { CIP113 } from '@cip113/sdk';
 * import { evolutionAdapter } from '@cip113/sdk/evolution';
 * import { freezeAndSeizeSubstandard } from '@cip113/sdk/freeze-and-seize';
 *
 * const protocol = CIP113.init({
 *   adapter: evolutionAdapter({ network: 'preprod', provider: { type: 'blockfrost', projectId: '...' } }),
 *   standard: { blueprint: standardBlueprint, deployment: deploymentParams },
 *   substandards: [freezeAndSeizeSubstandard({ blueprint: fesBlueprint })],
 * });
 *
 * const tx = await protocol.register('freeze-and-seize', { assetName: 'MyToken', quantity: 1000n, ... });
 * ```
 */

import type { CIP113Adapter } from "./provider/interface.js";
import type { DeploymentParams, PlutusBlueprint, PolicyId } from "./types.js";
import type {
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
  /** Adapter providing blockchain queries and tx building */
  adapter: CIP113Adapter;

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

  /** The adapter */
  readonly adapter: CIP113Adapter;

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

    // Build parameterized standard scripts
    const scripts = buildDeploymentScripts(
      config.standard.blueprint,
      config.standard.deployment,
      config.adapter
    );

    // Registry of substandard plugins
    const substandards = new Map<string, SubstandardPlugin>();

    // Build the substandard context
    const substandardContext = {
      adapter: config.adapter,
      standardScripts: scripts,
      deployment: config.standard.deployment,
      network: "preprod", // TODO: derive from adapter
    };

    // Initialize and register provided substandards
    if (config.substandards) {
      for (const plugin of config.substandards) {
        plugin.init(substandardContext);
        substandards.set(plugin.id, plugin);
      }
    }

    // Helper to get substandard or throw
    function requireSubstandard(id: string): SubstandardPlugin {
      const plugin = substandards.get(id);
      if (!plugin) {
        throw new Error(
          `Substandard "${id}" not registered. Available: ${[...substandards.keys()].join(", ")}`
        );
      }
      return plugin;
    }

    // Helper to resolve substandard from policyId
    // TODO: implement lookup from registry
    function resolveSubstandard(_policyId: PolicyId): SubstandardPlugin {
      // For now, require explicit substandard ID
      throw new Error("Substandard resolution from policyId not yet implemented");
    }

    return {
      scripts,
      deployment: config.standard.deployment,
      adapter: config.adapter,

      async register(substandardId, params) {
        return requireSubstandard(substandardId).register(params);
      },

      async mint(params) {
        // TODO: resolve substandard from policyId via registry lookup
        // For now, iterate substandards and try
        for (const plugin of substandards.values()) {
          try {
            return await plugin.mint(params);
          } catch {
            continue;
          }
        }
        throw new Error(`No substandard can handle mint for policy ${params.tokenPolicyId}`);
      },

      async burn(params) {
        for (const plugin of substandards.values()) {
          try {
            return await plugin.burn(params);
          } catch {
            continue;
          }
        }
        throw new Error(`No substandard can handle burn for policy ${params.tokenPolicyId}`);
      },

      async transfer(params) {
        for (const plugin of substandards.values()) {
          try {
            return await plugin.transfer(params);
          } catch {
            continue;
          }
        }
        throw new Error(`No substandard can handle transfer for policy ${params.tokenPolicyId}`);
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
          for (const plugin of substandards.values()) {
            if (plugin.freeze) {
              try {
                return await plugin.freeze(params);
              } catch {
                continue;
              }
            }
          }
          throw new Error(`No substandard supports freeze for policy ${params.tokenPolicyId}`);
        },

        async unfreeze(params) {
          for (const plugin of substandards.values()) {
            if (plugin.unfreeze) {
              try {
                return await plugin.unfreeze(params);
              } catch {
                continue;
              }
            }
          }
          throw new Error(`No substandard supports unfreeze for policy ${params.tokenPolicyId}`);
        },

        async seize(params) {
          for (const plugin of substandards.values()) {
            if (plugin.seize) {
              try {
                return await plugin.seize(params);
              } catch {
                continue;
              }
            }
          }
          throw new Error(`No substandard supports seize for policy ${params.tokenPolicyId}`);
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

export type { CIP113Adapter, CardanoProvider, TxBuilder, TxPlan } from "./provider/interface.js";
export type {
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
} from "./substandards/interface.js";
export type {
  DeploymentParams,
  PlutusBlueprint,
  PlutusScript,
  TxInput,
  UTxO,
  Value,
  Network,
  PolicyId,
  ScriptHash,
  HexString,
} from "./types.js";
export { Data } from "./core/datums.js";
export * from "./core/redeemers.js";
export { sortTxInputs, findRefInputIndex } from "./core/registry.js";
