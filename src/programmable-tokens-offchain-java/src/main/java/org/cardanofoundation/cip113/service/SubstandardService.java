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
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Service
@Slf4j
@RequiredArgsConstructor
public class SubstandardService {

    private final ObjectMapper objectMapper;

    // Thread-safe in-memory cache of all substandards
    private final Map<String, Substandard> substandardsCache = new ConcurrentHashMap<>();

    /**
     * Load all substandards from resources/substandards at startup
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
     * Get all substandards
     *
     * @return list of all substandards
     */
    public List<Substandard> getAllSubstandards() {
        return new ArrayList<>(substandardsCache.values());
    }

    /**
     * Get a specific substandard by ID (folder name)
     *
     * @param id the substandard ID (folder name)
     * @return the substandard or empty if not found
     */
    public Optional<Substandard> getSubstandardById(String id) {
        return Optional.ofNullable(substandardsCache.get(id));
    }
}
