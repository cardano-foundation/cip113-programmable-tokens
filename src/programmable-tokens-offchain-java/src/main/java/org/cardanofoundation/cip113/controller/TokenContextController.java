package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.BlacklistInitEntity;
import org.cardanofoundation.cip113.entity.FreezeAndSeizeTokenRegistrationEntity;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.TokenContextResponse;
import org.cardanofoundation.cip113.model.TokenRegistrationRequest;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("${apiPrefix}/token-context")
@RequiredArgsConstructor
@Slf4j
public class TokenContextController {

    private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;
    private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeTokenRegistrationRepository;
    private final BlacklistInitRepository blacklistInitRepository;

    /**
     * Get token context — returns substandardId + init params for a given policy ID.
     * Used by the SDK to determine which substandard handles a token.
     */
    @GetMapping("/{policyId}")
    public ResponseEntity<TokenContextResponse> getTokenContext(@PathVariable String policyId) {
        var registryEntry = programmableTokenRegistryRepository.findByPolicyId(policyId);

        if (registryEntry.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var entry = registryEntry.get();
        var substandardId = entry.getSubstandardId();
        var assetName = entry.getAssetName();
        String blacklistNodePolicyId = null;
        String issuerAdminPkh = null;
        String blacklistInitTxHash = null;
        Integer blacklistInitOutputIndex = null;

        if ("freeze-and-seize".equals(substandardId)) {
            var tokenRegistration = freezeAndSeizeTokenRegistrationRepository
                    .findByProgrammableTokenPolicyId(policyId);

            if (tokenRegistration.isPresent()) {
                var fesReg = tokenRegistration.get();
                issuerAdminPkh = fesReg.getIssuerAdminPkh();
                var blacklistInit = fesReg.getBlacklistInit();
                if (blacklistInit != null) {
                    blacklistNodePolicyId = blacklistInit.getBlacklistNodePolicyId();
                    blacklistInitTxHash = blacklistInit.getTxHash();
                    blacklistInitOutputIndex = blacklistInit.getOutputIndex();
                }
            }
        }

        return ResponseEntity.ok(new TokenContextResponse(
                policyId,
                substandardId,
                assetName,
                blacklistNodePolicyId,
                issuerAdminPkh,
                blacklistInitTxHash,
                blacklistInitOutputIndex
        ));
    }

    /**
     * Register a token in the backend DB after SDK-built on-chain registration.
     * This is a DB-only operation — no transaction building.
     * Called by the frontend as a callback after successful on-chain registration.
     */
    @PostMapping("/register")
    public ResponseEntity<?> registerToken(@RequestBody TokenRegistrationRequest request) {
        log.info("Token registry callback: policyId={}, substandardId={}", request.policyId(), request.substandardId());

        // Check if already registered
        if (programmableTokenRegistryRepository.existsByPolicyId(request.policyId())) {
            log.info("Token {} already registered, skipping", request.policyId());
            return ResponseEntity.ok().build();
        }

        // 1. Save to unified programmable token registry
        programmableTokenRegistryRepository.save(ProgrammableTokenRegistryEntity.builder()
                .policyId(request.policyId())
                .substandardId(request.substandardId())
                .assetName(request.assetName() != null ? request.assetName() : "")
                .build());

        // 2. For FES: insert blacklist init (if not already present), then token registration
        if ("freeze-and-seize".equals(request.substandardId()) && request.blacklistNodePolicyId() != null) {
            // 2a. Insert blacklist init row if it doesn't exist yet (SDK-built registrations)
            var blacklistInitOpt = blacklistInitRepository
                    .findByBlacklistNodePolicyId(request.blacklistNodePolicyId());

            if (blacklistInitOpt.isEmpty() && request.blacklistInitTxHash() != null) {
                log.info("Inserting blacklist init for policyId={}, bootstrapUtxo={}#{}",
                        request.blacklistNodePolicyId(), request.blacklistInitTxHash(), request.blacklistInitOutputIndex());
                var newBlacklistInit = BlacklistInitEntity.builder()
                        .blacklistNodePolicyId(request.blacklistNodePolicyId())
                        .adminPkh(request.blacklistAdminPkh() != null ? request.blacklistAdminPkh() : "")
                        .txHash(request.blacklistInitTxHash())
                        .outputIndex(request.blacklistInitOutputIndex() != null ? request.blacklistInitOutputIndex() : 0)
                        .build();
                blacklistInitRepository.save(newBlacklistInit);
                blacklistInitOpt = java.util.Optional.of(newBlacklistInit);
            }

            // 2b. Insert FES token registration (FK to blacklist init)
            if (blacklistInitOpt.isPresent()) {
                freezeAndSeizeTokenRegistrationRepository.save(FreezeAndSeizeTokenRegistrationEntity.builder()
                        .programmableTokenPolicyId(request.policyId())
                        .issuerAdminPkh(request.issuerAdminPkh() != null ? request.issuerAdminPkh() : "")
                        .blacklistInit(blacklistInitOpt.get())
                        .build());
            } else {
                log.warn("BlacklistInit not found and no init data provided for blacklistNodePolicyId: {}", request.blacklistNodePolicyId());
            }
        }

        log.info("Token {} registered successfully as {}", request.policyId(), request.substandardId());
        return ResponseEntity.ok().build();
    }
}
