"use client";

/**
 * CIP-113 SDK context.
 *
 * Provides a lazily-initialized CIP113Protocol to components.
 * Fetches blueprints and deployment params from the backend API on first use.
 */

import {
  createContext,
  useContext,
  useRef,
  useCallback,
  useMemo,
  type ReactNode,
} from "react";
import { useProtocolVersion } from "./protocol-version-context";
import {
  CIP113,
  type CIP113Protocol,
  type DeploymentParams,
  type PlutusBlueprint,
} from "@cip113/sdk";
import { evolutionAdapter } from "@cip113/sdk/evolution";
import { dummySubstandard } from "@cip113/sdk/dummy";
import { freezeAndSeizeSubstandard } from "@cip113/sdk/freeze-and-seize";
import type { FESDeploymentParams } from "@cip113/sdk";
import {
  getProtocolBlueprint,
  getProtocolBootstrap,
  getSubstandardBlueprint,
  getTokenContext,
} from "@/lib/api/protocol";
import { stringToHex } from "@/lib/api/minting";
import type { ProtocolBootstrapParams } from "@/types/protocol";

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

interface CIP113ContextValue {
  /**
   * Get or lazily initialize the CIP-113 protocol.
   * First call fetches blueprints + params from backend — subsequent calls return cached.
   */
  getProtocol(): Promise<CIP113Protocol>;

  /**
   * Ensure the right substandard is registered for a given token.
   * Fetches token context from backend, registers FES substandard if needed.
   * Returns the substandardId for direct routing.
   */
  ensureSubstandard(policyId: string, assetName: string): Promise<string>;

  /**
   * Register a token in the backend DB after SDK-built on-chain registration.
   * This is a callback — no tx building, just persists to backend DB.
   */
  registerTokenCallback(params: {
    policyId: string;
    substandardId: string;
    assetName: string;
    issuerAdminPkh?: string;
    blacklistNodePolicyId?: string;
  }): Promise<void>;

  /**
   * Build a FES registration flow (blacklist init + token registration).
   * Returns two unsigned tx CBORs that must be signed and submitted in order.
   */
  buildFESRegistration(params: {
    adminAddress: string;
    assetName: string;
    quantity: string;
    recipientAddress?: string;
  }): Promise<{
    initCbor: string;
    regCbor: string;
    blacklistNodePolicyId: string;
    tokenPolicyId: string;
  }>;

  /** Whether the SDK is available (has Blockfrost key) */
  available: boolean;
}

const CIP113Context = createContext<CIP113ContextValue>({
  getProtocol: () => Promise.reject(new Error("CIP113Provider not mounted")),
  ensureSubstandard: () => Promise.reject(new Error("CIP113Provider not mounted")),
  registerTokenCallback: () => Promise.reject(new Error("CIP113Provider not mounted")),
  buildFESRegistration: () => Promise.reject(new Error("CIP113Provider not mounted")),
  available: false,
});

// ---------------------------------------------------------------------------
// Convert backend bootstrap params to SDK DeploymentParams
// ---------------------------------------------------------------------------

/**
 * Convert backend bootstrap params to SDK DeploymentParams.
 *
 * The frontend types are a subset of what the Java backend provides.
 * Fields not available in the frontend types use the bootstrap txHash
 * as a reasonable default (bootstrap tx outputs are at fixed indices).
 */
function toDeploymentParams(bp: ProtocolBootstrapParams): DeploymentParams {
  return {
    txHash: bp.txHash,
    protocolParams: {
      txInput: bp.protocolParams.txInput,
      policyId: bp.protocolParams.scriptHash,
      alwaysFailScriptHash: bp.protocolParams.alwaysFailScriptHash,
    },
    programmableLogicGlobal: {
      policyId: bp.programmableLogicGlobalPrams.scriptHash,
      scriptHash: bp.programmableLogicGlobalPrams.scriptHash,
    },
    programmableLogicBase: {
      scriptHash: bp.programmableLogicBaseParams.scriptHash,
    },
    issuance: {
      txInput: bp.issuanceParams.txInput,
      policyId: bp.issuanceParams.scriptHash,
      alwaysFailScriptHash: bp.issuanceParams.alwaysFailScriptHash,
    },
    directoryMint: {
      txInput: bp.directoryMintParams.txInput,
      issuanceScriptHash: bp.directoryMintParams.issuanceScriptHash,
      scriptHash: bp.directoryMintParams.scriptHash,
    },
    directorySpend: {
      policyId: bp.directorySpendParams.scriptHash,
      scriptHash: bp.directorySpendParams.scriptHash,
    },
    programmableBaseRefInput: bp.programmableBaseRefInput,
    programmableGlobalRefInput: bp.programmableGlobalRefInput,
  };
}

// ---------------------------------------------------------------------------
// Convert backend blueprint to SDK PlutusBlueprint
// ---------------------------------------------------------------------------

