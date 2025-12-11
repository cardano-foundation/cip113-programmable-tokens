package org.cardanofoundation.cip113.controller;

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
 * REST controller for CIP-0113 protocol configuration endpoints.
 *
 * <p>Provides access to the protocol blueprint (compiled validators) and bootstrap
 * parameters (deployment configuration). These endpoints are used by the frontend
 * to understand the current protocol deployment.
 *
 * <h2>Endpoints</h2>
 * <ul>
 *   <li>{@code GET /api/v1/protocol/blueprint} - Aiken-generated Plutus blueprint</li>
 *   <li>{@code GET /api/v1/protocol/bootstrap} - Bootstrap parameters with UTxO references</li>
 * </ul>
 *
 * <h2>Security Considerations</h2>
 * <p>These endpoints expose public protocol information and do not require authentication.
 * The blueprint and bootstrap data are derived from on-chain state and configuration files.
 *
 * @see ProtocolBootstrapService
 */
@RestController
@RequestMapping("${apiPrefix}/protocol")
@RequiredArgsConstructor
@Slf4j
public class ProtocolController {

    private final ProtocolBootstrapService protocolBootstrapService;

    @GetMapping("/blueprint")
    public ResponseEntity<Plutus> getPlutus() {
        return ResponseEntity.ok(protocolBootstrapService.getPlutus());
    }

    @GetMapping("/bootstrap")
    public ResponseEntity<ProtocolBootstrapParams> getLatest() {
        return ResponseEntity.ok(protocolBootstrapService.getProtocolBootstrapParams());
    }


}
