package org.cardanofoundation.cip113.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.TransactionContext;
import org.cardanofoundation.cip113.model.TransactionContext.MintingResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.service.substandard.SubstandardHandlerFactory;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable.*;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable.*;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable.*;
import org.cardanofoundation.cip113.service.substandard.context.SubstandardContext;
import org.springframework.stereotype.Service;

/**
 * Service orchestration layer for compliance operations.
 * This service coordinates blacklist, whitelist, and seize operations
 * between controllers and substandard handlers.
 *
 * <p>Supported capabilities:</p>
 * <ul>
 *   <li>{@link BlacklistManageable} - Freeze/unfreeze addresses</li>
 *   <li>{@link WhitelistManageable} - KYC/securities compliance</li>
 *   <li>{@link Seizeable} - Asset seizure from blacklisted addresses</li>
 * </ul>
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ComplianceOperationsService {

    private final SubstandardHandlerFactory handlerFactory;
    private final ProtocolBootstrapService protocolBootstrapService;

    // ========== Blacklist Operations ==========

    /**
     * Initialize a blacklist for a programmable token.
     *
     * @param substandardId  The substandard identifier (e.g., "freeze-and-seize")
     * @param request        The blacklist initialization request
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @param context        Optional context for context-aware handlers
     * @return Transaction context with unsigned CBOR tx and bootstrap parameters
     */
    public TransactionContext<MintingResult> initBlacklist(
            String substandardId,
            BlacklistInitRequest request,
            String protocolTxHash,
            SubstandardContext context) {

        log.info("Initializing blacklist for substandard: {}, admin: {}",
                substandardId, request.adminAddress());

        var protocolParams = resolveProtocolParams(protocolTxHash);
        var blacklistMgr = getBlacklistManageable(substandardId, context);

        var txContext = blacklistMgr.buildBlacklistInitTransaction(request, protocolParams);

        log.info("Blacklist init transaction built successfully for substandard: {}", substandardId);
        return txContext;
    }

    /**
     * Add an address to the blacklist (freeze).
     *
     * @param substandardId  The substandard identifier
     * @param request        The add to blacklist request
     * @param protocolTxHash Optional protocol version tx hash
     * @param context        Optional context for context-aware handlers
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> addToBlacklist(
            String substandardId,
            AddToBlacklistRequest request,
            String protocolTxHash,
            SubstandardContext context) {

        log.info("Adding to blacklist for substandard: {}, target: {}",
                substandardId, request.targetAddress());

        var protocolParams = resolveProtocolParams(protocolTxHash);
        var blacklistMgr = getBlacklistManageable(substandardId, context);

        var txContext = blacklistMgr.buildAddToBlacklistTransaction(request, protocolParams);

        log.info("Add to blacklist transaction built successfully for substandard: {}", substandardId);
        return txContext;
    }

    /**
     * Remove an address from the blacklist (unfreeze).
     *
     * @param substandardId  The substandard identifier
     * @param request        The remove from blacklist request
     * @param protocolTxHash Optional protocol version tx hash
     * @param context        Optional context for context-aware handlers
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> removeFromBlacklist(
            String substandardId,
            RemoveFromBlacklistRequest request,
            String protocolTxHash,
            SubstandardContext context) {

        log.info("Removing from blacklist for substandard: {}, target: {}",
                substandardId, request.targetAddress());

        var protocolParams = resolveProtocolParams(protocolTxHash);
        var blacklistMgr = getBlacklistManageable(substandardId, context);

        var txContext = blacklistMgr.buildRemoveFromBlacklistTransaction(request, protocolParams);

        log.info("Remove from blacklist transaction built successfully for substandard: {}", substandardId);
        return txContext;
    }

    // ========== Whitelist Operations ==========

    /**
     * Initialize a whitelist for a programmable token.
     *
     * @param substandardId  The substandard identifier
     * @param request        The whitelist initialization request
     * @param protocolTxHash Optional protocol version tx hash
     * @param context        Optional context for context-aware handlers
     * @return Transaction context with unsigned CBOR tx and bootstrap parameters
     */
    public TransactionContext<WhitelistInitResult> initWhitelist(
            String substandardId,
            WhitelistInitRequest request,
            String protocolTxHash,
            SubstandardContext context) {

        log.info("Initializing whitelist for substandard: {}, admin: {}",
                substandardId, request.adminAddress());

        var protocolParams = resolveProtocolParams(protocolTxHash);
        var whitelistMgr = getWhitelistManageable(substandardId, context);

        var txContext = whitelistMgr.buildWhitelistInitTransaction(request, protocolParams);

        log.info("Whitelist init transaction built successfully for substandard: {}", substandardId);
        return txContext;
    }

    /**
     * Add an address to the whitelist (KYC approval).
     *
     * @param substandardId  The substandard identifier
     * @param request        The add to whitelist request
     * @param protocolTxHash Optional protocol version tx hash
     * @param context        Optional context for context-aware handlers
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> addToWhitelist(
            String substandardId,
            AddToWhitelistRequest request,
            String protocolTxHash,
            SubstandardContext context) {

        log.info("Adding to whitelist for substandard: {}, target: {}",
                substandardId, request.targetCredential());

        var protocolParams = resolveProtocolParams(protocolTxHash);
        var whitelistMgr = getWhitelistManageable(substandardId, context);

        var txContext = whitelistMgr.buildAddToWhitelistTransaction(request, protocolParams);

        log.info("Add to whitelist transaction built successfully for substandard: {}", substandardId);
        return txContext;
    }

    /**
     * Remove an address from the whitelist (revoke KYC approval).
     *
     * @param substandardId  The substandard identifier
     * @param request        The remove from whitelist request
     * @param protocolTxHash Optional protocol version tx hash
     * @param context        Optional context for context-aware handlers
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> removeFromWhitelist(
            String substandardId,
            RemoveFromWhitelistRequest request,
            String protocolTxHash,
            SubstandardContext context) {

        log.info("Removing from whitelist for substandard: {}, target: {}",
                substandardId, request.targetCredential());

        var protocolParams = resolveProtocolParams(protocolTxHash);
        var whitelistMgr = getWhitelistManageable(substandardId, context);

        var txContext = whitelistMgr.buildRemoveFromWhitelistTransaction(request, protocolParams);

        log.info("Remove from whitelist transaction built successfully for substandard: {}", substandardId);
        return txContext;
    }

    // ========== Seize Operations ==========

    /**
     * Seize assets from a blacklisted address.
     *
     * @param substandardId  The substandard identifier
     * @param request        The seize request
     * @param protocolTxHash Optional protocol version tx hash
     * @param context        Optional context for context-aware handlers
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> seize(
            String substandardId,
            SeizeRequest request,
            String protocolTxHash,
            SubstandardContext context) {

        log.info("Seizing assets for substandard: {}, from: {}, destination: {}",
                substandardId, request.targetAddress(), request.destinationAddress());

        var protocolParams = resolveProtocolParams(protocolTxHash);
        var seizeable = getSeizeable(substandardId, context);

        var txContext = seizeable.buildSeizeTransaction(request, protocolParams);

        log.info("Seize transaction built successfully for substandard: {}", substandardId);
        return txContext;
    }

    /**
     * Seize assets from multiple UTxOs in a single transaction.
     *
     * @param substandardId  The substandard identifier
     * @param request        The multi-seize request
     * @param protocolTxHash Optional protocol version tx hash
     * @param context        Optional context for context-aware handlers
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> multiSeize(
            String substandardId,
            MultiSeizeRequest request,
            String protocolTxHash,
            SubstandardContext context) {

        log.info("Multi-seizing assets for substandard: {}, utxo count: {}, destination: {}",
                substandardId, request.utxoReferences().size(), request.destinationAddress());

        var protocolParams = resolveProtocolParams(protocolTxHash);
        var seizeable = getSeizeable(substandardId, context);

        var txContext = seizeable.buildMultiSeizeTransaction(request, protocolParams);

        log.info("Multi-seize transaction built successfully for substandard: {}", substandardId);
        return txContext;
    }

    // ========== Helper Methods ==========

    /**
     * Resolve protocol bootstrap params from tx hash or use default.
     */
    private ProtocolBootstrapParams resolveProtocolParams(String protocolTxHash) {
        if (protocolTxHash != null && !protocolTxHash.isEmpty()) {
            return protocolBootstrapService.getProtocolBootstrapParamsByTxHash(protocolTxHash)
                    .orElseThrow(() -> new IllegalArgumentException(
                            "Protocol version not found: " + protocolTxHash));
        }
        return protocolBootstrapService.getProtocolBootstrapParams();
    }

    /**
     * Get BlacklistManageable capability from handler.
     */
    private BlacklistManageable getBlacklistManageable(String substandardId, SubstandardContext context) {
        var handler = context != null
                ? handlerFactory.getHandler(substandardId, context)
                : handlerFactory.getHandler(substandardId);

        if (handler == null) {
            throw new IllegalArgumentException("Unknown substandard: " + substandardId);
        }

        return handler.asBlacklistManageable()
                .orElseThrow(() -> new UnsupportedOperationException(
                        "Substandard '" + substandardId + "' does not support blacklist management"));
    }

    /**
     * Get WhitelistManageable capability from handler.
     */
    private WhitelistManageable getWhitelistManageable(String substandardId, SubstandardContext context) {
        var handler = context != null
                ? handlerFactory.getHandler(substandardId, context)
                : handlerFactory.getHandler(substandardId);

        if (handler == null) {
            throw new IllegalArgumentException("Unknown substandard: " + substandardId);
        }

        return handler.asWhitelistManageable()
                .orElseThrow(() -> new UnsupportedOperationException(
                        "Substandard '" + substandardId + "' does not support whitelist management"));
    }

    /**
     * Get Seizeable capability from handler.
     */
    private Seizeable getSeizeable(String substandardId, SubstandardContext context) {
        var handler = context != null
                ? handlerFactory.getHandler(substandardId, context)
                : handlerFactory.getHandler(substandardId);

        if (handler == null) {
            throw new IllegalArgumentException("Unknown substandard: " + substandardId);
        }

        return handler.asSeizeable()
                .orElseThrow(() -> new UnsupportedOperationException(
                        "Substandard '" + substandardId + "' does not support seize operations"));
    }
}
