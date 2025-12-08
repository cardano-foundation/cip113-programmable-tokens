package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.*;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service for building parameterized protocol scripts based on protocol version.
 * This eliminates code duplication across controllers by centralizing script parameterization logic.
 * Scripts are cached per protocol version for performance.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ProtocolScriptBuilderService {

    private final ProtocolBootstrapService protocolBootstrapService;

    // Cache: protocolTxHash -> scriptName -> PlutusScript
    private final Map<String, Map<String, PlutusScript>> scriptCache = new ConcurrentHashMap<>();

    /**
     * Get parameterized Directory Mint (registry_mint) script
     * Parameters: utxo (tx hash + output index), issuance script hash
     */
    public PlutusScript getParameterizedDirectoryMintScript(ProtocolBootstrapParams protocolParams) {
        return getCachedOrBuild(protocolParams.txHash(), "directory_mint", () -> {
            var utxo1 = protocolParams.directoryMintParams().txInput();
            var issuanceScriptHash = protocolParams.directoryMintParams().issuanceScriptHash();

            var directoryParameters = ListPlutusData.of(
                    ConstrPlutusData.of(0,
                            BytesPlutusData.of(HexUtil.decodeHexString(utxo1.txHash())),
                            BigIntPlutusData.of(utxo1.outputIndex())),
                    BytesPlutusData.of(HexUtil.decodeHexString(issuanceScriptHash))
            );

            var contractOpt = protocolBootstrapService.getProtocolContract("registry_mint.registry_mint.mint");
            if (contractOpt.isEmpty()) {
                throw new IllegalStateException("Registry mint contract not found");
            }

            var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(directoryParameters, contractOpt.get()),
                    PlutusVersion.v3
            );

            try {
                log.debug("Built directory mint script with hash: {}", HexUtil.encodeHexString(script.getScriptHash()));
            } catch (Exception e) {
                log.debug("Built directory mint script (could not compute hash)");
            }
            return script;
        });
    }

    /**
     * Get parameterized Directory Spend (registry_spend) script
     * Parameters: protocol params script hash
     */
    public PlutusScript getParameterizedDirectorySpendScript(ProtocolBootstrapParams protocolParams) {
        return getCachedOrBuild(protocolParams.txHash(), "directory_spend", () -> {
            var protocolParamsScriptHash = protocolParams.protocolParams().scriptHash();

            var directorySpendParameters = ListPlutusData.of(
                    BytesPlutusData.of(HexUtil.decodeHexString(protocolParamsScriptHash))
            );

            var contractOpt = protocolBootstrapService.getProtocolContract("registry_spend.registry_spend.spend");
            if (contractOpt.isEmpty()) {
                throw new IllegalStateException("Registry spend contract not found");
            }

            var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(directorySpendParameters, contractOpt.get()),
                    PlutusVersion.v3
            );

            try {
                log.debug("Built directory spend script with hash: {}", HexUtil.encodeHexString(script.getScriptHash()));
            } catch (Exception e) {
                log.debug("Built directory spend script (could not compute hash)");
            }
            return script;
        });
    }

    /**
     * Get parameterized Issuance Mint script
     * Parameters: programmable logic base script hash, substandard issue script hash
     */
    public PlutusScript getParameterizedIssuanceMintScript(
            ProtocolBootstrapParams protocolParams,
            PlutusScript substandardIssueScript
    ) {
        try {
            // Don't cache this one since it depends on substandard script which varies
            var programmableLogicBaseScriptHash = protocolParams.programmableLogicBaseParams().scriptHash();

            var issuanceParameters = ListPlutusData.of(
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicBaseScriptHash))
                    ),
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(substandardIssueScript.getScriptHash())
                    )
            );

            var contractOpt = protocolBootstrapService.getProtocolContract("issuance_mint.issuance_mint.mint");
            if (contractOpt.isEmpty()) {
                throw new IllegalStateException("Issuance mint contract not found");
            }

            var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(issuanceParameters, contractOpt.get()),
                    PlutusVersion.v3
            );

            try {
                log.debug("Built issuance mint script with policy ID: {}", script.getPolicyId());
            } catch (Exception e) {
                log.debug("Built issuance mint script (could not compute policy ID)");
            }
            return script;
        } catch (Exception e) {
            throw new RuntimeException("Failed to build issuance mint script", e);
        }
    }

    /**
     * Get parameterized Programmable Logic Base script
     * Parameters: protocol params script hash, programmable logic global script hash
     */
    public PlutusScript getParameterizedProgrammableLogicBaseScript(ProtocolBootstrapParams protocolParams) {
        return getCachedOrBuild(protocolParams.txHash(), "programmable_logic_base", () -> {
            var protocolParamsScriptHash = protocolParams.protocolParams().scriptHash();
            var programmableLogicGlobalScriptHash = protocolParams.programmableLogicGlobalPrams().scriptHash();

            var parameters = ListPlutusData.of(
                    BytesPlutusData.of(HexUtil.decodeHexString(protocolParamsScriptHash)),
                    BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicGlobalScriptHash))
            );

            var contractOpt = protocolBootstrapService.getProtocolContract("programmable_logic_base.programmable_logic_base.spend");
            if (contractOpt.isEmpty()) {
                throw new IllegalStateException("Programmable logic base contract not found");
            }

            var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(parameters, contractOpt.get()),
                    PlutusVersion.v3
            );

            try {
                log.debug("Built programmable logic base script with hash: {}", HexUtil.encodeHexString(script.getScriptHash()));
            } catch (Exception e) {
                log.debug("Built programmable logic base script (could not compute hash)");
            }
            return script;
        });
    }

    /**
     * Get parameterized Programmable Logic Global script
     * Parameters: protocol params script hash
     */
    public PlutusScript getParameterizedProgrammableLogicGlobalScript(ProtocolBootstrapParams protocolParams) {
        return getCachedOrBuild(protocolParams.txHash(), "programmable_logic_global", () -> {
            var protocolParamsScriptHash = protocolParams.protocolParams().scriptHash();

            var parameters = ListPlutusData.of(
                    BytesPlutusData.of(HexUtil.decodeHexString(protocolParamsScriptHash))
            );

            var contractOpt = protocolBootstrapService.getProtocolContract("programmable_logic_global.programmable_logic_global.spend");
            if (contractOpt.isEmpty()) {
                throw new IllegalStateException("Programmable logic global contract not found");
            }

            var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(parameters, contractOpt.get()),
                    PlutusVersion.v3
            );

            try {
                log.debug("Built programmable logic global script with hash: {}", HexUtil.encodeHexString(script.getScriptHash()));
            } catch (Exception e) {
                log.debug("Built programmable logic global script (could not compute hash)");
            }
            return script;
        });
    }

    /**
     * Clear cache for a specific protocol version
     */
    public void clearCache(String protocolTxHash) {
        scriptCache.remove(protocolTxHash);
        log.info("Cleared script cache for protocol version: {}", protocolTxHash);
    }

    /**
     * Clear all caches
     */
    public void clearAllCaches() {
        scriptCache.clear();
        log.info("Cleared all script caches");
    }

    /**
     * Helper method to get cached script or build it
     */
    private PlutusScript getCachedOrBuild(String protocolTxHash, String scriptName, ScriptBuilder builder) {
        return scriptCache
                .computeIfAbsent(protocolTxHash, k -> new ConcurrentHashMap<>())
                .computeIfAbsent(scriptName, k -> builder.build());
    }

    @FunctionalInterface
    private interface ScriptBuilder {
        PlutusScript build();
    }
}
