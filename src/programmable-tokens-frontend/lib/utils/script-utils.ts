import { RegistryDatum } from "../../types/protocol";

export const findValidator = (
  validators: { title: string; compiledCode: string }[],
  validatorName: string,
  purpose: string
): string => {
  const title = `${validatorName}.${validatorName}.${purpose}`;
  const validator = validators.find((v) => v.title === title);
  if (!validator) {
    throw new Error(`Validator ${title} not found`);
  }
  return validator.compiledCode;
};

export const findSubstandardValidator = (
  validators: { title: string; script_bytes: string }[],
  validatorName: string,
  purpose: string
): string => {
  const title = `${validatorName}.${purpose}`;
  const validator = validators.find((v) => v.title === title);
  if (!validator) {
    throw new Error(`Validator ${title} not found`);
  }
  return validator.script_bytes;
};

export interface BlacklistNode {
  key: string;
  next: string;
}

export function parseBlacklistNodeDatum(datum: any): BlacklistNode | null {
  if (!datum?.fields || datum.fields.length < 2) return null;
  return {
    key: datum.fields[0].bytes,
    next: datum.fields[1].bytes,
  };
}

export function sortTxInputRefs(inputs: { txHash: string; outputIndex: number }[]) {
  return [...inputs].sort((a, b) => {
    const cmp = a.txHash.localeCompare(b.txHash);
    return cmp !== 0 ? cmp : a.outputIndex - b.outputIndex;
  });
}

export function parseRegistryDatum(datum: any): RegistryDatum | null {
  if (!datum?.fields || datum.fields.length < 5) {
    return null;
  }
  return {
    key: datum.fields[0].bytes,
    next: datum.fields[1].bytes,
    transferScriptHash: datum.fields[2].bytes,
    thirdPartyScriptHash: datum.fields[3].bytes,
    metadata: datum.fields[4].bytes,
  };
}
