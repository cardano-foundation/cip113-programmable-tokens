import { PlutusScript } from "@meshsdk/common";
import {
  applyParamsToScript,
  resolveScriptHash,
  serializePlutusScript,
  byteString,
  conStr1,
} from "@meshsdk/core";
import { scriptHashToRewardAddress } from "@meshsdk/core-cst";

import { SubstandardBlueprint } from "../../../../types/protocol";
import { findSubstandardValidator } from "../../../utils/script-utils";

export class cip113_scripts_freezeAndSeize {
  private networkID: number;
  private validators: { title: string; script_bytes: string }[];

  constructor(networkID: number, blueprint: SubstandardBlueprint) {
    this.networkID = networkID;
    this.validators = blueprint.validators;
  }

  /**
   * Build parameterized transfer withdraw script.
   *
   * Contract: example_transfer_logic.transfer.withdraw
   * Parameters: [Credential::Script(progLogicBaseScriptHash), blacklistNodePolicyId]
   */
  async transfer_withdraw(
    progLogicBaseScriptHash: string,
    blacklistNodePolicyId: string
  ) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "example_transfer_logic.transfer",
      "withdraw"
    );

    const cbor = applyParamsToScript(
      scriptBytes,
      [
        conStr1([byteString(progLogicBaseScriptHash)]),
        byteString(blacklistNodePolicyId),
      ],
      "JSON"
    );

    const plutus_script: PlutusScript = {
      code: cbor,
      version: "V3",
    };
    const policy_id = resolveScriptHash(cbor, "V3");
    const reward_address = scriptHashToRewardAddress(
      policy_id,
      this.networkID
    );

    return {
      cbor,
      plutus_script,
      policy_id,
      reward_address,
    };
  }

  /**
   * Build parameterized blacklist spend script.
   *
   * Contract: blacklist_spend.blacklist_spend.spend
   * Parameters: [blacklistMintPolicyId]
   *
   * Note: For the transfer flow, blacklistMintPolicyId === blacklistNodePolicyId
   * (the blacklist node NFTs are minted by the blacklist mint script,
   * and blacklistNodePolicyId IS that mint script's policy ID).
   */
  async blacklist_spend(blacklistMintPolicyId: string) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "blacklist_spend.blacklist_spend",
      "spend"
    );

    const cbor = applyParamsToScript(
      scriptBytes,
      [byteString(blacklistMintPolicyId)],
      "JSON"
    );

    const plutus_script: PlutusScript = {
      code: cbor,
      version: "V3",
    };
    const policy_id = resolveScriptHash(cbor, "V3");
    const address = serializePlutusScript(
      plutus_script,
      undefined,
      this.networkID,
      false
    ).address;

    return {
      cbor,
      plutus_script,
      address,
      policy_id,
    };
  }
}

export default cip113_scripts_freezeAndSeize;
