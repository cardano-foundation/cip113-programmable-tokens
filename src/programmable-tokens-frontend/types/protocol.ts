export interface TxInput {
  txHash: string;
  outputIndex: number;
}

export interface ProtocolParams {
  txInput: TxInput;
  scriptHash: string;
  alwaysFailScriptHash: string;
}

export interface DirectoryMintParams {
  txInput: TxInput;
  issuanceScriptHash: string;
  scriptHash: string;
}

export interface ProgrammableLogicBaseParams {
  scriptHash: string;
}

export interface ProgrammableLogicGlobalParams {
  scriptHash: string;
}

export interface IssuanceParams {
  txInput: TxInput;
  scriptHash: string;
  alwaysFailScriptHash: string;
}

export interface DirectorySpendParams {
  scriptHash: string;
}

export interface ProtocolBootstrapParams {
  protocolParams: ProtocolParams;
  programmableLogicGlobalPrams: ProgrammableLogicGlobalParams;
  programmableLogicBaseParams: ProgrammableLogicBaseParams;
  issuanceParams: IssuanceParams;
  directoryMintParams: DirectoryMintParams;
  directorySpendParams: DirectorySpendParams;
  programmableBaseRefInput: TxInput;
  programmableGlobalRefInput: TxInput;
  txHash: string;
}

export type RegistryDatum = {
  key: string;
  next: any;
  transferScriptHash: string;
  thirdPartyScriptHash: string;
  metadata: any;
};

export interface BlueprintValidator {
  title: string;
  compiledCode: string;
  hash: string;
}

export interface ProtocolBlueprint {
  validators: BlueprintValidator[];
  preamble?: {
    title: string;
    version: string;
    description?: string;
  };
}

export interface SubstandardValidator {
  title: string;
  script_hash: string;
  script_bytes: string;
}

export interface SubstandardBlueprint {
  id: string;
  validators: SubstandardValidator[];
}

export interface TokenContext {
  policyId: string;
  substandardId: string;
  assetName?: string;
  blacklistNodePolicyId?: string;
  issuerAdminPkh?: string;
  blacklistInitTxHash?: string;
  blacklistInitOutputIndex?: number;
}
