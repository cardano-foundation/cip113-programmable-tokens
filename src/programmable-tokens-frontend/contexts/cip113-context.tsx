"use client";

/**
 * CIP-113 SDK context.
 *
 * Provides a lazily-initialized CIP113Protocol to components.
 * Fetches blueprints and deployment params from the backend API on first use.
 *
 * Uses Evolution SDK client directly — no adapter abstraction.
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
  paymentCredentialHash,
  stringToHex,
  evoClient,
  previewChain,
  preprodChain,
  mainnetChain,
  EvoAddress,
  EvoTransactionHash,
} from "@cip113/sdk";
import { dummySubstandard } from "@cip113/sdk/dummy";
import { freezeAndSeizeSubstandard, createFESScripts } from "@cip113/sdk/freeze-and-seize";
import type { FESDeploymentParams } from "@cip113/sdk";
import {
  getProtocolBlueprint,
  getProtocolBootstrap,
  getSubstandardBlueprint,
  getTokenContext,
} from "@/lib/api/protocol";
import type { ProtocolBootstrapParams } from "@/types/protocol";

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

interface CIP113ContextValue {
  getProtocol(): Promise<CIP113Protocol>;
  ensureSubstandard(policyId: string, assetName: string): Promise<string>;
  registerTokenCallback(params: {
    policyId: string;
    substandardId: string;
    assetName: string;
    issuerAdminPkh?: string;
    blacklistNodePolicyId?: string;
  }): Promise<void>;
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
  const registeredFESTokens = useRef<Set<string>>(new Set());
  const fesBlueprintRef = useRef<PlutusBlueprint | null>(null);

  const available = !!blockfrostKey;

  /** Get the Evolution SDK chain preset for the configured network */
  const getChain = useCallback(() => {
    switch (network) {
      case "mainnet": return mainnetChain;
      case "preprod": return preprodChain;
      case "preview": return previewChain;
    }
  }, [network]);

  const getProtocol = useCallback(async (): Promise<CIP113Protocol> => {
    if (protocolRef.current) return protocolRef.current;
    if (initPromiseRef.current) return initPromiseRef.current;

    if (!blockfrostKey) {
      throw new Error("CIP-113 SDK not available: NEXT_PUBLIC_BLOCKFROST_API_KEY not set");
    }

    const promise = (async () => {
      console.log("[CIP-113] Initializing SDK...");

      // 1. Fetch from backend
      const [protocolBp, bootstrapParams, dummyBp] = await Promise.all([
        getProtocolBlueprint(),
        getProtocolBootstrap(selectedVersion?.txHash),
        getSubstandardBlueprint("dummy"),
      ]);

      // 2. Create Evolution SDK client (ReadOnlyClient — no wallet for CIP-30 flow)
      const chain = getChain();
      const readClient = evoClient(chain).withBlockfrost({
        projectId: blockfrostKey,
        baseUrl: blockfrostUrl || `https://cardano-${network}.blockfrost.io/api/v0`,
      });
      // Use a dummy address to give the client network context
      const dummyAddr = chain.id === 1
        ? "addr1qx2kd28nq8ac5prwg32hhvudlwggpgfp8utlyqxu6wqgz62f79qsdmm5dsknt9ecr5w468r9ey0fxwkdrwh08ly3tu9sy0f4qd"
        : "addr_test1qzx9hu8j4ah3auytk0mwcupd69hpc52t0cw39a65ndrah86djs784u92a3m5w475w3w35tyd6v3qumkze80j8a6h5tuqq5xe8y";
      const clientWithAddr = readClient.withAddress(dummyAddr);

      // 3. Initialize CIP-113 protocol
      const protocol = CIP113.init({
        client: clientWithAddr,
        standard: {
          blueprint: toSdkBlueprint(protocolBp),
          deployment: toDeploymentParams(bootstrapParams),
        },
        substandards: [
          dummySubstandard({ blueprint: substandardToSdkBlueprint(dummyBp) }),
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
      initPromiseRef.current = null;
      throw e;
    }
  }, [blockfrostKey, blockfrostUrl, network, selectedVersion?.txHash, getChain]);

  const ensureSubstandard = useCallback(async (policyId: string, assetName: string): Promise<string> => {
    const tokenCtx = await getTokenContext(policyId);

    if (tokenCtx.substandardId === "freeze-and-seize" && !registeredFESTokens.current.has(policyId)) {
      const protocol = await getProtocol();

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

  const buildFESRegistration = useCallback(async (params: {
    adminAddress: string;
    assetName: string;
    quantity: string;
    recipientAddress?: string;
  }) => {
    const protocol = await getProtocol();
    const client = protocol.client;
    const assetNameHex = stringToHex(params.assetName);
    const adminPkh = paymentCredentialHash(params.adminAddress);

    // Fetch FES blueprint
    if (!fesBlueprintRef.current) {
      const fesBp = await getSubstandardBlueprint("freeze-and-seize");
      fesBlueprintRef.current = substandardToSdkBlueprint(fesBp);
    }

    // Step 1: Compute blacklistInitTxInput from first wallet UTxO
    const walletUtxos = await client.getUtxos(EvoAddress.fromBech32(params.adminAddress));
    if (walletUtxos.length === 0) throw new Error("No wallet UTxOs");
    const bootstrapUtxo = walletUtxos[0];
    const blacklistInitTxInput = {
      txHash: EvoTransactionHash.toHex(bootstrapUtxo.transactionId),
      outputIndex: Number(bootstrapUtxo.index),
    };

    // Pre-compute the blacklist mint policy ID
    const tempFesScripts = createFESScripts(fesBlueprintRef.current);
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
      client,
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
      bootstrapUtxo: bootstrapUtxo,
    });

    console.log("[CIP-113] Blacklist init built. PolicyId:", initResult.metadata?.blacklistNodePolicyId);
    console.log("[CIP-113] Init CBOR hex:", initResult.cbor);
    console.log("[CIP-113] Init txHash:", initResult.txHash);
    console.log("[CIP-113] Init metadata:", JSON.stringify(initResult.metadata));

    // Step 2: Build registration tx — chain from init using available UTxOs
    console.log("[CIP-113] Building registration tx...");
    console.log("[CIP-113] Chaining with", initResult.chainAvailable?.length ?? 0, "available UTxOs from init");
    try {
      const regResult = await fes.register({
        feePayerAddress: params.adminAddress,
        assetName: params.assetName,
        quantity: BigInt(params.quantity),
        recipientAddress: params.recipientAddress,
        config: { adminPkh, blacklistNodePolicyId },
        chainedUtxos: initResult.chainAvailable,
      });

      const tokenPolicyId = regResult.tokenPolicyId ?? "";
      console.log("[CIP-113] Registration built. TokenPolicyId:", tokenPolicyId);
      console.log("[CIP-113] Reg CBOR hex:", regResult.cbor);
      console.log("[CIP-113] Reg txHash:", regResult.txHash);

      return {
        initCbor: initResult.cbor,
        regCbor: regResult.cbor,
        blacklistNodePolicyId,
        tokenPolicyId,
      };
    } catch (regError) {
      console.error("[CIP-113] Registration build FAILED:", regError);
      console.error("[CIP-113] Reg error message:", (regError as Error)?.message);
      let cause = (regError as any)?.cause;
      let depth = 0;
      while (cause && depth < 5) {
        console.error(`[CIP-113] Reg cause[${depth}]:`, cause?.message ?? JSON.stringify(cause)?.slice(0, 500));
        cause = cause?.cause;
        depth++;
      }
      throw regError;
    }
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
