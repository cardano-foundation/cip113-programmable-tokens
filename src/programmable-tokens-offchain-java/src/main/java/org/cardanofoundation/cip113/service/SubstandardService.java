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
 * Service for managing CIP-0113 Substandards.
 *
 * <p>A substandard is a collection of pre-built validators (transfer logic, issuance logic)
 * that implement specific token behavior patterns. Examples include:
 * <ul>
 *   <li><b>dummy</b>: Simple validators for testing</li>
 *   <li><b>freeze-and-seize</b>: Validators with blacklist functionality</li>
 *   <li><b>whitelist</b>: Validators that restrict transfers to approved addresses</li>
 * </ul>
 *
 * <h2>Directory Structure</h2>
 * <p>Substandards are loaded from the classpath at startup. Each substandard must have:
 * <pre>
 * resources/substandards/{substandard-id}/plutus.json
 * </pre>
 *
 * <p>The {@code plutus.json} file is an Aiken blueprint containing compiled validators.
 *
 * <h2>Caching</h2>
 * <p>All substandards are loaded into an in-memory cache at startup. The cache uses
 * {@link ConcurrentHashMap} for thread-safe access in a multi-threaded web server.
 *
 * <h2>Usage Example</h2>
 * <pre>{@code
 * // Get all substandards
 * List<Substandard> all = substandardService.getAllSubstandards();
 *
 * // Get a specific substandard
 * Optional<Substandard> dummy = substandardService.getSubstandardById("dummy");
 *
 * // Get a specific validator from a substandard
 * Optional<SubstandardValidator> transferLogic =
 *     substandardService.getSubstandardValidator("dummy", "transfer_logic");
 * }</pre>
 *
 * @see Substandard for the substandard data model
 * @see SubstandardValidator for individual validator information
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class SubstandardService {

    /** JSON parser for reading Aiken blueprints */
    private final ObjectMapper objectMapper;

    /**
     * Thread-safe in-memory cache of all substandards.
     * Key is the substandard ID (folder name), value is the loaded Substandard.
     */
    private final Map<String, Substandard> substandardsCache = new ConcurrentHashMap<>();

    /**
     * Load all substandards from the classpath at application startup.
     *
     * <p>This method scans {@code classpath:substandards/}{@code *}{@code /plutus.json} for all
     * available substandard blueprints and loads them into the cache.
     *
     * <p>Each blueprint is parsed to extract:
     * <ul>
     *   <li>Validator titles (e.g., "transfer_logic.transfer_logic.withdraw")</li>
     *   <li>Compiled script bytes (CBOR hex)</li>
     *   <li>Script hashes (policy IDs)</li>
     * </ul>
     *
     * <p>Errors loading individual substandards are logged but don't prevent
     * other substandards from loading.
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

                    // Parse plutus.json (Aiken blueprint format)
                    JsonNode root = objectMapper.readTree(resource.getInputStream());
                    JsonNode validatorsNode = root.get("validators");

                    if (validatorsNode == null || !validatorsNode.isArray()) {
                        log.warn("No validators array found in substandard: {}", folderName);
                        continue;
                    }

                    // Extract validators from the blueprint
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
     * Get all loaded substandards.
     *
     * @return list of all substandards, or empty list if none loaded
     */
    public List<Substandard> getAllSubstandards() {
        return new ArrayList<>(substandardsCache.values());
    }

    /**
     * Get a specific substandard by its ID.
     *
     * <p>The ID corresponds to the folder name under {@code resources/substandards/}.
     *
     * @param id the substandard ID (folder name, e.g., "dummy", "freeze-and-seize")
     * @return the substandard if found, empty otherwise
     */
    public Optional<Substandard> getSubstandardById(String id) {
        return Optional.ofNullable(substandardsCache.get(id));
    }

    /**
     * Get a specific validator from a substandard by partial name match.
     *
     * <p>Validator titles in Aiken blueprints follow the pattern:
     * {@code module_name.validator_name.purpose} (e.g., "transfer_logic.transfer_logic.withdraw").
     * This method matches if the validator title <i>contains</i> the given name.
     *
     * <h3>Example</h3>
     * <pre>{@code
     * // Find the transfer logic validator in the "dummy" substandard
     * Optional<SubstandardValidator> validator =
     *     getSubstandardValidator("dummy", "transfer_logic");
     * }</pre>
     *
     * @param id the substandard ID
     * @param name partial validator name to match (uses contains matching)
     * @return the first matching validator, or empty if not found
     */
    public Optional<SubstandardValidator> getSubstandardValidator(String id, String name) {
        return getSubstandardById(id)
                .flatMap(substandard -> substandard.validators()
                        .stream()
                        .filter(validator -> validator.title().contains(name))
                        .findAny());
    }

}
