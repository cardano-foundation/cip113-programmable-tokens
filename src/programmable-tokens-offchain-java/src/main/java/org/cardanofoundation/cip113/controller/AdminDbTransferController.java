package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.BlacklistInitEntity;
import org.cardanofoundation.cip113.entity.FreezeAndSeizeTokenRegistrationEntity;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Hidden utility controller for transferring freeze-and-seize data between databases.
 * Useful for dev/debug scenarios where you need to copy data from one environment to another.
 *
 * WARNING: This is a utility endpoint with no authentication. Do not expose in production.
 */
@RestController
@RequestMapping("${apiPrefix}/admin/db-transfer")
@RequiredArgsConstructor
@Slf4j
public class AdminDbTransferController {

    private final BlacklistInitRepository blacklistInitRepository;
    private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeTokenRegistrationRepository;

    /**
     * Export all freeze-and-seize data from current database
     *
     * @return JSON with all blacklist inits and token registrations
     */
    @GetMapping("/export")
    public ResponseEntity<Map<String, Object>> exportData() {
        log.info("GET /admin/db-transfer/export - exporting all freeze-and-seize data");

        try {
            List<BlacklistInitEntity> blacklistInits = blacklistInitRepository.findAll();
            List<FreezeAndSeizeTokenRegistrationEntity> tokenRegistrations = freezeAndSeizeTokenRegistrationRepository.findAll();

            Map<String, Object> exportData = new HashMap<>();
            exportData.put("blacklistInits", blacklistInits);
            exportData.put("tokenRegistrations", tokenRegistrations);
            exportData.put("exportedAt", System.currentTimeMillis());
            exportData.put("counts", Map.of(
                    "blacklistInits", blacklistInits.size(),
                    "tokenRegistrations", tokenRegistrations.size()
            ));

            log.info("Exported {} blacklist inits and {} token registrations",
                    blacklistInits.size(), tokenRegistrations.size());

            return ResponseEntity.ok(exportData);
        } catch (Exception e) {
            log.error("Failed to export data", e);
            return ResponseEntity.internalServerError().build();
        }
    }

    /**
     * Import freeze-and-seize data into current database
     * Skips duplicates based on primary keys
     *
     * @param importData JSON with blacklistInits and tokenRegistrations arrays
     * @return Summary of import results (inserted, skipped, errors)
     */
    @PostMapping("/import")
    public ResponseEntity<Map<String, Object>> importData(@RequestBody Map<String, Object> importData) {
        log.info("POST /admin/db-transfer/import - importing freeze-and-seize data");

        try {
            int blacklistInitsInserted = 0;
            int blacklistInitsSkipped = 0;
            int tokenRegistrationsInserted = 0;
            int tokenRegistrationsSkipped = 0;

            // Import blacklist inits
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> blacklistInitsData = (List<Map<String, Object>>) importData.get("blacklistInits");
            if (blacklistInitsData != null) {
                for (Map<String, Object> data : blacklistInitsData) {
                    try {
                        String blacklistNodePolicyId = (String) data.get("blacklistNodePolicyId");
                        String txHash = (String) data.get("txHash");
                        Integer outputIndex = (Integer) data.get("outputIndex");

                        // Check if already exists (by blacklistNodePolicyId)
                        if (blacklistInitRepository.findByBlacklistNodePolicyId(blacklistNodePolicyId).isPresent()) {
                            log.debug("Skipping duplicate blacklist init: {}", blacklistNodePolicyId);
                            blacklistInitsSkipped++;
                            continue;
                        }

                        // Create new entity
                        BlacklistInitEntity entity = BlacklistInitEntity.builder()
                                .blacklistNodePolicyId(blacklistNodePolicyId)
                                .adminPkh((String) data.get("adminPkh"))
                                .txHash(txHash)
                                .outputIndex(outputIndex)
                                .build();

                        blacklistInitRepository.save(entity);
                        blacklistInitsInserted++;
                        log.debug("Inserted blacklist init: {}", blacklistNodePolicyId);
                    } catch (Exception e) {
                        log.error("Failed to import blacklist init: {}", data, e);
                    }
                }
            }

            // Import token registrations
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> tokenRegistrationsData = (List<Map<String, Object>>) importData.get("tokenRegistrations");
            if (tokenRegistrationsData != null) {
                for (Map<String, Object> data : tokenRegistrationsData) {
                    try {
                        String programmableTokenPolicyId = (String) data.get("programmableTokenPolicyId");

                        // Check if already exists (by programmableTokenPolicyId)
                        if (freezeAndSeizeTokenRegistrationRepository.findByProgrammableTokenPolicyId(programmableTokenPolicyId).isPresent()) {
                            log.debug("Skipping duplicate token registration: {}", programmableTokenPolicyId);
                            tokenRegistrationsSkipped++;
                            continue;
                        }

                        // Get or create blacklist init reference
                        String blacklistNodePolicyId = (String) data.get("blacklistNodePolicyId");
                        BlacklistInitEntity blacklistInit = null;
                        if (blacklistNodePolicyId != null) {
                            blacklistInit = blacklistInitRepository.findByBlacklistNodePolicyId(blacklistNodePolicyId)
                                    .orElse(null);
                        }

                        // Create new entity
                        FreezeAndSeizeTokenRegistrationEntity entity = FreezeAndSeizeTokenRegistrationEntity.builder()
                                .programmableTokenPolicyId(programmableTokenPolicyId)
                                .issuerAdminPkh((String) data.get("issuerAdminPkh"))
                                .blacklistInit(blacklistInit)
                                .build();

                        freezeAndSeizeTokenRegistrationRepository.save(entity);
                        tokenRegistrationsInserted++;
                        log.debug("Inserted token registration: {}", programmableTokenPolicyId);
                    } catch (Exception e) {
                        log.error("Failed to import token registration: {}", data, e);
                    }
                }
            }

            Map<String, Object> result = new HashMap<>();
            result.put("success", true);
            result.put("blacklistInits", Map.of(
                    "inserted", blacklistInitsInserted,
                    "skipped", blacklistInitsSkipped
            ));
            result.put("tokenRegistrations", Map.of(
                    "inserted", tokenRegistrationsInserted,
                    "skipped", tokenRegistrationsSkipped
            ));

            log.info("Import completed: blacklistInits(inserted={}, skipped={}), tokenRegistrations(inserted={}, skipped={})",
                    blacklistInitsInserted, blacklistInitsSkipped,
                    tokenRegistrationsInserted, tokenRegistrationsSkipped);

            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Failed to import data", e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "success", false,
                    "error", e.getMessage()
            ));
        }
    }
}
