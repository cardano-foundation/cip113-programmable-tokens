package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.SubstandardValidator;
import org.cardanofoundation.cip113.util.PlutusSerializationHelper;
import org.springframework.stereotype.Service;

/**
 * Service for building parameterized whitelist-send-receive-multiadmin scripts.
 *
 * <p>Validator parameterization chain:</p>
 * <pre>
 * manager_signatures(utxo_ref_1) → manager_sigs_hash
 * manager_list_mint(utxo_ref_2, manager_sigs_hash) → manager_list_cs
 * manager_list_spend(manager_list_cs)
 * manager_auth(manager_list_cs) → manager_auth_hash
 * whitelist_mint(utxo_ref_3, manager_auth_hash) → whitelist_cs
 * whitelist_spend(whitelist_cs)
 * whitelist_transfer_logic(programmable_logic_base_cred, whitelist_cs) → transfer_logic_hash
 * </pre>
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class WhitelistMultiAdminScriptBuilderService {

    private static final String SUBSTANDARD_ID = "whitelist-send-receive-multiadmin";

    private final SubstandardService substandardService;

    /**
     * Build manager_signatures mint script.
     * Contract: manager_signatures.manager_signatures.mint
     * Parameters: [utxo_ref]
     */
    public PlutusScript buildManagerSignaturesMintScript(TransactionInput utxoRef) {
        var contract = getContract("manager_signatures.manager_signatures.mint");
        var params = ListPlutusData.of(PlutusSerializationHelper.serialize(utxoRef));
        return applyParameters(contract, params, "manager_signatures_mint");
    }

    /**
     * Build manager_signatures withdraw script.
     * Contract: manager_signatures.manager_signatures.withdraw
     * Parameters: [utxo_ref]
     */
    public PlutusScript buildManagerSignaturesWithdrawScript(TransactionInput utxoRef) {
        var contract = getContract("manager_signatures.manager_signatures.withdraw");
        var params = ListPlutusData.of(PlutusSerializationHelper.serialize(utxoRef));
        return applyParameters(contract, params, "manager_signatures_withdraw");
    }

    /**
     * Build manager_list_mint script.
     * Contract: manager_list_mint.manager_list_mint.mint
     * Parameters: [utxo_ref, manager_sigs_hash]
     */
    public PlutusScript buildManagerListMintScript(TransactionInput utxoRef, String managerSigsHash) {
        var contract = getContract("manager_list_mint.manager_list_mint.mint");
        var params = ListPlutusData.of(
                PlutusSerializationHelper.serialize(utxoRef),
                BytesPlutusData.of(HexUtil.decodeHexString(managerSigsHash))
        );
        return applyParameters(contract, params, "manager_list_mint");
    }

    /**
     * Build manager_list_spend script.
     * Contract: manager_list_spend.manager_list_spend.spend
     * Parameters: [manager_list_cs]
     */
    public PlutusScript buildManagerListSpendScript(String managerListCs) {
        var contract = getContract("manager_list_spend.manager_list_spend.spend");
        var params = ListPlutusData.of(
                BytesPlutusData.of(HexUtil.decodeHexString(managerListCs))
        );
        return applyParameters(contract, params, "manager_list_spend");
    }

    /**
     * Build manager_auth withdraw script.
     * Contract: manager_auth.manager_auth.withdraw
     * Parameters: [manager_list_cs]
     */
    public PlutusScript buildManagerAuthScript(String managerListCs) {
        var contract = getContract("manager_auth.manager_auth.withdraw");
        var params = ListPlutusData.of(
                BytesPlutusData.of(HexUtil.decodeHexString(managerListCs))
        );
        return applyParameters(contract, params, "manager_auth");
    }

    /**
     * Build whitelist_mint script.
     * Contract: whitelist_mint.whitelist_mint.mint
     * Parameters: [utxo_ref, manager_auth_hash]
     */
    public PlutusScript buildWhitelistMintScript(TransactionInput utxoRef, String managerAuthHash) {
        var contract = getContract("whitelist_mint.whitelist_mint.mint");
        var params = ListPlutusData.of(
                PlutusSerializationHelper.serialize(utxoRef),
                BytesPlutusData.of(HexUtil.decodeHexString(managerAuthHash))
        );
        return applyParameters(contract, params, "whitelist_mint");
    }

    /**
     * Build whitelist_spend script.
     * Contract: whitelist_spend.whitelist_spend.spend
     * Parameters: [whitelist_cs]
     */
    public PlutusScript buildWhitelistSpendScript(String whitelistCs) {
        var contract = getContract("whitelist_spend.whitelist_spend.spend");
        var params = ListPlutusData.of(
                BytesPlutusData.of(HexUtil.decodeHexString(whitelistCs))
        );
        return applyParameters(contract, params, "whitelist_spend");
    }

    /**
     * Build transfer logic withdraw script.
     * Contract: whitelist_transfer_logic.transfer.withdraw
     * Parameters: [programmable_logic_base_cred, whitelist_node_cs]
     */
    public PlutusScript buildTransferScript(String progLogicBaseScriptHash, String whitelistNodeCs) {
        var contract = getContract("whitelist_transfer_logic.transfer.withdraw");
        var progLogicCredential = Credential.fromScript(progLogicBaseScriptHash);
        var params = ListPlutusData.of(
                PlutusSerializationHelper.serialize(progLogicCredential),
                BytesPlutusData.of(HexUtil.decodeHexString(whitelistNodeCs))
        );
        return applyParameters(contract, params, "transfer");
    }

    // ========== Private Helpers ==========

    private SubstandardValidator getContract(String contractPath) {
        return substandardService.getSubstandardValidator(SUBSTANDARD_ID, contractPath)
                .orElseThrow(() -> new IllegalStateException(
                        "Whitelist multi-admin contract not found: " + contractPath
                ));
    }

    private PlutusScript applyParameters(SubstandardValidator contract, ListPlutusData params, String scriptName) {
        try {
            var parameterizedCode = AikenScriptUtil.applyParamToScript(params, contract.scriptBytes());
            var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(parameterizedCode, PlutusVersion.v3);
            log.debug("Built whitelist multi-admin {} script: {}", scriptName, script.getPolicyId());
            return script;
        } catch (Exception e) {
            throw new RuntimeException("Failed to build whitelist multi-admin " + scriptName + " script", e);
        }
    }
}
