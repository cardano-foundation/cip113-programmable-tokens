import type { IWallet } from "@meshsdk/core";
import type {
  ProtocolBootstrapParams,
  ProtocolBlueprint,
  SubstandardBlueprint,
} from "@/types/protocol";
import { register_programmable_tokens } from "../transactions/register";
import { transfer_programmable_token } from "../transactions/transfer";
import { mint_programmable_tokens } from "../transactions/mint";
import { getNetworkId } from "../config";

export type SubstandardId = "dummy" | "bafin";

export interface MintTransactionParams {
  assetName: string;
  quantity: string;
  issuerBaseAddress: string;
  recipientAddress?: string;
  substandardName: string;
  substandardIssueContractName: string;
}

export interface RegisterTransactionParams {
  assetName: string;
  quantity: string;
  registrarAddress: string;
  recipientAddress?: string;
  substandardName: string;
  substandardIssueContractName: string;
  substandardTransferContractName: string;
  substandardThirdPartyContractName?: string;
  networkId?: 0 | 1;
}

export interface TransferTransactionParams {
  unit: string;
  quantity: string;
  recipientAddress: string;
  networkId?: 0 | 1;
}

export interface SubstandardHandler {
  buildMintTransaction(
    params: MintTransactionParams,
    protocolParams: ProtocolBootstrapParams,
    protocolBlueprint: ProtocolBlueprint,
    substandardBlueprint: SubstandardBlueprint,
    wallet: IWallet
  ): Promise<string>;

  buildRegisterTransaction(
    params: RegisterTransactionParams,
    protocolParams: ProtocolBootstrapParams,
    protocolBlueprint: ProtocolBlueprint,
    substandardBlueprint: SubstandardBlueprint,
    wallet: IWallet
  ): Promise<{ unsignedTx: string; policy_Id: string }>;

  buildTransferTransaction(
    params: TransferTransactionParams,
    protocolParams: ProtocolBootstrapParams,
    protocolBlueprint: ProtocolBlueprint,
    substandardBlueprint: SubstandardBlueprint,
    wallet: IWallet
  ): Promise<string>;
}

const dummyHandler: SubstandardHandler = {
  async buildMintTransaction(
    params: MintTransactionParams,
    protocolParams: ProtocolBootstrapParams,
    protocolBlueprint: ProtocolBlueprint,
    substandardBlueprint: SubstandardBlueprint,
    wallet: IWallet
  ): Promise<string> {
    const networkId = getNetworkId();

    return mint_programmable_tokens(
      protocolParams,
      params.assetName,
      params.quantity,
      networkId,
      wallet,
      protocolBlueprint,
      substandardBlueprint,
      params.recipientAddress || null
    );
  },

  async buildRegisterTransaction(
    params: RegisterTransactionParams,
    protocolParams: ProtocolBootstrapParams,
    protocolBlueprint: ProtocolBlueprint,
    substandardBlueprint: SubstandardBlueprint,
    wallet: IWallet
  ): Promise<{ unsignedTx: string; policy_Id: string }> {
    const subStandardName = params.substandardIssueContractName.includes(
      "issue"
    )
      ? ("issuance" as const)
      : ("transfer" as const);

    const networkId = params.networkId ?? getNetworkId();

    const { unsignedTx, policy_Id } = await register_programmable_tokens(
      params.assetName,
      params.quantity,
      protocolParams,
      subStandardName,
      networkId,
      wallet,
      protocolBlueprint,
      substandardBlueprint,
      params.recipientAddress || null
    );
    return { unsignedTx, policy_Id };
  },

  async buildTransferTransaction(
    params: TransferTransactionParams,
    protocolParams: ProtocolBootstrapParams,
    protocolBlueprint: ProtocolBlueprint,
    substandardBlueprint: SubstandardBlueprint,
    wallet: IWallet
  ): Promise<string> {
    const networkId = params.networkId ?? getNetworkId();

    return transfer_programmable_token(
      params.unit,
      params.quantity,
      params.recipientAddress,
      protocolParams,
      networkId,
      wallet,
      protocolBlueprint,
      substandardBlueprint
    );
  },
};

const bafinHandler: SubstandardHandler = {
  async buildMintTransaction() {
    throw new Error(
      "Bafin substandard not yet implemented for client-side transaction building"
    );
  },

  async buildRegisterTransaction() {
    throw new Error(
      "Bafin substandard not yet implemented for client-side transaction building"
    );
  },

  async buildTransferTransaction() {
    throw new Error(
      "Bafin substandard not yet implemented for client-side transaction building"
    );
  },
};

const handlers: Record<string, SubstandardHandler> = {
  dummy: dummyHandler,
  bafin: bafinHandler,
};

/**
 * Get a substandard handler by ID
 */
export function getSubstandardHandler(
  substandardId: SubstandardId
): SubstandardHandler {
  const handler = handlers[substandardId.toLowerCase()];

  if (!handler) {
    throw new Error(`Substandard not found: ${substandardId}`);
  }

  return handler;
}

/**
 * Check if a substandard is supported for client-side transaction building
 */
export function isSubstandardSupported(substandardId: string): boolean {
  return substandardId.toLowerCase() in handlers;
}

/**
 * Get all supported substandard IDs
 */
export function getSupportedSubstandards(): SubstandardId[] {
  return Object.keys(handlers) as SubstandardId[];
}
