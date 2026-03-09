package org.cardanofoundation.cip113.controller;

import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.util.Pair;
import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.BlacklistInitResponse;
import org.cardanofoundation.cip113.model.GovernanceInitResponse;
import org.cardanofoundation.cip113.repository.*;
import org.cardanofoundation.cip113.service.BlacklistQueryService;
import org.cardanofoundation.cip113.service.ComplianceOperationsService;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable.AddToBlacklistRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable.BlacklistInitRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable.RemoveFromBlacklistRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable.MultiSeizeRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable.SeizeRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.SubstandardGovernance.AddAdminRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.SubstandardGovernance.GovernanceInitRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.SubstandardGovernance.RemoveAdminRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable.AddToWhitelistRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable.RemoveFromWhitelistRequest;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable.WhitelistInitRequest;
import org.cardanofoundation.cip113.service.substandard.context.FreezeAndSeizeContext;
import org.cardanofoundation.cip113.service.substandard.context.SubstandardContext;
import org.cardanofoundation.cip113.service.substandard.context.WhitelistMultiAdminContext;
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

    private final WhitelistTokenRegistrationRepository whitelistTokenRegistrationRepository;
    private final WhitelistInitRepository whitelistInitRepository;
    private final ManagerListInitRepository managerListInitRepository;
    private final ManagerSignaturesInitRepository managerSignaturesInitRepository;

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

        log.info("POST /compliance/blacklist/init - substandardId: {}, admin: {}",
                request.substandardId(), request.adminAddress());

        try {
            // Resolve substandard from policyId via unified registry
            var substandardId = request.substandardId();

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
     *
     * <p>Can be called either before or after token registration:</p>
     * <ul>
     *   <li>Before registration: provide {@code substandardId} and {@code managerSigsPolicyId} as query params</li>
     *   <li>After registration: provide {@code tokenPolicyId} in the request body</li>
     * </ul>
     *
     * @param request        The whitelist initialization request
     * @param protocolTxHash Optional protocol version tx hash
     * @param substandardId  Optional substandard ID (required if token not yet registered)
     * @param managerSigsPolicyId Optional manager sigs policy ID (to build context before registration)
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/whitelist/init")
    public ResponseEntity<?> initWhitelist(
            @RequestBody WhitelistInitRequest request,
            @RequestParam(required = false) String protocolTxHash,
            @RequestParam(required = false) String substandardId,
            @RequestParam(required = false) String managerSigsPolicyId) {

        log.info("POST /compliance/whitelist/init - tokenPolicyId: {}, substandardId: {}, admin: {}",
                request.tokenPolicyId(), substandardId, request.adminAddress());

        try {
            // Resolve substandard: from param, or from tokenPolicyId if token already registered
            if (substandardId == null || substandardId.isEmpty()) {
                if (request.tokenPolicyId() == null || request.tokenPolicyId().isEmpty()) {
                    return ResponseEntity.badRequest().body("Either substandardId param or tokenPolicyId in body is required");
                }
                substandardId = resolveSubstandardId(request.tokenPolicyId());
            }

            // Build context: from managerSigsPolicyId param, or from tokenPolicyId if registered
            SubstandardContext context = null;
            if (managerSigsPolicyId != null && !managerSigsPolicyId.isEmpty()) {
                context = buildWhitelistContextFromManagerSigs(managerSigsPolicyId);
            } else if (request.tokenPolicyId() != null && !request.tokenPolicyId().isEmpty()) {
                try {
                    context = buildWhitelistContext(substandardId, request.tokenPolicyId());
                } catch (Exception e) {
                    log.debug("Could not build context from tokenPolicyId, using empty context");
                }
            }
            if (context == null) {
                context = WhitelistMultiAdminContext.emptyContext();
            }

            var txContext = complianceOperationsService.initWhitelist(
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
            var substandardId = resolveSubstandardId(request.policyId());
            var context = buildWhitelistContext(substandardId, request.policyId());

            var txContext = complianceOperationsService.addToWhitelist(
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
            var substandardId = resolveSubstandardId(request.policyId());
            var context = buildWhitelistContext(substandardId, request.policyId());

            var txContext = complianceOperationsService.removeFromWhitelist(
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

    // ========== Governance Endpoints ==========

    @PostMapping("/governance/init")
    public ResponseEntity<?> initGovernance(
            @RequestBody GovernanceInitRequest request,
            @RequestParam(required = false) String protocolTxHash,
            @RequestParam String substandardId) {

        log.info("POST /compliance/governance/init - substandardId: {}, admin: {}",
                substandardId, request.adminAddress());

        try {
            var context = WhitelistMultiAdminContext.emptyContext();
            var txContext = complianceOperationsService.initGovernance(
                    substandardId, request, protocolTxHash, context);

            if (txContext.isSuccessful()) {
                var result = txContext.metadata();
                return ResponseEntity.ok(new GovernanceInitResponse(
                        result.managerSigsPolicyId(),
                        result.managerListPolicyId(),
                        result.managerAuthHash(),
                        result.whitelistPolicyId(),
                        txContext.unsignedCborTx()));
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }
        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error initializing governance", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    @PostMapping("/governance/add")
    public ResponseEntity<?> addAdmin(
            @RequestBody AddAdminRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/governance/add - policyId: {}, target: {}",
                request.policyId(), request.targetCredential());

        try {
            var substandardId = resolveSubstandardId(request.policyId());
            var context = buildWhitelistContext(substandardId, request.policyId());

            var txContext = complianceOperationsService.addAdmin(
                    substandardId, request, protocolTxHash, context);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }
        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error adding admin", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    @PostMapping("/governance/remove")
    public ResponseEntity<?> removeAdmin(
            @RequestBody RemoveAdminRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /compliance/governance/remove - policyId: {}, target: {}",
                request.policyId(), request.targetCredential());

        try {
            var substandardId = resolveSubstandardId(request.policyId());
            var context = buildWhitelistContext(substandardId, request.policyId());

            var txContext = complianceOperationsService.removeAdmin(
                    substandardId, request, protocolTxHash, context);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }
        } catch (UnsupportedOperationException e) {
            log.warn("Capability not supported: {}", e.getMessage());
            return ResponseEntity.badRequest().body(e.getMessage());
        } catch (Exception e) {
            log.error("Error removing admin", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    // ========== Helper Methods ==========

    private String resolveSubstandardId(String policyId) {
        return programmableTokenRegistryRepository.findByPolicyId(policyId)
                .map(ProgrammableTokenRegistryEntity::getSubstandardId)
                .orElseThrow(() -> new IllegalArgumentException(
                        "Token not registered in programmable token registry: " + policyId));
    }

    /**
     * Build WhitelistMultiAdminContext from managerSigsPolicyId (for pre-registration flows
     * like whitelist init where the token doesn't exist yet).
     */
    private WhitelistMultiAdminContext buildWhitelistContextFromManagerSigs(String managerSigsPolicyId) {
        var managerSigsInit = managerSignaturesInitRepository.findByManagerSigsPolicyId(managerSigsPolicyId)
                .orElseThrow(() -> new RuntimeException("manager signatures init not found for: " + managerSigsPolicyId));

        var managerListInits = managerListInitRepository.findByManagerSigsInit_ManagerSigsPolicyId(managerSigsPolicyId);

        var builder = WhitelistMultiAdminContext.builder()
                .issuerAdminPkh(managerSigsInit.getAdminPkh())
                .managerSigsPolicyId(managerSigsInit.getManagerSigsPolicyId())
                .managerSigsInitTxInput(TransactionInput.builder()
                        .transactionId(managerSigsInit.getTxHash())
                        .index(managerSigsInit.getOutputIndex())
                        .build());

        if (!managerListInits.isEmpty()) {
            var managerListInit = managerListInits.getFirst();
            builder.managerListPolicyId(managerListInit.getManagerListPolicyId())
                    .managerListInitTxInput(TransactionInput.builder()
                            .transactionId(managerListInit.getTxHash())
                            .index(managerListInit.getOutputIndex())
                            .build());

            // Derive managerAuthHash from manager_list_cs
            // The handler's wlScriptBuilder.buildManagerAuthScript(managerListCs) produces the hash,
            // but we don't have that service here. Instead, check if a whitelist init already exists.
        }

        return builder.build();
    }

    /**
     * Build WhitelistMultiAdminContext from database for a given token policy ID.
     */
    private WhitelistMultiAdminContext buildWhitelistContext(String substandardId, String policyId) {
        if (!"whitelist-send-receive-multiadmin".equals(substandardId)) {
            return null;
        }

        var tokenReg = whitelistTokenRegistrationRepository.findByProgrammableTokenPolicyId(policyId)
                .orElseThrow(() -> new RuntimeException("whitelist token registration not found for: " + policyId));

        var whitelistInit = tokenReg.getWhitelistInit();
        var managerListInit = tokenReg.getManagerListInit();
        var managerSigsInit = tokenReg.getManagerSigsInit();

        return WhitelistMultiAdminContext.builder()
                .issuerAdminPkh(tokenReg.getIssuerAdminPkh())
                .whitelistPolicyId(whitelistInit.getWhitelistPolicyId())
                .managerAuthHash(whitelistInit.getManagerAuthHash())
                .managerListPolicyId(managerListInit.getManagerListPolicyId())
                .managerSigsPolicyId(managerSigsInit.getManagerSigsPolicyId())
                .whitelistInitTxInput(TransactionInput.builder()
                        .transactionId(whitelistInit.getTxHash())
                        .index(whitelistInit.getOutputIndex())
                        .build())
                .managerListInitTxInput(TransactionInput.builder()
                        .transactionId(managerListInit.getTxHash())
                        .index(managerListInit.getOutputIndex())
                        .build())
                .managerSigsInitTxInput(TransactionInput.builder()
                        .transactionId(managerSigsInit.getTxHash())
                        .index(managerSigsInit.getOutputIndex())
                        .build())
                .build();
    }
}
