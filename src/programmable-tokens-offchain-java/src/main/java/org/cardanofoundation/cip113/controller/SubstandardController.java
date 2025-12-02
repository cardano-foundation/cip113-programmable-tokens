package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.Substandard;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * REST controller for accessing CIP-0113 substandard validators.
 *
 * <p>Substandards are predefined programmable token configurations that implement
 * specific transfer logic. This controller exposes the available substandards
 * that can be used when registering new programmable tokens.</p>
 *
 * <h2>Endpoints</h2>
 * <ul>
 *   <li>{@code GET /api/v1/substandards} - List all available substandards</li>
 *   <li>{@code GET /api/v1/substandards/{id}} - Get a specific substandard by ID</li>
 * </ul>
 *
 * <h2>Substandard Structure</h2>
 * <p>Each substandard contains:</p>
 * <ul>
 *   <li><strong>id</strong>: Folder name identifier (e.g., "blacklist")</li>
 *   <li><strong>name</strong>: Human-readable name from blueprint</li>
 *   <li><strong>validators</strong>: List of compiled Plutus validators</li>
 * </ul>
 *
 * <h2>Common Substandards</h2>
 * <ul>
 *   <li><strong>blacklist</strong>: Block transfers to/from sanctioned addresses</li>
 *   <li><strong>whitelist</strong>: Allow transfers only to approved addresses</li>
 *   <li><strong>transfer-limit</strong>: Enforce maximum transfer amounts</li>
 * </ul>
 *
 * @see SubstandardService
 * @see Substandard
 */
@RestController
@RequestMapping("${apiPrefix}/substandards")
@RequiredArgsConstructor
@Slf4j
public class SubstandardController {

    private final SubstandardService substandardService;

    /**
     * Get all substandards
     *
     * @return list of all substandards with their validators
     */
    @GetMapping
    public ResponseEntity<List<Substandard>> getAllSubstandards() {
        log.debug("GET /substandards - fetching all substandards");
        List<Substandard> substandards = substandardService.getAllSubstandards();
        return ResponseEntity.ok(substandards);
    }

    /**
     * Get a specific substandard by ID (folder name)
     *
     * @param id the substandard ID (folder name in substandards directory)
     * @return the substandard with its validators or 404 if not found
     */
    @GetMapping("/{id}")
    public ResponseEntity<Substandard> getSubstandardById(@PathVariable String id) {
        log.debug("GET /substandards/{} - fetching substandard by id", id);
        return substandardService.getSubstandardById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}
