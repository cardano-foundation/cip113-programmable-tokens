package org.cardanofoundation.cip113.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.blueprint.Plutus;
import org.cardanofoundation.cip113.model.blueprint.Validator;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.util.Optional;

/**
 * Service for loading and managing CIP-0113 protocol bootstrap configuration.
 *
 * <p>This service is responsible for loading two critical configuration files at startup:</p>
 * <ul>
 *   <li><strong>protocolBootstrap.json</strong>: Contains bootstrap transaction UTxO references,
 *       policy IDs, and other protocol initialization parameters.</li>
 *   <li><strong>plutus.json</strong>: The Aiken-generated blueprint containing compiled Plutus
 *       validator scripts and their metadata.</li>
 * </ul>
 *
 * <h2>Initialization</h2>
 * <p>Both files are loaded from the classpath during application startup via the {@code @PostConstruct}
 * lifecycle hook. If either file is missing or malformed, the service throws a RuntimeException,
 * preventing the application from starting in an invalid state.</p>
 *
 * <h2>Protocol Bootstrap Parameters</h2>
 * <p>The bootstrap parameters define:</p>
 * <ul>
 *   <li>Reference UTxO transaction IDs and output indices</li>
 *   <li>Protocol policy IDs for various validator scripts</li>
 *   <li>Initial stake key credentials</li>
 * </ul>
 *
 * <h2>Plutus Blueprint</h2>
 * <p>The Plutus blueprint provides:</p>
 * <ul>
 *   <li>Compiled validator bytecode (CBOR-encoded)</li>
 *   <li>Validator titles for lookup operations</li>
 *   <li>Script hashes and policy IDs</li>
 *   <li>Parameter specifications for script instantiation</li>
 * </ul>
 *
 * <h2>Usage Example</h2>
 * <pre>{@code
 * @Autowired
 * private ProtocolBootstrapService bootstrapService;
 *
 * public void buildTransaction() {
 *     // Get bootstrap UTxO references
 *     var params = bootstrapService.getProtocolBootstrapParams();
 *     var refTxId = params.getReferenceTxId();
 *
 *     // Get compiled validator code
 *     Optional<String> code = bootstrapService.getProtocolContract("registry_mint.mint");
 *     code.ifPresent(compiledCode -> {
 *         // Use compiled code for transaction building
 *     });
 * }
 * }</pre>
 *
 * @see Plutus
 * @see ProtocolBootstrapParams
 * @see Validator
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ProtocolBootstrapService {

    /** Jackson ObjectMapper for JSON deserialization */
    private final ObjectMapper objectMapper;

    /**
     * The parsed Aiken Plutus blueprint containing all validator scripts.
     * <p>
     * This object provides access to:
     * <ul>
     *   <li>Compiled validator bytecode via {@link Validator#compiledCode()}</li>
     *   <li>Validator titles for identification</li>
     *   <li>Script parameters and metadata</li>
     * </ul>
     */
    @Getter
    private Plutus plutus;

    /**
     * Protocol bootstrap parameters loaded from protocolBootstrap.json.
     * <p>
     * Contains the UTxO references and policy IDs needed to interact with
     * the deployed protocol instance on-chain.
     */
    @Getter
    private ProtocolBootstrapParams protocolBootstrapParams;

    /**
     * Initializes the service by loading bootstrap and blueprint files.
     *
     * <p>Called automatically by Spring after dependency injection is complete.
     * Loads both configuration files from the classpath and parses them into
     * their respective domain objects.</p>
     *
     * <p>Files expected in classpath:</p>
     * <ul>
     *   <li><code>protocolBootstrap.json</code> - Protocol bootstrap configuration</li>
     *   <li><code>plutus.json</code> - Aiken-generated Plutus blueprint</li>
     * </ul>
     *
     * @throws RuntimeException if either file cannot be loaded or parsed
     */
    @PostConstruct
    public void init() {
        try {
            // Load protocol bootstrap parameters (UTxO references, policy IDs)
            protocolBootstrapParams = objectMapper.readValue(
                this.getClass().getClassLoader().getResourceAsStream("protocolBootstrap.json"),
                ProtocolBootstrapParams.class
            );

            // Load Aiken-generated Plutus blueprint (compiled validators)
            plutus = objectMapper.readValue(
                this.getClass().getClassLoader().getResourceAsStream("plutus.json"),
                Plutus.class
            );

            log.info("Successfully loaded protocol bootstrap and Plutus blueprint");
            log.debug("Loaded {} validators from blueprint", plutus.validators().size());
        } catch (IOException e) {
            log.error("Could not load bootstrap or protocol blueprint: {}", e.getMessage());
            throw new RuntimeException("Failed to initialize protocol bootstrap service", e);
        }
    }

    /**
     * Retrieves compiled validator code by its title.
     *
     * <p>Validator titles follow the Aiken naming convention:</p>
     * <ul>
     *   <li>{@code "registry_mint.mint"} - Registry NFT minting policy</li>
     *   <li>{@code "programmable_logic_base.spend"} - Token spend validator</li>
     *   <li>{@code "blacklist_mint.mint"} - Blacklist management policy</li>
     * </ul>
     *
     * @param contractTitle The exact title of the validator as defined in the blueprint
     * @return Optional containing the CBOR-encoded compiled code, or empty if not found
     *
     * @see Validator#title()
     * @see Validator#compiledCode()
     */
    public Optional<String> getProtocolContract(String contractTitle) {
        return plutus.validators().stream()
            .filter(validator -> validator.title().equals(contractTitle))
            .findAny()
            .map(Validator::compiledCode);
    }

}
