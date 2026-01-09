import cbor from "cbor";

import { PlutusScript } from "@meshsdk/common";
import { resolveScriptHash } from "@meshsdk/core";
import { scriptHashToRewardAddress } from "@meshsdk/core-cst";

import { findValidator } from "../../../utils/script-utils";

export class cip113_scripts_subStandard {
  private networkID: number;
  constructor(networkID: number) {
    this.networkID = networkID;
  }

  async transfer_issue_withdraw() {
    const validator = findValidator("transfer.issue", "withdraw", true);
    const _cbor = cbor.encode(Buffer.from(validator, "hex")).toString("hex");
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
    const validator = findValidator("transfer.transfer", "withdraw", true);
    const _cbor = cbor.encode(Buffer.from(validator, "hex")).toString("hex");
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
