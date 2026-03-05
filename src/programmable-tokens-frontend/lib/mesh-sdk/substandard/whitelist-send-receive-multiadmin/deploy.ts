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

export class cip113_scripts_whitelistSendReceiveMultiAdmin {
  private networkID: number;
  private validators: { title: string; script_bytes: string }[];

  constructor(networkID: number, blueprint: SubstandardBlueprint) {
    this.networkID = networkID;
    this.validators = blueprint.validators;
  }

  private buildScript(cbor: string) {
    const plutus_script: PlutusScript = { code: cbor, version: "V3" };
    const policy_id = resolveScriptHash(cbor, "V3");
    return { cbor, plutus_script, policy_id };
  }

  private buildWithRewardAddress(cbor: string) {
    const base = this.buildScript(cbor);
    const reward_address = scriptHashToRewardAddress(
      base.policy_id,
      this.networkID
    );
    return { ...base, reward_address };
  }

  private buildWithEntAddress(cbor: string) {
    const base = this.buildScript(cbor);
    const address = serializePlutusScript(
      base.plutus_script,
      undefined,
      this.networkID,
      false
    ).address;
    return { ...base, address };
  }

  /**
   * manager_signatures.manager_signatures.mint
   * Parameters: [utxo_ref]
   */
  async manager_signatures_mint(utxoTxHash: string, utxoOutputIndex: number) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "manager_signatures.manager_signatures",
      "mint"
    );

    const utxoRef = {
      constructor: 0,
      fields: [{ bytes: utxoTxHash }, { int: utxoOutputIndex }],
    };

    const cbor = applyParamsToScript(scriptBytes, [utxoRef], "JSON");
    return this.buildScript(cbor);
  }

  /**
   * manager_signatures.manager_signatures.withdraw
   * Parameters: [utxo_ref]
   */
  async manager_signatures_withdraw(
    utxoTxHash: string,
    utxoOutputIndex: number
  ) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "manager_signatures.manager_signatures",
      "withdraw"
    );

    const utxoRef = {
      constructor: 0,
      fields: [{ bytes: utxoTxHash }, { int: utxoOutputIndex }],
    };

    const cbor = applyParamsToScript(scriptBytes, [utxoRef], "JSON");
    return this.buildWithRewardAddress(cbor);
  }

  /**
   * manager_list_mint.manager_list_mint.mint
   * Parameters: [utxo_ref, manager_sigs_hash]
   */
  async manager_list_mint(
    utxoTxHash: string,
    utxoOutputIndex: number,
    managerSigsHash: string
  ) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "manager_list_mint.manager_list_mint",
      "mint"
    );

    const utxoRef = {
      constructor: 0,
      fields: [{ bytes: utxoTxHash }, { int: utxoOutputIndex }],
    };

    const cbor = applyParamsToScript(
      scriptBytes,
      [utxoRef, byteString(managerSigsHash)],
      "JSON"
    );
    return this.buildScript(cbor);
  }

  /**
   * manager_list_spend.manager_list_spend.spend
   * Parameters: [manager_list_cs]
   */
  async manager_list_spend(managerListCs: string) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "manager_list_spend.manager_list_spend",
      "spend"
    );

    const cbor = applyParamsToScript(
      scriptBytes,
      [byteString(managerListCs)],
      "JSON"
    );
    return this.buildWithEntAddress(cbor);
  }

  /**
   * manager_auth.manager_auth.withdraw
   * Parameters: [manager_list_cs]
   */
  async manager_auth(managerListCs: string) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "manager_auth.manager_auth",
      "withdraw"
    );

    const cbor = applyParamsToScript(
      scriptBytes,
      [byteString(managerListCs)],
      "JSON"
    );
    return this.buildWithRewardAddress(cbor);
  }

  /**
   * whitelist_mint.whitelist_mint.mint
   * Parameters: [utxo_ref, manager_auth_hash]
   */
  async whitelist_mint(
    utxoTxHash: string,
    utxoOutputIndex: number,
    managerAuthHash: string
  ) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "whitelist_mint.whitelist_mint",
      "mint"
    );

    const utxoRef = {
      constructor: 0,
      fields: [{ bytes: utxoTxHash }, { int: utxoOutputIndex }],
    };

    const cbor = applyParamsToScript(
      scriptBytes,
      [utxoRef, byteString(managerAuthHash)],
      "JSON"
    );
    return this.buildScript(cbor);
  }

  /**
   * whitelist_spend.whitelist_spend.spend
   * Parameters: [whitelist_cs]
   */
  async whitelist_spend(whitelistCs: string) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "whitelist_spend.whitelist_spend",
      "spend"
    );

    const cbor = applyParamsToScript(
      scriptBytes,
      [byteString(whitelistCs)],
      "JSON"
    );
    return this.buildWithEntAddress(cbor);
  }

  /**
   * whitelist_transfer_logic.transfer.withdraw
   * Parameters: [Credential::Script(progLogicBaseCred), whitelist_node_cs]
   */
  async transfer_withdraw(
    progLogicBaseScriptHash: string,
    whitelistNodeCs: string
  ) {
    const scriptBytes = findSubstandardValidator(
      this.validators,
      "whitelist_transfer_logic.transfer",
      "withdraw"
    );

    const cbor = applyParamsToScript(
      scriptBytes,
      [
        conStr1([byteString(progLogicBaseScriptHash)]),
        byteString(whitelistNodeCs),
      ],
      "JSON"
    );
    return this.buildWithRewardAddress(cbor);
  }
}

export default cip113_scripts_whitelistSendReceiveMultiAdmin;
