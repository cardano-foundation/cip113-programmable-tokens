package org.cardanofoundation.cip113.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.Substandard;
import org.cardanofoundation.cip113.model.SubstandardValidator;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service for managing CIP-0113 substandard validator blueprints.
 *
 * <p>Substandards define the programmable behavior of tokens in the CIP-0113 protocol.
 * Each substandard provides a set of validators that implement specific token semantics,
 * such as:</p>
 *
 * <ul>
 *   <li><b>dummy</b>: Simple tokens with no transfer restrictions</li>
 *   <li><b>permissioned</b>: Tokens requiring issuer signature for transfers</li>
 *   <li><b>blacklistable</b>: Tokens with address blacklist enforcement</li>
 * </ul>
 *
 * <h2>Substandard Structure</h2>
 * <p>Each substandard is a directory under {@code resources/substandards/} containing
 * a {@code plutus.json} blueprint file. The directory name becomes the substandard ID.</p>
 *
 * <pre>
 * resources/substandards/
 * ├── dummy/
 * │   └── plutus.json          # Validators: issuance_logic, transfer_logic
 * ├── permissioned/
 * │   └── plutus.json          # Validators: issuance_logic, permissioned_transfer
 * └── blacklistable/
 *     └── plutus.json          # Validators: issuance_logic, blacklist_transfer, blacklist_check
 * </pre>
 *
 * <h2>Validator Triple</h2>
 * <p>When registering a token, users select three validators from a substandard:</p>
 * <ol>
 *   <li><b>Issue logic</b>: Validates token minting (required)</li>
 *   <li><b>Transfer logic</b>: Validates token transfers (required)</li>
 *   <li><b>Third-party logic</b>: Additional validation hook (optional)</li>
 * </ol>
 *
 * <h2>Blueprint Format</h2>
 * <p>Each {@code plutus.json} follows the Aiken blueprint format:</p>
 * <pre>
 * {
 *   "validators": [
 *     {
 *       "title": "issuance_logic.issuance_logic.else",
 *       "compiledCode": "59abcd...",
 *       "hash": "abc123..."
 *     },
 *     ...
 *   ]
 * }
 * </pre>
 *
 * <h2>Thread Safety</h2>
 * <p>Substandards are loaded at startup and cached in a {@link ConcurrentHashMap}
 * for thread-safe access. The data is immutable after initialization.</p>
 *
 * @see Substandard
 * @see SubstandardValidator
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class SubstandardService {

    /** JSON deserializer for parsing blueprint files */
    private final ObjectMapper objectMapper;

    /**
     * Thread-safe cache of all loaded substandards.
     * <p>Key: substandard ID (directory name), Value: parsed substandard</p>
     */
    private final Map<String, Substandard> substandardsCache = new ConcurrentHashMap<>();

    /**
     * Load all substandards from resources at startup.
     *
     * <p>This method scans the {@code classpath:substandards/} directory for
     * subdirectories containing {@code plutus.json} files. Each valid blueprint
     * is parsed and cached for fast access.</p>
     *
     * <p>Invalid or malformed blueprints are logged and skipped without
     * preventing other substandards from loading.</p>
     */
    @PostConstruct
    public void init() {
        log.info("Loading substandards from resources/substandards...");

        try {
            PathMatchingResourcePatternResolver resolver = new PathMatchingResourcePatternResolver();
            Resource[] resources = resolver.getResources("classpath:substandards/*/plutus.json");

            log.info("Found {} plutus.json files in substandards directory", resources.length);

            for (Resource resource : resources) {
                try {
                    // Extract folder name as ID from the resource path
                    // Path format: ...substandards/{foldername}/plutus.json
                    String uri = resource.getURI().toString();
                    String[] parts = uri.split("/substandards/");
                    if (parts.length < 2) {
                        log.warn("Could not extract folder name from path: {}", uri);
                        continue;
                    }
                    String folderName = parts[1].split("/")[0];

                    log.debug("Processing substandard: {}", folderName);

                    // Parse plutus.json
                    JsonNode root = objectMapper.readTree(resource.getInputStream());
                    JsonNode validatorsNode = root.get("validators");

                    if (validatorsNode == null || !validatorsNode.isArray()) {
                        log.warn("No validators array found in substandard: {}", folderName);
                        continue;
                    }

                    // Extract validators
                    List<SubstandardValidator> validators = new ArrayList<>();
                    for (JsonNode validatorNode : validatorsNode) {
                        String title = validatorNode.get("title").asText();
                        String compiledCode = validatorNode.get("compiledCode").asText();
                        String hash = validatorNode.get("hash").asText();

                        validators.add(new SubstandardValidator(title, compiledCode, hash));
                    }

                    // Create and cache the substandard
                    Substandard substandard = new Substandard(folderName, validators);
                    substandardsCache.put(folderName, substandard);

                    log.info("Loaded substandard '{}' with {} validators", folderName, validators.size());

                } catch (Exception e) {
                    log.error("Error loading substandard from resource: {}", resource.getFilename(), e);
                }
            }

            log.info("Successfully loaded {} substandards into cache", substandardsCache.size());

        } catch (IOException e) {
            log.error("Error scanning substandards directory", e);
        }
    }

    /**
     * Get all available substandards.
     *
     * <p>Returns a copy of the cached substandards. Useful for:</p>
     * <ul>
     *   <li>Listing available substandards in the UI</li>
     *   <li>Substandard selection dropdowns</li>
     *   <li>API endpoints exposing available options</li>
     * </ul>
     *
     * @return list of all loaded substandards (never null)
     */
    public List<Substandard> getAllSubstandards() {
        return new ArrayList<>(substandardsCache.values());
    }

    /**
     * Get a specific substandard by ID.
     *
     * <p>The ID corresponds to the directory name under {@code resources/substandards/}.
     * For example, {@code "dummy"}, {@code "permissioned"}, or {@code "blacklistable"}.</p>
     *
     * @param id the substandard ID (case-sensitive directory name)
     * @return the substandard, or empty if not found
     */
    public Optional<Substandard> getSubstandardById(String id) {
        return Optional.ofNullable(substandardsCache.get(id));
    }

    /**
     * Get a specific validator from a substandard by partial name match.
     *
     * <p>Searches the substandard's validators for one whose title contains the
     * specified name. This allows flexible matching without needing the full
     * Aiken-generated title.</p>
     *
     * <h3>Example</h3>
     * <pre>
     * // Full title: "issuance_logic.issuance_logic.else"
     * // Match with: "issuance_logic"
     * var validator = service.getSubstandardValidator("dummy", "issuance_logic");
     * </pre>
     *
     * @param id the substandard ID
     * @param name partial validator name to search for (case-sensitive)
     * @return the matching validator, or empty if not found
     */
    public Optional<SubstandardValidator> getSubstandardValidator(String id, String name) {
        return getSubstandardById(id)
                .flatMap(substandard -> substandard.validators()
                        .stream()
                        .filter(validator -> validator.title().contains(name))
                        .findAny());
    }

}
