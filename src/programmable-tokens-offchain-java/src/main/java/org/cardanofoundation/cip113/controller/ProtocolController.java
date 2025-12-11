package org.cardanofoundation.cip113.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.blueprint.Plutus;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * REST controller for accessing CIP-0113 protocol configuration.
 *
 * <p>This controller exposes the Aiken-generated Plutus blueprint and
 * protocol bootstrap parameters needed by clients to interact with
 * the CIP-0113 protocol.</p>
 *
 * <h2>Endpoints</h2>
 * <ul>
 *   <li>{@code GET /api/v1/protocol/blueprint} - Full Plutus blueprint with compiled validators</li>
 *   <li>{@code GET /api/v1/protocol/bootstrap} - Bootstrap parameters (UTxO refs, policy IDs)</li>
 * </ul>
 *
 * <h2>Use Cases</h2>
 * <ul>
 *   <li>Frontend clients need blueprint to build transactions locally</li>
 *   <li>External tools need policy IDs for token identification</li>
 *   <li>Debugging and verification of protocol deployment</li>
 * </ul>
 *
 * @see ProtocolBootstrapService
 * @see Plutus
 * @see ProtocolBootstrapParams
 */
@RestController
@RequestMapping("${apiPrefix}/protocol")
@RequiredArgsConstructor
@Slf4j
@Tag(name = "Protocol", description = "Protocol configuration and blueprint endpoints")
public class ProtocolController {

    private final ProtocolBootstrapService protocolBootstrapService;

    /**
     * Get the full Aiken-generated Plutus blueprint.
     *
     * <p>The blueprint contains compiled validator bytecode and metadata
     * for all CIP-0113 validators. Frontend clients use this to build
     * transactions with embedded script references.</p>
     *
     * @return the Plutus blueprint with all validators
     */
    @GetMapping("/blueprint")
    @Operation(
            summary = "Get Plutus blueprint",
            description = "Returns the full Aiken-generated Plutus blueprint containing compiled " +
                    "validator bytecode and metadata for all CIP-0113 validators. " +
                    "Frontend clients use this to build transactions with embedded script references."
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Blueprint retrieved successfully",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(implementation = Plutus.class))),
            @ApiResponse(responseCode = "500", description = "Blueprint not loaded or internal error")
    })
    public ResponseEntity<Plutus> getPlutus() {
        return ResponseEntity.ok(protocolBootstrapService.getPlutus());
    }

    /**
     * Get the protocol bootstrap parameters.
     *
     * <p>Bootstrap parameters define the specific deployment instance,
     * including reference UTxO IDs and policy IDs for all protocol
     * components.</p>
     *
     * @return the protocol bootstrap configuration
     */
    @GetMapping("/bootstrap")
    @Operation(
            summary = "Get bootstrap parameters",
            description = "Returns the protocol bootstrap parameters including reference UTxO IDs, " +
                    "policy IDs, and script hashes for the deployed CIP-0113 protocol instance. " +
                    "These parameters are network-specific (mainnet/testnet)."
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Bootstrap parameters retrieved successfully",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(implementation = ProtocolBootstrapParams.class))),
            @ApiResponse(responseCode = "500", description = "Bootstrap parameters not loaded or internal error")
    })
    public ResponseEntity<ProtocolBootstrapParams> getLatest() {
        return ResponseEntity.ok(protocolBootstrapService.getProtocolBootstrapParams());
    }
}
