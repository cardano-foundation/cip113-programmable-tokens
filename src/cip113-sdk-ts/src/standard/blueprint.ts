/**
 * Blueprint loading and validator lookup.
 */

import type { PlutusBlueprint, BlueprintValidator, HexString } from "../types.js";

/**
 * Standard validator titles as they appear in the blueprint.
 */
export const STANDARD_VALIDATORS = {
  ALWAYS_FAIL: "always_fail.always_fail.spend",
  PROTOCOL_PARAMS_MINT: "protocol_params_mint.protocol_params_mint.mint",
  PROGRAMMABLE_LOGIC_GLOBAL: "programmable_logic_global.programmable_logic_global.withdraw",
  PROGRAMMABLE_LOGIC_BASE: "programmable_logic_base.programmable_logic_base.spend",
  ISSUANCE_CBOR_HEX_MINT: "issuance_cbor_hex_mint.issuance_cbor_hex_mint.mint",
  ISSUANCE_MINT: "issuance_mint.issuance_mint.mint",
  REGISTRY_MINT: "registry_mint.registry_mint.mint",
  REGISTRY_SPEND: "registry_spend.registry_spend.spend",
} as const;

/**
 * Get a validator's compiled code from a blueprint by title.
 * Throws if the validator is not found.
 */
export function getValidatorCode(
  blueprint: PlutusBlueprint,
  title: string
): HexString {
  const validator = blueprint.validators.find((v) => v.title === title);
  if (!validator) {
    throw new Error(
      `Validator "${title}" not found in blueprint "${blueprint.preamble.title} v${blueprint.preamble.version}"`
    );
  }
  return validator.compiledCode;
}

/**
 * Get a validator entry from a blueprint by title.
 */
export function getValidator(
  blueprint: PlutusBlueprint,
  title: string
): BlueprintValidator {
  const validator = blueprint.validators.find((v) => v.title === title);
  if (!validator) {
    throw new Error(
      `Validator "${title}" not found in blueprint "${blueprint.preamble.title} v${blueprint.preamble.version}"`
    );
  }
  return validator;
}

/**
 * Validate that a blueprint contains all required standard validators.
 */
export function validateStandardBlueprint(blueprint: PlutusBlueprint): void {
  const titles = blueprint.validators.map((v) => v.title);
  for (const [name, title] of Object.entries(STANDARD_VALIDATORS)) {
    if (!titles.includes(title)) {
      throw new Error(
        `Standard blueprint is missing required validator "${name}" (title: "${title}")`
      );
    }
  }
}
