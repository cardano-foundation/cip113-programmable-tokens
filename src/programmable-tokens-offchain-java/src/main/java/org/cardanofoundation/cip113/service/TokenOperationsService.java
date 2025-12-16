package org.cardanofoundation.cip113.service;

import com.easy1staking.cardano.model.AssetType;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.service.substandard.SubstandardHandlerFactory;
import org.springframework.stereotype.Service;

import java.util.Optional;

/**
 * Service orchestration layer for token operations.
 * This service coordinates between controllers, substandard handlers, and protocol services.
 * It handles substandard routing and provides a clean separation between API and business logic.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class TokenOperationsService {

    private final SubstandardHandlerFactory handlerFactory;
    private final ProtocolBootstrapService protocolBootstrapService;
    private final RegistryService registryService;

    /**
     * Register a new programmable token
     *
     * @param request        The registration request
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @return Transaction context with unsigned CBOR tx
     */
    public RegisterTransactionContext registerToken(RegisterTokenRequest request, String protocolTxHash) {
        log.info("Registering token with substandard: {}, protocol: {}",
                request.substandardName(), protocolTxHash);

        // Get protocol bootstrap params
        var protocolParams = resolveProtocolParams(protocolTxHash);

        // Get substandard handler
        var handler = handlerFactory.getHandler(request.substandardName());

        // Build registration transaction
        var txContext = handler.buildRegistrationTransaction(request, protocolParams);

        log.info("Registration transaction built successfully for substandard: {}",
                request.substandardName());

        return txContext;
    }

    /**
     * Mint programmable tokens
     *
     * @param request        The mint request
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext mintToken(MintTokenRequest request, String protocolTxHash) {
        log.info("Minting token: {}, protocol: {}", request, protocolTxHash);

        // Get protocol bootstrap params
        var protocolParams = resolveProtocolParams(protocolTxHash);

        // Resolve substandard from registry
//        String substandardId = resolveSubstandardFromRegistry("request.unit()");
        String substandardId = request.substandardName();

        // Get substandard handler
        var handler = handlerFactory.getHandler(substandardId);

        // Build mint transaction
        var txContext = handler.buildMintTransaction(request,
                protocolParams);

        log.info("Mint transaction built successfully for substandard: {}", substandardId);

        return txContext;
    }

    /**
     * Transfer programmable tokens
     *
     * @param request        The transfer request
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext transferToken(
            TransferTokenRequest request,
            String protocolTxHash) {
        log.info("Transferring token: {}, protocol: {}", request.unit(), protocolTxHash);

        // Get protocol bootstrap params
        var protocolParams = resolveProtocolParams(protocolTxHash);

        // Resolve substandard from registry
        String substandardId = resolveSubstandardFromRegistry(request.unit());

        // Get substandard handler
        var handler = handlerFactory.getHandler(substandardId);

        // Build transfer transaction
        var txContext = handler.buildTransferTransaction(request,
                protocolParams);

        log.info("Transfer transaction built successfully for substandard: {}", substandardId);

        return txContext;
    }

    /**
     * Resolve protocol bootstrap params from tx hash or use default
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
     * Resolve substandard from registry by looking up the token's policy ID.
     * For now, this is a partial implementation that:
     * 1. Uses AssetType to extract policy ID from unit
     * 2. Finds registry entry to validate token exists
     * 3. Hardcodes "dummy" as the substandard (TODO: extract from registry metadata)
     *
     * @param unit The token unit (policyId + assetNameHex)
     * @return The substandard ID
     */
    private String resolveSubstandardFromRegistry(String unit) {
        // Use AssetType utility to extract policy ID
        AssetType assetType = AssetType.fromUnit(unit);
        String policyId = assetType.policyId();

        log.debug("Resolving substandard for policy ID: {} (from unit: {})", policyId, unit);

        // Find registry entry
        Optional<RegistryNodeEntity> registryEntry = registryService.findByPolicyId(unit);

        if (registryEntry.isEmpty()) {
            throw new IllegalArgumentException(
                    "Token not registered in registry: " + policyId);
        }

        // TODO: Extract substandard from registry metadata when resolution logic is implemented
        // For now, we hardcode "dummy" until the metadata resolution is complete
        String substandardId = "dummy";

        log.debug("Resolved substandard '{}' for policy ID: {}", substandardId, policyId);

        return substandardId;
    }

    /**
     * Check if a substandard is supported
     *
     * @param substandardId The substandard identifier
     * @return true if supported, false otherwise
     */
    public boolean isSubstandardSupported(String substandardId) {
        return handlerFactory.hasHandler(substandardId);
    }

    /**
     * Get all supported substandard IDs
     *
     * @return Set of supported substandard IDs
     */
    public java.util.Set<String> getSupportedSubstandards() {
        return handlerFactory.getRegisteredSubstandards();
    }
}
