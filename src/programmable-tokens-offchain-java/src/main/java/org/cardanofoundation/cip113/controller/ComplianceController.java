package org.cardanofoundation.cip113.controller;

import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.util.Pair;
import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.BlacklistInitResponse;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.cardanofoundation.cip113.service.BlacklistQueryService;
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
    private final BlacklistQueryService blacklistQueryService;

    private final BlacklistInitRepository blacklistInitRepository;

    private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeTokenRegistrationRepository;

    private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;

    // ========== Blacklist Endpoints ==========

    /**
     * Initialize a blacklist for a programmable token.
     * Creates the on-chain linked list structure for tracking blacklisted addresses.
     * Requires the token to be already registered in the programmable token registry.
     *
     * @param request        The blacklist initialization request (contains tokenPolicyId)
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/blacklist/init")
    public ResponseEntity<?> initBlacklist(@RequestBody BlacklistInitRequest request,
                                           @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/blacklist/init - request: {}", request);
        log.info("POST /compliance/blacklist/init - substandardId: {}, admin: {}, feePayer: {}",
                request != null ? request.substandardId() : "null",
                request != null ? request.adminAddress() : "null",
                request != null ? request.feePayerAddress() : "null");

        try {
            // Validate request
            if (request == null) {
                log.error("Request body is null");
                return ResponseEntity.badRequest().body("Request body is required");
            }
            
            var substandardId = request.substandardId();
            if (substandardId == null || substandardId.isEmpty()) {
                log.error("substandardId is null or empty");
                return ResponseEntity.badRequest().body("substandardId is required");
            }
            
            var adminAddress = request.adminAddress();
            if (adminAddress == null || adminAddress.isEmpty()) {
                log.error("adminAddress is null or empty");
                return ResponseEntity.badRequest().body("adminAddress is required");
            }
            
            // Resolve substandard from policyId via unified registry

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
     * @param request        The add to blacklist request (contains tokenPolicyId)
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/blacklist/add")
    @Transactional
    public ResponseEntity<?> addToBlacklist(
            @RequestBody AddToBlacklistRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/blacklist/add - tokenPolicyId: {}, target: {}",
                request.tokenPolicyId(), request.targetAddress());

        try {
            // Resolve substandard from policyId via unified registry
            var substandardId = resolveSubstandardId(request.tokenPolicyId());

            var context = switch (substandardId) {
                case "freeze-and-seize" -> {
                    var dataOpt = freezeAndSeizeTokenRegistrationRepository.findByProgrammableTokenPolicyId(request.tokenPolicyId())
                            .flatMap(token -> blacklistInitRepository.findByBlacklistNodePolicyId(token.getBlacklistInit().getBlacklistNodePolicyId())
                                    .map(blacklistInitEntity -> new Pair<>(token, blacklistInitEntity)));

                    if (dataOpt.isEmpty()) {
                        throw new RuntimeException("could not find programmable token or blacklist init data");
                    }

                    var data = dataOpt.get();
                    var tokenRegistration = data.first();
                    var blacklistInitEntity = data.second();
                    yield FreezeAndSeizeContext.builder()
                            .issuerAdminPkh(tokenRegistration.getIssuerAdminPkh())
                            .blacklistManagerPkh(blacklistInitEntity.getAdminPkh())
                            .blacklistInitTxInput(TransactionInput.builder()
                                    .transactionId(blacklistInitEntity.getTxHash())
                                    .index(blacklistInitEntity.getOutputIndex())
                                    .build())
                            .build();
                }

                default -> null;
            };

            var txContext = complianceOperationsService.addToBlacklist(
                    substandardId, request, protocolTxHash, context);

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
     * @param request        The remove from blacklist request (contains tokenPolicyId)
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/blacklist/remove")
    public ResponseEntity<?> removeFromBlacklist(
            @RequestBody RemoveFromBlacklistRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/blacklist/remove - tokenPolicyId: {}, target: {}",
                request.tokenPolicyId(), request.targetAddress());

        try {
            // Resolve substandard from policyId via unified registry
            var substandardId = resolveSubstandardId(request.tokenPolicyId());

            var context = switch (substandardId) {
                case "freeze-and-seize" -> {
                    var dataOpt = freezeAndSeizeTokenRegistrationRepository.findByProgrammableTokenPolicyId(request.tokenPolicyId())
                            .flatMap(token -> blacklistInitRepository.findByBlacklistNodePolicyId(token.getBlacklistInit().getBlacklistNodePolicyId())
                                    .map(blacklistInitEntity -> new Pair<>(token, blacklistInitEntity)));

                    if (dataOpt.isEmpty()) {
                        throw new RuntimeException("could not find programmable token or blacklist init data");
                    }

                    var data = dataOpt.get();
                    var tokenRegistration = data.first();
                    var blacklistInitEntity = data.second();
                    yield FreezeAndSeizeContext.builder()
                            .issuerAdminPkh(tokenRegistration.getIssuerAdminPkh())
                            .blacklistManagerPkh(blacklistInitEntity.getAdminPkh())
                            .blacklistInitTxInput(TransactionInput.builder()
                                    .transactionId(blacklistInitEntity.getTxHash())
                                    .index(blacklistInitEntity.getOutputIndex())
                                    .build())
                            .build();
                }

                default -> null;
            };

            var txContext = complianceOperationsService.removeFromBlacklist(
                    substandardId, request, protocolTxHash, context);

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

    /**
     * Check if an address is blacklisted for a specific token.
     * Returns the blacklist status without requiring transaction building.
     * This is a read-only query operation that checks the on-chain blacklist linked-list.
     *
     * @param tokenPolicyId  The programmable token policy ID
     * @param address        The bech32 address to check
     * @param protocolTxHash Optional protocol version tx hash (currently unused for queries)
     * @return JSON response with blacklist status
     */
    @GetMapping("/blacklist/check")
    public ResponseEntity<?> checkBlacklistStatus(
            @RequestParam String tokenPolicyId,
            @RequestParam String address,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("GET /compliance/blacklist/check - tokenPolicyId: {}, address: {}",
                tokenPolicyId, address);

        try {
            boolean isBlacklisted = blacklistQueryService.isAddressBlacklisted(
                    tokenPolicyId,
                    address
            );

            return ResponseEntity.ok(java.util.Map.of(
                    "tokenPolicyId", tokenPolicyId,
                    "address", address,
                    "blacklisted", isBlacklisted,
                    "frozen", isBlacklisted
            ));

        } catch (UnsupportedOperationException e) {
            log.warn("Blacklist check not implemented: {}", e.getMessage());
            // Return false for not-yet-implemented check (fail-safe)
            return ResponseEntity.ok(java.util.Map.of(
                    "tokenPolicyId", tokenPolicyId,
                    "address", address,
                    "blacklisted", false,
                    "frozen", false,
                    "error", "Blockchain query implementation pending"
            ));
        } catch (Exception e) {
            log.error("Error checking blacklist status", e);
            return ResponseEntity.internalServerError()
                    .body(java.util.Map.of("error", e.getMessage()));
        }
    }

    // ========== Whitelist Endpoints ==========

    /**
     * Initialize a whitelist for a programmable token (security token).
     * Creates the on-chain linked list structure for tracking KYC-approved addresses.
     * Requires the token to be already registered in the programmable token registry.
     *
     * @param request        The whitelist initialization request (contains tokenPolicyId)
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/whitelist/init")
    public ResponseEntity<?> initWhitelist(
            @RequestBody WhitelistInitRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/whitelist/init - tokenPolicyId: {}, admin: {}",
                request.tokenPolicyId(), request.adminAddress());

        try {
            // Resolve substandard from policyId via unified registry
            var substandardId = resolveSubstandardId(request.tokenPolicyId());

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
     * @param request        The add to whitelist request (contains policyId)
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/whitelist/add")
    public ResponseEntity<?> addToWhitelist(
            @RequestBody AddToWhitelistRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/whitelist/add - policyId: {}, target: {}",
                request.policyId(), request.targetCredential());

        try {
            // Resolve substandard from policyId via unified registry
            var substandardId = resolveSubstandardId(request.policyId());

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
     * @param request        The remove from whitelist request (contains policyId)
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/whitelist/remove")
    public ResponseEntity<?> removeFromWhitelist(
            @RequestBody RemoveFromWhitelistRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/whitelist/remove - policyId: {}, target: {}",
                request.policyId(), request.targetCredential());

        try {
            // Resolve substandard from policyId via unified registry
            var substandardId = resolveSubstandardId(request.policyId());

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
     * @param request        The seize request (contains unit with policyId)
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/seize")
    public ResponseEntity<?> seize(
            @RequestBody SeizeRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/seize - unit: {}, destination: {}",
                request.unit(), request.destinationAddress());

        try {

            var progToken = AssetType.fromUnit(request.unit());

            // Resolve substandard from policyId via unified registry
            var substandardId = resolveSubstandardId(progToken.policyId());

            var context = switch (substandardId) {
                case "freeze-and-seize" -> {
                    var dataOpt = freezeAndSeizeTokenRegistrationRepository.findByProgrammableTokenPolicyId(progToken.policyId())
                            .flatMap(token -> blacklistInitRepository.findByBlacklistNodePolicyId(token.getBlacklistInit().getBlacklistNodePolicyId())
                                    .map(blacklistInitEntity -> new Pair<>(token, blacklistInitEntity)));

                    if (dataOpt.isEmpty()) {
                        throw new RuntimeException("could not find programmable token or blacklist init data");
                    }

                    var data = dataOpt.get();
                    var tokenRegistration = data.first();
                    var blacklistInitEntity = data.second();
                    yield FreezeAndSeizeContext.builder()
                            .issuerAdminPkh(tokenRegistration.getIssuerAdminPkh())
                            .blacklistManagerPkh(blacklistInitEntity.getAdminPkh())
                            .blacklistInitTxInput(TransactionInput.builder()
                                    .transactionId(blacklistInitEntity.getTxHash())
                                    .index(blacklistInitEntity.getOutputIndex())
                                    .build())
                            .build();
                }

                default -> null;
            };


            var txContext = complianceOperationsService.seize(
                    substandardId, request, protocolTxHash, context);

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
     * @param request        The multi-seize request (contains policyId)
     * @param protocolTxHash Optional protocol version tx hash
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/seize/multi")
    public ResponseEntity<?> multiSeize(
            @RequestBody MultiSeizeRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/seize/multi - policyId: {}, utxo count: {}, destination: {}",
                request.policyId(), request.utxoReferences().size(), request.destinationAddress());

        try {
            // Resolve substandard from policyId via unified registry
            var substandardId = resolveSubstandardId(request.policyId());

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

    // ========== Helper Methods ==========

    /**
     * Resolve substandard ID from the unified programmable token registry.
     *
     * @param policyId The programmable token policy ID
     * @return The substandard ID
     * @throws IllegalArgumentException if the token is not registered
     */
    private String resolveSubstandardId(String policyId) {
        return programmableTokenRegistryRepository.findByPolicyId(policyId)
                .map(ProgrammableTokenRegistryEntity::getSubstandardId)
                .orElseThrow(() -> new IllegalArgumentException(
                        "Token not registered in programmable token registry: " + policyId));
    }
}