function toSdkBlueprint(bp: { validators: Array<{ title: string; compiledCode: string; hash: string }>; preamble?: { title: string; version: string } }): PlutusBlueprint {
  return {
    preamble: bp.preamble ?? { title: "unknown", version: "0.0.0" },
    validators: bp.validators.map((v) => ({
      title: v.title,
      compiledCode: v.compiledCode,
      hash: v.hash,
    })),
  };
}

function substandardToSdkBlueprint(bp: { id: string; validators: Array<{ title: string; script_bytes: string; script_hash: string }> }): PlutusBlueprint {
  return {
    preamble: { title: bp.id, version: "0.1.0" },
    validators: bp.validators.map((v) => ({
      title: v.title,
      compiledCode: v.script_bytes,
      hash: v.script_hash,
    })),
  };
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

export function CIP113Provider({ children }: { children: ReactNode }) {
  const network = (process.env.NEXT_PUBLIC_NETWORK || "preview") as "preview" | "preprod" | "mainnet";
  const blockfrostKey = process.env.NEXT_PUBLIC_BLOCKFROST_API_KEY || "";
  const blockfrostUrl = process.env.NEXT_PUBLIC_BLOCKFROST_URL || "";
  const { selectedVersion } = useProtocolVersion();

  const protocolRef = useRef<CIP113Protocol | null>(null);
  const initPromiseRef = useRef<Promise<CIP113Protocol> | null>(null);
  /** Track which FES tokens have been registered (by policyId) */
  const registeredFESTokens = useRef<Set<string>>(new Set());
  /** Cache FES blueprint to avoid re-fetching */
  const fesBlueprintRef = useRef<PlutusBlueprint | null>(null);

  const available = !!blockfrostKey;

  const getProtocol = useCallback(async (): Promise<CIP113Protocol> => {
    // Return cached protocol if available
    if (protocolRef.current) return protocolRef.current;

    // Return in-progress initialization if one is running
    if (initPromiseRef.current) return initPromiseRef.current;

    if (!blockfrostKey) {
      throw new Error("CIP-113 SDK not available: NEXT_PUBLIC_BLOCKFROST_API_KEY not set");
    }

    // Start initialization
    const promise = (async () => {
      console.log("[CIP-113] Initializing SDK...");

      // 1. Fetch from backend
      const [protocolBp, bootstrapParams, dummyBp] = await Promise.all([
        getProtocolBlueprint(),
        getProtocolBootstrap(selectedVersion?.txHash),
        getSubstandardBlueprint("dummy"),
      ]);

      // 2. Create Evolution adapter
      const adapter = evolutionAdapter({
        network,
        provider: {
          type: "blockfrost",
          projectId: blockfrostKey,
          ...(blockfrostUrl ? { baseUrl: blockfrostUrl } : {}),
        },
      });

      // 3. Initialize CIP-113 protocol
      const protocol = CIP113.init({
        adapter,
        standard: {
          blueprint: toSdkBlueprint(protocolBp),
          deployment: toDeploymentParams(bootstrapParams),
        },
        substandards: [
          dummySubstandard({ blueprint: substandardToSdkBlueprint(dummyBp) }),
          // FES substandards are per-token — they'll be registered dynamically
        ],
      });

      console.log("[CIP-113] SDK initialized. Substandards:", protocol.listSubstandards());
      protocolRef.current = protocol;
      return protocol;
    })();

    initPromiseRef.current = promise;

    try {
      return await promise;
    } catch (e) {
      initPromiseRef.current = null; // Allow retry on failure
      throw e;
    }
  }, [blockfrostKey, blockfrostUrl, network, selectedVersion?.txHash]);

  /**
   * Ensure the right substandard is registered for a token.
   * For FES tokens: fetches context from backend, registers FES substandard dynamically.
   * Returns the substandardId for direct routing.
   */
  const ensureSubstandard = useCallback(async (policyId: string, assetName: string): Promise<string> => {
    // 1. Fetch token context from backend
    const tokenCtx = await getTokenContext(policyId);

    // 2. If FES and not already registered, register dynamically
    if (tokenCtx.substandardId === "freeze-and-seize" && !registeredFESTokens.current.has(policyId)) {
      const protocol = await getProtocol();

      // Fetch FES blueprint (cached)
      if (!fesBlueprintRef.current) {
        const fesBp = await getSubstandardBlueprint("freeze-and-seize");
        fesBlueprintRef.current = substandardToSdkBlueprint(fesBp);
      }

      const fes = freezeAndSeizeSubstandard({
        blueprint: fesBlueprintRef.current,
        deployment: {
          adminPkh: tokenCtx.issuerAdminPkh || "",
          assetName: tokenCtx.assetName || assetName,
          blacklistNodePolicyId: tokenCtx.blacklistNodePolicyId || "",
          blacklistInitTxInput: { txHash: "", outputIndex: 0 },
        },
      });

      protocol.registerSubstandard(fes);
      registeredFESTokens.current.add(policyId);
      console.log(`[CIP-113] Registered FES substandard for token ${policyId}`);
    }

    return tokenCtx.substandardId;
  }, [getProtocol]);

  /**
   * Register a token in the backend DB after SDK-built on-chain registration.
   */
  const registerTokenCallback = useCallback(async (params: {
    policyId: string;
    substandardId: string;
    assetName: string;
    issuerAdminPkh?: string;
    blacklistNodePolicyId?: string;
  }) => {
    const baseUrl = process.env.NEXT_PUBLIC_API_URL || "";
    const apiPrefix = process.env.NEXT_PUBLIC_API_PREFIX || "/api/v1";
    await fetch(`${baseUrl}${apiPrefix}/token-context/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    });
    console.log(`[CIP-113] Token ${params.policyId} registered in backend DB`);
  }, []);

  /**
   * Build a FES registration flow (blacklist init + token registration).
   * Creates a temporary FES substandard instance for the registration.
   */
  const buildFESRegistration = useCallback(async (params: {
    adminAddress: string;
    assetName: string;
    quantity: string;
    recipientAddress?: string;
  }) => {
    const protocol = await getProtocol();
    const adapter = protocol.adapter;
    const assetNameHex = stringToHex(params.assetName);
    const adminPkh = adapter.paymentCredentialHash(params.adminAddress);

    // Fetch FES blueprint
    if (!fesBlueprintRef.current) {
      const fesBp = await getSubstandardBlueprint("freeze-and-seize");
      fesBlueprintRef.current = substandardToSdkBlueprint(fesBp);
    }

    // Step 1: We need blacklistInitTxInput — use the first wallet UTxO
    const walletUtxos = await adapter.getUtxos(params.adminAddress);
    if (walletUtxos.length === 0) throw new Error("No wallet UTxOs");
    const bootstrapUtxo = walletUtxos[0];
    const blacklistInitTxInput = {
      txHash: bootstrapUtxo.txHash,
      outputIndex: bootstrapUtxo.outputIndex,
    };

    // Pre-compute the blacklist mint policy ID deterministically
    // It's derived from: blacklistMint(bootstrapTxInput, adminPkh)
    // We need to parameterize just the blacklist mint script to get its hash
    const { createFESScripts } = await import("@cip113/sdk/freeze-and-seize");
    const tempFesScripts = createFESScripts(fesBlueprintRef.current, adapter);
    const blacklistMintScript = tempFesScripts.buildBlacklistMint(blacklistInitTxInput, adminPkh);
    const blacklistNodePolicyId = blacklistMintScript.hash;
    console.log("[CIP-113] Pre-computed blacklistNodePolicyId:", blacklistNodePolicyId);

    // Create a FES substandard with the CORRECT blacklistNodePolicyId
    const fes = freezeAndSeizeSubstandard({
      blueprint: fesBlueprintRef.current,
      deployment: {
        adminPkh,
        assetName: assetNameHex,
        blacklistNodePolicyId,
        blacklistInitTxInput,
      },
    });

    fes.init({
      adapter,
      standardScripts: protocol.scripts,
      deployment: protocol.deployment,
      network: network,
    });

    // Step 1: Build blacklist init tx
    console.log("[CIP-113] Building blacklist init tx...");
    const initResult = await fes.initCompliance!({
      feePayerAddress: params.adminAddress,
      adminAddress: params.adminAddress,
      assetName: params.assetName,
      skipStakeRegistration: true, // Stake registration handled separately
    });

    console.log("[CIP-113] Blacklist init built. PolicyId:", initResult.metadata?.blacklistNodePolicyId);

    console.log("[CIP-113] Building registration tx...");
    const regResult = await fes.register({
      feePayerAddress: params.adminAddress,
      assetName: params.assetName,
      quantity: BigInt(params.quantity),
      recipientAddress: params.recipientAddress,
      config: { adminPkh, blacklistNodePolicyId },
    });

    const tokenPolicyId = regResult.tokenPolicyId ?? "";
    console.log("[CIP-113] Registration built. TokenPolicyId:", tokenPolicyId);

    return {
      initCbor: initResult.cbor,
      regCbor: regResult.cbor,
      blacklistNodePolicyId,
      tokenPolicyId,
    };
  }, [getProtocol, network]);

  const value = useMemo(
    () => ({ getProtocol, ensureSubstandard, registerTokenCallback, buildFESRegistration, available }),
    [getProtocol, ensureSubstandard, registerTokenCallback, buildFESRegistration, available]
  );

  return (
    <CIP113Context.Provider value={value}>
      {children}
    </CIP113Context.Provider>
  );
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export function useCIP113() {
  return useContext(CIP113Context);
}
