package org.cardanofoundation.cip113.util;

import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.model.AddressUtxoEntity;
import com.easy1staking.cardano.util.UtxoUtil;
import lombok.experimental.UtilityClass;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;

import java.math.BigInteger;
import java.util.List;

/**
 * Utility class for common transaction building operations.
 * Extracts frequently used transaction building logic to reduce code duplication.
 */
@UtilityClass
@Slf4j
public class TransactionBuilderHelper {

    /**
     * Create a programmable token target address (script + delegation)
     *
     * @param scriptHash The script hash for payment credential
     * @param delegationAddress The delegation address
     * @param network The Cardano network
     * @return The target address
     */
    public static Address createProgrammableTokenAddress(
            String scriptHash,
            Address delegationAddress,
            AppConfig.Network network
    ) {
        return AddressProvider.getBaseAddress(
                Credential.fromScript(scriptHash),
                delegationAddress.getDelegationCredential().get(),
                network.getCardanoNetwork()
        );
    }

    /**
     * Create a Value object with ADA and native assets
     *
     * @param lovelace The amount of lovelace
     * @param policyId The policy ID of the native asset
     * @param assetName The asset name (hex)
     * @param quantity The quantity of the asset
     * @return Value object
     */
    public static Value createValueWithAsset(
            BigInteger lovelace,
            String policyId,
            String assetName,
            BigInteger quantity
    ) {
        var asset = Asset.builder()
                .name("0x" + assetName)
                .value(quantity)
                .build();

        return Value.builder()
                .coin(lovelace)
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(policyId)
                                .assets(List.of(asset))
                                .build()
                ))
                .build();
    }

    /**
     * Create a simple Asset object
     *
     * @param assetName The asset name (hex, without 0x prefix)
     * @param quantity The quantity
     * @return Asset object
     */
    public static Asset createAsset(String assetName, BigInteger quantity) {
        return Asset.builder()
                .name("0x" + assetName)
                .value(quantity)
                .build();
    }

    /**
     * Convert AddressUtxoEntity to Utxo
     *
     * @param entity The entity to convert
     * @return Utxo object
     */
    public static com.bloxbean.cardano.client.api.model.Utxo toUtxo(AddressUtxoEntity entity) {
        return UtxoUtil.toUtxo(entity);
    }

    /**
     * Get reward address for a script
     *
     * @param script The Plutus script
     * @param network The Cardano network
     * @return Reward address
     */
    public static Address getRewardAddress(PlutusScript script, AppConfig.Network network) {
        return AddressProvider.getRewardAddress(script, network.getCardanoNetwork());
    }

    /**
     * Get enterprise address for a script
     *
     * @param script The Plutus script
     * @param network The Cardano network
     * @return Enterprise address
     */
    public static Address getEnterpriseAddress(PlutusScript script, AppConfig.Network network) {
        return AddressProvider.getEntAddress(script, network.getCardanoNetwork());
    }

    /**
     * Create minimum ADA value (2 ADA)
     *
     * @return BigInteger representing 2 ADA in lovelace
     */
    public static BigInteger minAda() {
        return Amount.ada(2).getQuantity();
    }

    /**
     * Create 1 ADA value
     *
     * @return BigInteger representing 1 ADA in lovelace
     */
    public static BigInteger oneAda() {
        return Amount.ada(1).getQuantity();
    }

    /**
     * Log script hash
     *
     * @param name Script name for logging
     * @param script The script
     */
    public static void logScriptHash(String name, PlutusScript script) {
        try {
            log.info("{}: {}", name, HexUtil.encodeHexString(script.getScriptHash()));
        } catch (Exception e) {
            log.warn("{}: (could not compute hash)", name);
        }
    }

    /**
     * Log script policy ID
     *
     * @param name Script name for logging
     * @param script The script
     */
    public static void logPolicyId(String name, PlutusScript script) {
        try {
            log.info("{}: {}", name, script.getPolicyId());
        } catch (Exception e) {
            log.warn("{}: (could not compute policy ID)", name);
        }
    }
}
