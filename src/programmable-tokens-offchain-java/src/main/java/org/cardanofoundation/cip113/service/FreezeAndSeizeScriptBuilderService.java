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
import com.easy1staking.util.Pair;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.SubstandardValidator;
import org.cardanofoundation.cip113.util.PlutusSerializationHelper;
import org.springframework.stereotype.Service;

import static org.cardanofoundation.cip113.util.PlutusSerializationHelper.serialize;

/**
 * Service for building parameterized Freeze-and-Seize scripts.
 * <p>
 * This service eliminates code duplication across FreezeAndSeizeHandler by centralizing
 * script parameterization logic for all freeze-and-seize contracts:
 * <ul>
 *   <li><b>Issuer Admin Contract</b> - Parameterized with admin PKH</li>
 *   <li><b>Transfer Contract</b> - Parameterized with prog logic base + blacklist policy</li>
 *   <li><b>Blacklist Mint Contract</b> - Parameterized with bootstrap UTXO + admin PKH</li>
 *   <li><b>Blacklist Spend Contract</b> - Parameterized with blacklist mint policy ID</li>
 * </ul>
 * <p>
 * All methods build fresh scripts (no caching) and are thread-safe.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class FreezeAndSeizeScriptBuilderService {

    private static final String SUBSTANDARD_ID = "freeze-and-seize";

    private final SubstandardService substandardService;

    /**
     * Build Issuer Admin Contract (withdraw)
     * <p>
     * Contract: example_transfer_logic.issuer_admin_contract.withdraw
     * Parameters: [admin_pkh]
     *
     * @param adminPubKeyHash Admin's payment credential hash (hex string)
     * @return Parameterized PlutusScript v3
     */
    public PlutusScript buildIssuerAdminScript(Credential adminPubKeyHash) {
        var contract = getContract("example_transfer_logic.issuer_admin_contract.withdraw");

        var params = ListPlutusData.of(serialize(adminPubKeyHash));

        return applyParameters(contract, params, "issuer_admin");
    }

    /**
     * Build Transfer Contract (withdraw)
     * <p>
     * Contract: example_transfer_logic.transfer.withdraw
     * Parameters: [prog_logic_base_credential, blacklist_node_policy_id]
     *
     * @param progLogicBaseScriptHash Protocol's programmable logic base script hash
     * @param blacklistNodePolicyId   Blacklist node policy ID for this deployment
     * @return Parameterized PlutusScript v3
     */
    public PlutusScript buildTransferScript(
            String progLogicBaseScriptHash,
            String blacklistNodePolicyId) {

        var contract = getContract("example_transfer_logic.transfer.withdraw");

        var progLogicCredential = Credential.fromScript(progLogicBaseScriptHash);

        var params = ListPlutusData.of(
                PlutusSerializationHelper.serialize(progLogicCredential),
                BytesPlutusData.of(HexUtil.decodeHexString(blacklistNodePolicyId))
        );

        return applyParameters(contract, params, "transfer");
    }

    /**
     * Build Blacklist Mint Contract (mint)
     * <p>
     * Contract: blacklist_mint.blacklist_mint.mint
     * Parameters: [bootstrap_utxo, admin_pkh]
     *
     * @param bootstrapTxInput Bootstrap UTXO reference (tx hash + output index)
     * @param adminPubKeyHash  Admin's payment credential hash (hex string)
     * @return Parameterized PlutusScript v3
     */
    public PlutusScript buildBlacklistMintScript(
            TransactionInput bootstrapTxInput,
            String adminPubKeyHash) {

        var contract = getContract("blacklist_mint.blacklist_mint.mint");

        var serializedTxInput = PlutusSerializationHelper.serialize(bootstrapTxInput);

        var params = ListPlutusData.of(
                serializedTxInput,
                BytesPlutusData.of(HexUtil.decodeHexString(adminPubKeyHash))
        );

        return applyParameters(contract, params, "blacklist_mint");
    }

    /**
     * Build Blacklist Spend Contract (spend)
     * <p>
     * Contract: blacklist_spend.blacklist_spend.spend
     * Parameters: [blacklist_mint_policy_id]
     *
     * @param blacklistMintPolicyId Policy ID from the blacklist mint script
     * @return Parameterized PlutusScript v3
     */
    public PlutusScript buildBlacklistSpendScript(String blacklistMintPolicyId) {
        var contract = getContract("blacklist_spend.blacklist_spend.spend");

        var params = ListPlutusData.of(
                BytesPlutusData.of(HexUtil.decodeHexString(blacklistMintPolicyId))
        );

        return applyParameters(contract, params, "blacklist_spend");
    }

    /**
     * Build both blacklist scripts at once (mint + spend)
     * <p>
     * Convenience method since:
     * <ol>
     *   <li>Blacklist spend depends on blacklist mint policy ID</li>
     *   <li>They're always used together</li>
     * </ol>
     *
     * @param bootstrapTxInput Bootstrap UTXO reference
     * @param adminPubKeyHash  Admin's payment credential hash
     * @return Pair of (mintScript, spendScript)
     */
    public Pair<PlutusScript, PlutusScript> buildBlacklistScripts(
            TransactionInput bootstrapTxInput,
            String adminPubKeyHash) {

        try {
            // Build mint script first
            var mintScript = buildBlacklistMintScript(bootstrapTxInput, adminPubKeyHash);

            // Use mint script's policy ID to build spend script
            var spendScript = buildBlacklistSpendScript(mintScript.getPolicyId());

            return new Pair<>(mintScript, spendScript);
        } catch (Exception e) {
            throw new RuntimeException(
                    "Failed to build blacklist scripts",
                    e
            );
        }
    }

    // ========== Private Helpers ==========

    /**
     * Get contract from substandard service
     */
    private SubstandardValidator getContract(String contractPath) {
        return substandardService.getSubstandardValidator(SUBSTANDARD_ID, contractPath)
                .orElseThrow(() -> new IllegalStateException(
                        "Freeze-and-seize contract not found: " + contractPath
                ));
    }

    /**
     * Apply parameters to contract and build PlutusScript v3
     */
    private PlutusScript applyParameters(
            SubstandardValidator contract,
            ListPlutusData params,
            String scriptName) {

        try {
            var parameterizedCode = AikenScriptUtil.applyParamToScript(
                    params,
                    contract.scriptBytes()
            );

            var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    parameterizedCode,
                    PlutusVersion.v3
            );

            log.debug("Built freeze-and-seize {} script", scriptName);
            return script;

        } catch (Exception e) {
            throw new RuntimeException(
                    "Failed to build freeze-and-seize " + scriptName + " script",
                    e
            );
        }
    }
}
