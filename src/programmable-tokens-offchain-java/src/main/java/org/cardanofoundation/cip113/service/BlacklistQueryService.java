package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.cardanofoundation.cip113.service.substandard.FreezeAndSeizeHandler;
import org.cardanofoundation.cip113.service.substandard.SubstandardHandlerFactory;
import org.cardanofoundation.cip113.service.substandard.context.FreezeAndSeizeContext;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

/**
 * Service for querying blacklist status from on-chain data.
 * Follows the same pattern as ComplianceOperationsService - resolves substandard,
 * builds context, and delegates to the appropriate handler.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class BlacklistQueryService {

    private final SubstandardHandlerFactory handlerFactory;
    private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;
    private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeTokenRegistrationRepository;
    private final BlacklistInitRepository blacklistInitRepository;

    /**
     * Check if an address is blacklisted for a specific token.
     * <p>
     * This method:
     * 1. Resolves the substandard from token policy ID
     * 2. Builds the appropriate context (e.g., FreezeAndSeizeContext)
     * 3. Gets the handler and delegates the check
     * <p>
     * Only substandards with blacklist capability (e.g., freeze-and-seize) will return true.
     * Other substandards (e.g., dummy) will return false.
     *
     * @param tokenPolicyId The programmable token policy ID
     * @param address       The bech32 address to check
     * @return true if blacklisted, false otherwise
     */
    @Cacheable(value = "blacklistStatus", key = "#tokenPolicyId + ':' + #address")
    public boolean isAddressBlacklisted(String tokenPolicyId, String address) {
        try {
            log.debug("Checking blacklist status for token={}, address={}", tokenPolicyId, address);

            // 1. Resolve substandard ID from policy ID
            var substandardIdOpt = programmableTokenRegistryRepository.findByPolicyId(tokenPolicyId)
                    .map(ProgrammableTokenRegistryEntity::getSubstandardId);

            if (substandardIdOpt.isEmpty()) {
                log.debug("Token {} not found in programmable token registry", tokenPolicyId);
                return false; // Not a programmable token
            }

            String substandardId = substandardIdOpt.get();
            log.debug("Resolved substandard: {}", substandardId);

            // 2. Build context based on substandard
            // Currently only freeze-and-seize supports blacklist
            if ("freeze-and-seize".equals(substandardId)) {
                return checkFreezeAndSeizeBlacklist(tokenPolicyId, address);
            } else {
                log.debug("Substandard {} does not support blacklist", substandardId);
                return false; // Other substandards don't have blacklist
            }

        } catch (Exception e) {
            log.error("Error checking blacklist status for token={}, address={}",
                    tokenPolicyId, address, e);
            // Fail-safe: if check fails, assume not blacklisted to avoid blocking legitimate users
            return false;
        }
    }

    /**
     * Check blacklist status for freeze-and-seize tokens.
     * Builds FreezeAndSeizeContext and delegates to the handler.
     */
    private boolean checkFreezeAndSeizeBlacklist(String tokenPolicyId, String address) {
        // Get token registration and blacklist init data
        var tokenRegistrationOpt = freezeAndSeizeTokenRegistrationRepository
                .findByProgrammableTokenPolicyId(tokenPolicyId);

        if (tokenRegistrationOpt.isEmpty()) {
            log.debug("Token {} not found in freeze-and-seize registry", tokenPolicyId);
            return false;
        }

        var tokenRegistration = tokenRegistrationOpt.get();
        var blacklistInit = tokenRegistration.getBlacklistInit();

        if (blacklistInit == null) {
            log.debug("Token {} has no blacklist initialized", tokenPolicyId);
            return false; // No blacklist for this token
        }

        // Build FreezeAndSeizeContext
        var context = FreezeAndSeizeContext.builder()
                .issuerAdminPkh(tokenRegistration.getIssuerAdminPkh())
                .blacklistManagerPkh(blacklistInit.getAdminPkh())
                .blacklistInitTxInput(TransactionInput.builder()
                        .transactionId(blacklistInit.getTxHash())
                        .index(blacklistInit.getOutputIndex())
                        .build())
                .blacklistNodePolicyId(blacklistInit.getBlacklistNodePolicyId())
                .build();

        log.debug("Built FreezeAndSeizeContext with blacklistNodePolicyId: {}",
                context.getBlacklistNodePolicyId());

        // Get handler and delegate check
        var handler = handlerFactory.getHandler("freeze-and-seize", context);

        if (handler instanceof FreezeAndSeizeHandler freezeAndSeizeHandler) {
            return freezeAndSeizeHandler.isAddressBlacklisted(address);
        } else {
            log.warn("Handler is not FreezeAndSeizeHandler: {}", handler.getClass());
            return false;
        }
    }
}
