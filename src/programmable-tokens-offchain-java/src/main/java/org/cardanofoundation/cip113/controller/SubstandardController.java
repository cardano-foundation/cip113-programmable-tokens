package org.cardanofoundation.cip113.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
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
@Tag(name = "Substandards", description = "CIP-113 substandard validators for programmable tokens")
public class SubstandardController {

    private final SubstandardService substandardService;

    /**
     * Get all substandards
     *
     * @return list of all substandards with their validators
     */
    @GetMapping
    @Operation(
            summary = "List all substandards",
            description = "Returns all available CIP-113 substandards with their compiled validators. " +
                    "Substandards define the transfer validation logic for programmable tokens."
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Successfully retrieved substandards",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(implementation = Substandard.class))),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
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
    @Operation(
            summary = "Get substandard by ID",
            description = "Returns a specific substandard by its ID (folder name). " +
                    "Common IDs include: blacklist, whitelist, transfer-limit."
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Substandard found",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(implementation = Substandard.class))),
            @ApiResponse(responseCode = "404", description = "Substandard not found"),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    public ResponseEntity<Substandard> getSubstandardById(
            @Parameter(description = "Substandard ID (folder name)", example = "blacklist")
            @PathVariable String id) {
        log.debug("GET /substandards/{} - fetching substandard by id", id);
        return substandardService.getSubstandardById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}
