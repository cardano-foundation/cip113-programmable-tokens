package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.BlacklistInitResponse;
import org.cardanofoundation.cip113.service.ComplianceOperationsService;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable.AddToBlacklistRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable.BlacklistInitRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable.RemoveFromBlacklistRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable.MultiSeizeRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable.SeizeRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable.AddToWhitelistRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable.RemoveFromWhitelistRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable.WhitelistInitRequest;
import org.cardanofoundation.cip113.service.substandard.context.FreezeAndSeizeContext;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * REST controller for compliance operations on programmable tokens.
 *
 * <p>This controller exposes endpoints for:</p>
 * <ul>
 *   <li><b>Blacklist</b> - Freeze/unfreeze addresses (init, add, remove)</li>
 *   <li><b>Whitelist</b> - KYC/securities compliance (init, add, remove)</li>
 *   <li><b>Seize</b> - Asset recovery from blacklisted addresses</li>
 * </ul>
 *
 * <p>All endpoints require a substandard that supports the relevant capability.
 * For example, blacklist operations require a substandard implementing
 * {@link org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable}.</p>
 */
@RestController
@RequestMapping("${apiPrefix}/compliance")
@RequiredArgsConstructor
@Slf4j
public class ComplianceController {

    private final ComplianceOperationsService complianceOperationsService;

    // ========== Blacklist Endpoints ==========

    /**
     * Initialize a blacklist for a programmable token.
     * Creates the on-chain linked list structure for tracking blacklisted addresses.
     *
     * @param substandardId  The substandard identifier (e.g., "freeze-and-seize")
     * @param request        The blacklist initialization request
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/blacklist/init")
    public ResponseEntity<?> initBlacklist(@RequestParam String substandardId,
                                           @RequestBody BlacklistInitRequest request,
                                           @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/blacklist/init - substandardId: {}, admin: {}",
                substandardId, request.adminAddress());

        try {

            var context = switch (substandardId) {
                case "freeze-and-seize" -> FreezeAndSeizeContext.emptyContext();
                default -> null;
            };

            var txContext = complianceOperationsService.initBlacklist(substandardId, request, protocolTxHash, context);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(new BlacklistInitResponse(txContext.metadata().policyId(), txContext.unsignedCborTx()));
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid request: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error initializing blacklist", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    /**
     * Add an address to the blacklist (freeze).
     * Once blacklisted, the address cannot transfer programmable tokens.
     *
     * @param substandardId  The substandard identifier
     * @param request        The add to blacklist request
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/blacklist/add")
    public ResponseEntity<?> addToBlacklist(
            @RequestParam String substandardId,
            @RequestBody AddToBlacklistRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/blacklist/add - substandardId: {}, target: {}",
                substandardId, request.targetAddress());

        try {

            var context = switch (substandardId) {
                case "freeze-and-seize" -> FreezeAndSeizeContext.builder()
                        .blacklistManagerPkh(request.adminAddress())
                        .
                        .build();
                default -> null;
            };

            var txContext = complianceOperationsService.addToBlacklist(
                    substandardId, request, protocolTxHash, null);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid request: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error adding to blacklist", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    /**
     * Remove an address from the blacklist (unfreeze).
     * Once removed, the address can transfer programmable tokens again.
     *
     * @param substandardId  The substandard identifier
     * @param request        The remove from blacklist request
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/blacklist/remove")
    public ResponseEntity<?> removeFromBlacklist(
            @RequestParam String substandardId,
            @RequestBody RemoveFromBlacklistRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/blacklist/remove - substandardId: {}, target: {}",
                substandardId, request.targetCredential());

        try {
            var txContext = complianceOperationsService.removeFromBlacklist(
                    substandardId, request, protocolTxHash, null);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid request: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error removing from blacklist", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    // ========== Whitelist Endpoints ==========

    /**
     * Initialize a whitelist for a programmable token (security token).
     * Creates the on-chain linked list structure for tracking KYC-approved addresses.
     *
     * @param substandardId  The substandard identifier
     * @param request        The whitelist initialization request
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/whitelist/init")
    public ResponseEntity<?> initWhitelist(
            @RequestParam String substandardId,
            @RequestBody WhitelistInitRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/whitelist/init - substandardId: {}, admin: {}",
                substandardId, request.adminAddress());

        try {
            var txContext = complianceOperationsService.initWhitelist(
                    substandardId, request, protocolTxHash, null);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid request: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error initializing whitelist", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    /**
     * Add an address to the whitelist (grant KYC approval).
     * Once whitelisted, the address can receive and transfer the security token.
     *
     * @param substandardId  The substandard identifier
     * @param request        The add to whitelist request
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/whitelist/add")
    public ResponseEntity<?> addToWhitelist(
            @RequestParam String substandardId,
            @RequestBody AddToWhitelistRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/whitelist/add - substandardId: {}, target: {}",
                substandardId, request.targetCredential());

        try {
            var txContext = complianceOperationsService.addToWhitelist(
                    substandardId, request, protocolTxHash, null);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid request: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error adding to whitelist", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    /**
     * Remove an address from the whitelist (revoke KYC approval).
     * Once removed, the address can no longer receive the security token.
     *
     * @param substandardId  The substandard identifier
     * @param request        The remove from whitelist request
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/whitelist/remove")
    public ResponseEntity<?> removeFromWhitelist(
            @RequestParam String substandardId,
            @RequestBody RemoveFromWhitelistRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/whitelist/remove - substandardId: {}, target: {}",
                substandardId, request.targetCredential());

        try {
            var txContext = complianceOperationsService.removeFromWhitelist(
                    substandardId, request, protocolTxHash, null);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid request: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error removing from whitelist", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    // ========== Seize Endpoints ==========

    /**
     * Seize assets from a blacklisted address.
     * The target address must be on the blacklist for this operation to succeed.
     *
     * @param substandardId  The substandard identifier
     * @param request        The seize request
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/seize")
    public ResponseEntity<?> seize(
            @RequestParam String substandardId,
            @RequestBody SeizeRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/seize - substandardId: {}, target: {}, destination: {}",
                substandardId, request.targetAddress(), request.destinationAddress());

        try {
            var txContext = complianceOperationsService.seize(
                    substandardId, request, protocolTxHash, null);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid request: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error seizing assets", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    /**
     * Seize assets from multiple UTxOs in a single transaction.
     * More efficient for seizing from addresses with multiple token UTxOs.
     *
     * @param substandardId  The substandard identifier
     * @param request        The multi-seize request
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/seize/multi")
    public ResponseEntity<?> multiSeize(
            @RequestParam String substandardId,
            @RequestBody MultiSeizeRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/seize/multi - substandardId: {}, utxo count: {}, destination: {}",
                substandardId, request.utxoReferences().size(), request.destinationAddress());

        try {
            var txContext = complianceOperationsService.multiSeize(
                    substandardId, request, protocolTxHash, null);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid request: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error multi-seizing assets", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }
}
