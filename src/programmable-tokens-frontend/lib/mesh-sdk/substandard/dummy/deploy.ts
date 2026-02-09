import cbor from "cbor";

import { PlutusScript } from "@meshsdk/common";
import { resolveScriptHash } from "@meshsdk/core";
import { scriptHashToRewardAddress } from "@meshsdk/core-cst";

import { SubstandardBlueprint } from "../../../../types/protocol";
import { findSubstandardValidator } from "../../../utils/script-utils";

export class cip113_scripts_subStandard {
  private networkID: number;
  private validators: { title: string; script_bytes: string }[];

  constructor(networkID: number, blueprint: SubstandardBlueprint) {
    this.networkID = networkID;
    this.validators = blueprint.validators;
  }

  async transfer_issue_withdraw() {
    const scriptBytes = findSubstandardValidator(this.validators, "transfer.issue", "withdraw");
    const _cbor = cbor.encode(Buffer.from(scriptBytes, "hex")).toString("hex");
    const plutus_script: PlutusScript = {
      code: _cbor,
      version: "V3",
    };
    const policy_id = resolveScriptHash(_cbor, "V3");
    const address = scriptHashToRewardAddress(policy_id, this.networkID);

    return {
      _cbor,
      plutus_script,
      policy_id,
      address,
    };
  }

  async transfer_transfer_withdraw() {
    const scriptBytes = findSubstandardValidator(this.validators, "transfer.transfer", "withdraw");
    const _cbor = cbor.encode(Buffer.from(scriptBytes, "hex")).toString("hex");
    const plutus_script: PlutusScript = {
      code: _cbor,
      version: "V3",
    };
    const policy_id = resolveScriptHash(_cbor, "V3");
    const reward_address = scriptHashToRewardAddress(policy_id, this.networkID);

    return {
      _cbor,
      plutus_script,
      reward_address,
      policy_id,
    };
  }
}

export default cip113_scripts_subStandard;
