package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.model.ProtocolVersionInfo;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.cardanofoundation.cip113.service.ProtocolParamsService;
import org.cardanofoundation.cip113.service.ProtocolScriptBuilderService;
import org.cardanofoundation.conversions.CardanoConverters;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("${apiPrefix}/protocol-params")
@RequiredArgsConstructor
@Slf4j
public class ProtocolParamsController {

    private final ProtocolParamsService protocolParamsService;

    private final ProtocolBootstrapService protocolBootstrapService;

    private final ProtocolScriptBuilderService protocolScriptBuilderService;

    private final CardanoConverters cardanoConverters;

    /**
     * Get the latest protocol params version
     *
     * @return the latest protocol params or 404 if none exist
     */
    @GetMapping("/latest")
    public ResponseEntity<ProtocolParamsEntity> getLatest() {
        log.debug("GET /latest - fetching latest protocol params");
        return protocolParamsService.getLatest()
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get all protocol params versions (ordered by slot ascending)
     *
     * @return list of all protocol params
     */
    @GetMapping("/all")
    public ResponseEntity<List<ProtocolParamsEntity>> getAll() {
        log.debug("GET /all - fetching all protocol params");
        List<ProtocolParamsEntity> allParams = protocolParamsService.getAll();
        return ResponseEntity.ok(allParams);
    }

    /**
     * Get protocol params by transaction hash
     *
     * @param txHash the transaction hash
     * @return the protocol params or 404 if not found
     */
    @GetMapping("/by-tx/{txHash}")
    public ResponseEntity<ProtocolParamsEntity> getByTxHash(@PathVariable String txHash) {
        log.debug("GET /by-tx/{} - fetching protocol params by tx hash", txHash);
        return protocolParamsService.getByTxHash(txHash)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get protocol params by slot number
     *
     * @param slot the slot number
     * @return the protocol params or 404 if not found
     */
    @GetMapping("/by-slot/{slot}")
    public ResponseEntity<ProtocolParamsEntity> getBySlot(@PathVariable Long slot) {
        log.debug("GET /by-slot/{} - fetching protocol params by slot", slot);
        return protocolParamsService.getBySlot(slot)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get protocol params valid at a given slot (closest version <= slot)
     *
     * @param slot the slot number
     * @return the protocol params valid at that slot or 404 if none
     */
    @GetMapping("/valid-at-slot/{slot}")
    public ResponseEntity<ProtocolParamsEntity> getValidAtSlot(@PathVariable Long slot) {
        log.debug("GET /valid-at-slot/{} - fetching protocol params valid at slot", slot);
        return protocolParamsService.getValidAtSlot(slot)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get all protocol versions with default marked
     * Returns list of all protocol versions with essential fields for UI display
     * The default version is marked based on txHash from protocol-bootstraps-preview.json
     *
     * @return list of protocol version info ordered by slot descending (newest first)
     */
    @GetMapping("/versions")
    public ResponseEntity<List<ProtocolVersionInfo>> getVersions() {
        log.debug("GET /versions - fetching all protocol versions");

        try {
            // Get default txHash from protocol-bootstraps-preview.json
            ProtocolBootstrapParams bootstrapParams = protocolBootstrapService.getProtocolBootstrapParams();
            String defaultTxHash = bootstrapParams.txHash();
            log.debug("Default protocol version txHash: {}", defaultTxHash);

            // Get all protocol params (already ordered by slot ascending)
            List<ProtocolParamsEntity> allParams = protocolParamsService.getAll();

            List<ProtocolVersionInfo> versions;

            // If database is empty, return bootstrap version from JSON file
            if (allParams.isEmpty()) {
                log.info("No protocol params in database, returning bootstrap version from JSON");
                // Build directory mint script to get its policy ID (registry node policy ID)
                var directoryMintScript = protocolScriptBuilderService.getParameterizedDirectoryMintScript(bootstrapParams);
                var registryNodePolicyId = directoryMintScript.getPolicyId();
                
                var bootstrapVersion = ProtocolVersionInfo.builder()
                        .registryNodePolicyId(registryNodePolicyId)
                        .progLogicScriptHash(bootstrapParams.programmableLogicBaseParams().scriptHash())
                        .txHash(defaultTxHash)
                        .slot(0L) // Placeholder - will be updated when detected on-chain
                        .timestamp(System.currentTimeMillis() / 1000) // Current timestamp
                        .isDefault(true)
                        .build();
                versions = List.of(bootstrapVersion);
            } else {
                // Convert to DTOs with isDefault flag and timestamp conversion
                versions = allParams.stream()
                        .map(entity -> {
                            var timestamp = cardanoConverters.slot()
                                    .slotToTime(entity.getSlot())
                                    .toEpochSecond(ZoneOffset.UTC);
                            return ProtocolVersionInfo.builder()
                                    .registryNodePolicyId(entity.getRegistryNodePolicyId())
                                    .progLogicScriptHash(entity.getProgLogicScriptHash())
                                    .txHash(entity.getTxHash())
                                    .slot(entity.getSlot())
                                    .timestamp(timestamp)
                                    .isDefault(entity.getTxHash().equals(defaultTxHash))
                                    .build();
                        })
                        .collect(Collectors.toList());
            }

            log.debug("Returning {} protocol versions", versions.size());
            return ResponseEntity.ok(versions);

        } catch (Exception e) {
            log.error("Error fetching protocol versions", e);
            return ResponseEntity.internalServerError().build();
        }
    }
}
