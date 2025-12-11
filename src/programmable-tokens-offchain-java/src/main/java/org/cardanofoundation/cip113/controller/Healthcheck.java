package org.cardanofoundation.cip113.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Health check endpoint for container orchestration and monitoring.
 */
@RestController
@RequestMapping("/healthcheck")
@Slf4j
@RequiredArgsConstructor
@Tag(name = "Health", description = "Service health checks")
public class Healthcheck {

    private final ProtocolBootstrapService protocolBootstrapService;
    private final SubstandardService substandardService;

    /**
     * Basic health check - returns 200 OK if the service is running.
     */
    @GetMapping
    @Operation(
            summary = "Basic health check",
            description = "Returns 200 OK if the service is running. Use for Kubernetes liveness probes."
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Service is healthy")
    })
    public ResponseEntity<Map<String, Object>> healthCheck() {
        Map<String, Object> health = new LinkedHashMap<>();
        health.put("status", "UP");
        health.put("timestamp", Instant.now().toString());
        return ResponseEntity.ok(health);
    }

    /**
     * Detailed health check - returns service status with component details.
     */
    @GetMapping("/details")
    @Operation(
            summary = "Detailed health check",
            description = "Returns comprehensive health status including protocol bootstrap and substandards. " +
                    "Use for Kubernetes readiness probes."
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Health details retrieved")
    })
    public ResponseEntity<Map<String, Object>> healthCheckDetails() {
        Map<String, Object> health = new LinkedHashMap<>();
        health.put("status", "UP");
        health.put("timestamp", Instant.now().toString());

        // Check protocol bootstrap
        Map<String, Object> protocol = new LinkedHashMap<>();
        try {
            var params = protocolBootstrapService.getProtocolBootstrapParams();
            protocol.put("status", "UP");
            protocol.put("protocolParamsUtxo", params.protocolParamsUtxo() != null);
            protocol.put("issuanceUtxo", params.issuanceUtxo() != null);
            protocol.put("directoryUtxo", params.directoryUtxo() != null);
        } catch (Exception e) {
            protocol.put("status", "DOWN");
            protocol.put("error", e.getMessage());
        }
        health.put("protocolBootstrap", protocol);

        // Check substandards
        Map<String, Object> substandards = new LinkedHashMap<>();
        try {
            var allSubstandards = substandardService.getAllSubstandards();
            substandards.put("status", "UP");
            substandards.put("count", allSubstandards.size());
        } catch (Exception e) {
            substandards.put("status", "DOWN");
            substandards.put("error", e.getMessage());
        }
        health.put("substandards", substandards);

        return ResponseEntity.ok(health);
    }
}
