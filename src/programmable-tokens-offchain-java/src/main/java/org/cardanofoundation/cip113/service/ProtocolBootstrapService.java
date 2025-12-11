package org.cardanofoundation.cip113.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.model.blueprint.Plutus;
import org.cardanofoundation.cip113.model.blueprint.Validator;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service for managing CIP-0113 protocol bootstrap parameters and contract blueprints.
 *
 * <p>This service is responsible for loading and providing access to the protocol's
 * foundational configuration, which includes:</p>
 *
 * <ul>
 *   <li><b>Protocol Bootstrap Parameters</b>: On-chain UTxO references and script hashes
 *       that define a protocol deployment</li>
 *   <li><b>Plutus Blueprint</b>: The compiled smart contracts (validators) from the
 *       Aiken build process</li>
 * </ul>
 *
 * <h2>Multi-Version Protocol Support</h2>
 * <p>The CIP-0113 protocol supports multiple deployments (versions) on the same network.
 * Each version is identified by its bootstrap transaction hash. This enables:</p>
 * <ul>
 *   <li>Protocol upgrades without breaking existing tokens</li>
 *   <li>Testing new versions alongside production</li>
 *   <li>Different protocol configurations for different use cases</li>
 * </ul>
 *
 * <h2>Configuration Files</h2>
 * <p>The service loads from classpath resources:</p>
 * <ul>
 *   <li>{@code protocol-bootstraps-{network}.json}: Array of protocol versions</li>
 *   <li>{@code plutus.json}: Aiken-compiled validator blueprint</li>
 * </ul>
 *
 * <h2>Protocol Bootstrap Structure</h2>
 * <p>Each protocol version contains:</p>
 * <pre>
 * {
 *   "txHash": "abc123...",                    // Bootstrap transaction hash
 *   "protocolParams": {                        // Global protocol parameters
 *     "scriptHash": "def456..."               // Protocol params script hash
 *   },
 *   "directoryMintParams": {                   // Registry mint policy params
 *     "txInput": { "txHash": "...", "outputIndex": 0 },
 *     "issuanceScriptHash": "..."
 *   },
 *   "programmableLogicBaseParams": {           // Base spend validator params
 *     "scriptHash": "..."
 *   },
 *   "programmableLogicGlobalParams": {         // Global stake validator params
 *     "scriptHash": "..."
 *   }
 * }
 * </pre>
 *
 * <h2>Thread Safety</h2>
 * <p>All bootstrap data is loaded at startup and stored in a {@link ConcurrentHashMap}
 * for thread-safe access. The data is immutable after initialization.</p>
 *
 * @see ProtocolBootstrapParams
 * @see Plutus
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ProtocolBootstrapService {

    /** JSON deserializer for parsing configuration files */
    private final ObjectMapper objectMapper;

    /** Network configuration for selecting the correct bootstrap file */
    private final AppConfig.Network network;

    /**
     * Default protocol version transaction hash.
     * <p>Configured via {@code programmable.token.default.txHash} property.</p>
     */
    @Value("${programmable.token.default.txHash:}")
    private String defaultTxHash;

    /**
     * The Aiken-compiled Plutus blueprint containing all validators.
     * <p>Loaded from {@code plutus.json} at startup.</p>
     */
    @Getter
    private Plutus plutus;

    /**
     * The default protocol bootstrap parameters.
     * <p>Either the version specified by {@code defaultTxHash} or the first available.</p>
     */
    @Getter
    private ProtocolBootstrapParams protocolBootstrapParams;

    /**
     * Map of all available protocol versions, keyed by transaction hash.
     * <p>Thread-safe for concurrent access.</p>
     */
    private final Map<String, ProtocolBootstrapParams> bootstrapsByTxHash = new ConcurrentHashMap<>();

    /**
     * Initialize the service by loading protocol configurations.
     *
     * <p>This method is called automatically after dependency injection. It:</p>
     * <ol>
     *   <li>Loads the network-specific bootstrap file (e.g., {@code protocol-bootstraps-preview.json})</li>
     *   <li>Populates the bootstraps map with all available versions</li>
     *   <li>Sets the default protocol version</li>
     *   <li>Loads the Plutus blueprint with compiled validators</li>
     * </ol>
     *
     * @throws RuntimeException if configuration files cannot be loaded or parsed
     */
    @PostConstruct
    public void init() {
        log.info("defaultTxHash: {}", defaultTxHash);
        log.info("network: {}", network.getNetwork());

        try {

            var protocolBootstrapFilename = String.format("protocol-bootstraps-%s.json", network.getNetwork());
            log.info("protocolBootstrapFilename: {}", protocolBootstrapFilename);

            // Load array of protocol bootstrap configurations
            var bootstrapsList = objectMapper.readValue(
                    this.getClass().getClassLoader().getResourceAsStream(protocolBootstrapFilename),
                    new TypeReference<List<ProtocolBootstrapParams>>() {}
            );

            // Store all bootstraps in map
            for (ProtocolBootstrapParams params : bootstrapsList) {
                bootstrapsByTxHash.put(params.txHash(), params);
                log.info("Loaded protocol bootstrap for txHash: {}", params.txHash());
            }

            // Set default protocol bootstrap params
            if (defaultTxHash != null && !defaultTxHash.isEmpty()) {
                protocolBootstrapParams = bootstrapsByTxHash.get(defaultTxHash);
                if (protocolBootstrapParams == null) {
                    log.warn("Default txHash {} not found in bootstraps, using first available", defaultTxHash);
                    protocolBootstrapParams = bootstrapsList.getFirst();
                } else {
                    log.info("Using default protocol bootstrap with txHash: {}", defaultTxHash);
                }
            } else {
                // No default specified, use first one
                protocolBootstrapParams = bootstrapsList.getFirst();
                log.info("No default txHash configured, using first bootstrap: {}", protocolBootstrapParams.txHash());
            }

            // Load plutus contracts
            plutus = objectMapper.readValue(
                    this.getClass().getClassLoader().getResourceAsStream("plutus.json"),
                    Plutus.class
            );

            log.info("Successfully initialized ProtocolBootstrapService with {} bootstrap versions", bootstrapsByTxHash.size());
        } catch (IOException e) {
            log.error("could not load bootstrap or protocol blueprint", e);
            throw new RuntimeException(e);
        }
    }

    /**
     * Get protocol bootstrap parameters by transaction hash.
     *
     * <p>Use this method to access a specific protocol version for multi-version
     * deployments. If the requested version doesn't exist, returns empty.</p>
     *
     * @param txHash the bootstrap transaction hash identifying the protocol version
     * @return the protocol bootstrap params, or empty if not found
     */
    public Optional<ProtocolBootstrapParams> getProtocolBootstrapParamsByTxHash(String txHash) {
        return Optional.ofNullable(bootstrapsByTxHash.get(txHash));
    }

    /**
     * Get all available protocol bootstrap configurations.
     *
     * <p>Returns an immutable copy of the bootstraps map. Useful for:</p>
     * <ul>
     *   <li>Listing available protocol versions in the UI</li>
     *   <li>Protocol version selection endpoints</li>
     *   <li>Health checks verifying all versions are loaded</li>
     * </ul>
     *
     * @return immutable map of txHash to ProtocolBootstrapParams
     */
    public Map<String, ProtocolBootstrapParams> getAllBootstraps() {
        return Map.copyOf(bootstrapsByTxHash);
    }

    /**
     * Get a compiled contract from the Plutus blueprint by title.
     *
     * <p>The title follows Aiken's naming convention: {@code module.validator_name.purpose}.
     * For example:</p>
     * <ul>
     *   <li>{@code "registry_mint.registry_mint.mint"}</li>
     *   <li>{@code "registry_spend.registry_spend.spend"}</li>
     *   <li>{@code "programmable_logic_base.programmable_logic_base.spend"}</li>
     * </ul>
     *
     * @param contractTitle the validator title as it appears in plutus.json
     * @return the compiled code (CBOR hex), or empty if not found
     */
    public Optional<String> getProtocolContract(String contractTitle) {
        return plutus.validators().stream()
                .filter(validator -> validator.title().equals(contractTitle))
                .findAny()
                .map(Validator::compiledCode);
    }

}
