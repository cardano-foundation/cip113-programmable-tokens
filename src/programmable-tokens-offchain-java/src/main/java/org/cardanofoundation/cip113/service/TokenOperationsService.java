package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.util.Pair;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.TransactionContext.RegistrationResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.cardanofoundation.cip113.service.substandard.BafinSubstandardHandler;
import org.cardanofoundation.cip113.service.substandard.DummySubstandardHandler;
import org.cardanofoundation.cip113.service.substandard.FreezeAndSeizeHandler;
import org.cardanofoundation.cip113.service.substandard.SubstandardHandlerFactory;
import org.cardanofoundation.cip113.service.substandard.capabilities.BasicOperations;
import org.cardanofoundation.cip113.service.substandard.context.FreezeAndSeizeContext;
import org.springframework.stereotype.Service;

import java.util.List;

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

    private final BlacklistInitRepository blacklistInitRepository;

    private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeTokenRegistrationRepository;

    private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;

    /**
     * Pre-register a programmable token by registering required stake addresses.
     * This step registers withdraw-0 script stake addresses before the main registration.
     *
     * @param request        The registration request (polymorphic - dispatched by type)
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @return Transaction context with unsigned CBOR tx (null if all already registered) and list of stake addresses
     */
    @SuppressWarnings("unchecked")
    public TransactionContext<List<String>> preRegisterToken(RegisterTokenRequest request, String protocolTxHash) {
        log.info("Pre-registering token with substandard: {}, protocol: {}",
                request.getSubstandardId(), protocolTxHash);

        // Get protocol bootstrap params
        var protocolParams = resolveProtocolParams(protocolTxHash);

        // Pattern matching dispatch based on request type
        var txContext = switch (request) {
            case DummyRegisterRequest dummyRequest -> {
                var handler = handlerFactory.getHandler("dummy");
                var basicOps = (BasicOperations<DummyRegisterRequest>) handler.asBasicOperations()
                        .orElseThrow(() -> new UnsupportedOperationException("dummy does not support basic operations"));
                yield basicOps.buildPreRegistrationTransaction(dummyRequest, protocolParams);
            }
            case FreezeAndSeizeRegisterRequest fasRequest -> {
                var handler = handlerFactory.getHandler("freeze-and-seize", FreezeAndSeizeContext.emptyContext());
                var basicOps = (BasicOperations<FreezeAndSeizeRegisterRequest>) handler.asBasicOperations()
                        .orElseThrow(() -> new UnsupportedOperationException("freeze-and-seize does not support basic operations"));
                yield basicOps.buildPreRegistrationTransaction(fasRequest, protocolParams);
            }
            default -> throw new UnsupportedOperationException(
                    "Unknown request type: " + request.getClass().getSimpleName());
        };

        log.info("Pre-registration transaction built successfully for substandard: {}",
                request.getSubstandardId());

        return txContext;
    }

    /**
     * Register a new programmable token.
     * Uses pattern matching to dispatch to the correct handler based on request type.
     *
     * @param request        The registration request (polymorphic - dispatched by type)
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @return Transaction context with unsigned CBOR tx and registration metadata
     */
    @SuppressWarnings("unchecked")
    public TransactionContext<RegistrationResult> registerToken(RegisterTokenRequest request, String protocolTxHash) {
        log.info("Registering token with substandard: {}, protocol: {}",
                request.getSubstandardId(), protocolTxHash);

        // Get protocol bootstrap params
        var protocolParams = resolveProtocolParams(protocolTxHash);

        // Pattern matching dispatch based on request type
        var txContext = switch (request) {
            case DummyRegisterRequest dummyRequest -> {
                var handler = handlerFactory.getHandler("dummy");
                var basicOps = (BasicOperations<DummyRegisterRequest>) handler.asBasicOperations()
                        .orElseThrow(() -> new UnsupportedOperationException("dummy does not support basic operations"));
                yield basicOps.buildRegistrationTransaction(dummyRequest, protocolParams);
            }
            case FreezeAndSeizeRegisterRequest fasRequest -> {
                var handler = handlerFactory.getHandler("freeze-and-seize", FreezeAndSeizeContext.emptyContext());
                var basicOps = (BasicOperations<FreezeAndSeizeRegisterRequest>) handler.asBasicOperations()
                        .orElseThrow(() -> new UnsupportedOperationException("freeze-and-seize does not support basic operations"));
                yield basicOps.buildRegistrationTransaction(fasRequest, protocolParams);
            }
            default -> throw new UnsupportedOperationException(
                    "Unknown request type: " + request.getClass().getSimpleName());
        };

        log.info("Registration transaction built successfully for substandard: {}",
                request.getSubstandardId());
        
        // Log transaction context status for debugging
        log.info("Transaction context isSuccessful: {}, error: {}", 
                txContext.isSuccessful(), 
                txContext.error() != null ? txContext.error() : "none");

        return txContext;
    }

    /**
     * Mint programmable tokens
     *
     * @param request        The mint request
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> mintToken(MintTokenRequest request, String protocolTxHash) {
        log.info("Minting token: {}, protocol: {}", request, protocolTxHash);

        // Get protocol bootstrap params
        var protocolParams = resolveProtocolParams(protocolTxHash);

        // Resolve substandard from policyId via unified registry
        String substandardId = resolveSubstandardId(request.tokenPolicyId());

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
                        .blacklistNodePolicyId(blacklistInitEntity.getBlacklistNodePolicyId())
                        .build();
            }

            default -> null;
        };

        // Get substandard handler with BasicOperations capability
        var handler = context != null ? handlerFactory.getHandler(substandardId, context) : handlerFactory.getHandler(substandardId);
        var txContext = switch (handler) {
            case DummySubstandardHandler dummySubstandardHandler ->
                    dummySubstandardHandler.buildMintTransaction(request, protocolParams);
            case FreezeAndSeizeHandler freezeAndSeizeHandler ->
                    freezeAndSeizeHandler.buildMintTransaction(request, protocolParams);
            case BafinSubstandardHandler bafinSubstandardHandler ->
                    bafinSubstandardHandler.buildMintTransaction(request, protocolParams);
            default -> throw new UnsupportedOperationException();
        };

        log.info("Mint transaction built successfully for substandard: {}", substandardId);

        return txContext;
    }

    /**
     * Burn programmable tokens from a specific UTxO
     *
     * @param request        The burn request with UTxO reference
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> burnToken(BurnTokenRequest request, String protocolTxHash) {
        log.info("Burning token from UTxO: {}#{}, protocol: {}",
                request.utxoTxHash(), request.utxoOutputIndex(), protocolTxHash);

        // Get protocol bootstrap params
        var protocolParams = resolveProtocolParams(protocolTxHash);

        // Resolve substandard from policyId via unified registry
        String substandardId = resolveSubstandardId(request.tokenPolicyId());

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
                        .blacklistNodePolicyId(blacklistInitEntity.getBlacklistNodePolicyId())
                        .build();
            }

            default -> null;
        };

        // Get substandard handler with BasicOperations capability
        var handler = context != null ? handlerFactory.getHandler(substandardId, context) : handlerFactory.getHandler(substandardId);
        var txContext = switch (handler) {
            case DummySubstandardHandler dummySubstandardHandler ->
                    dummySubstandardHandler.buildBurnTransaction(request, protocolParams);
            case FreezeAndSeizeHandler freezeAndSeizeHandler ->
                    freezeAndSeizeHandler.buildBurnTransaction(request, protocolParams);
            case BafinSubstandardHandler bafinSubstandardHandler ->
                    bafinSubstandardHandler.buildBurnTransaction(request, protocolParams);
            default -> throw new UnsupportedOperationException();
        };

        log.info("Burn transaction built successfully for substandard: {}", substandardId);

        return txContext;
    }

    /**
     * Transfer programmable tokens
     *
     * @param request        The transfer request
     * @param protocolTxHash Optional protocol version tx hash (uses default if null)
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> transferToken(
            TransferTokenRequest request,
            String protocolTxHash) {
        log.info("Transferring token: {}, protocol: {}", request.unit(), protocolTxHash);

        var programmableToken = AssetType.fromUnit(request.unit());

        // Get protocol bootstrap params
        var protocolParams = resolveProtocolParams(protocolTxHash);

        // Resolve substandard from policyId via unified registry
        String substandardId = resolveSubstandardId(programmableToken.policyId());

        var context = switch (substandardId) {
            case "freeze-and-seize" -> {
                var dataOpt = freezeAndSeizeTokenRegistrationRepository.findByProgrammableTokenPolicyId(programmableToken.policyId())
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
                        .blacklistNodePolicyId(blacklistInitEntity.getBlacklistNodePolicyId())
                        .build();
            }

            default -> null;
        };

        // Get substandard handler with BasicOperations capability
        var handler = context != null ? handlerFactory.getHandler(substandardId, context) : handlerFactory.getHandler(substandardId);
        var txContext = switch (handler) {
            case DummySubstandardHandler dummySubstandardHandler ->
                    dummySubstandardHandler.buildTransferTransaction(request, protocolParams);
            case FreezeAndSeizeHandler freezeAndSeizeHandler ->
                    freezeAndSeizeHandler.buildTransferTransaction(request, protocolParams);
            case BafinSubstandardHandler bafinSubstandardHandler ->
                    bafinSubstandardHandler.buildTransferTransaction(request, protocolParams);
            default -> throw new UnsupportedOperationException();
        };


        log.info("Transfer transaction built successfully for substandard: {}", substandardId);

        return txContext;
    }

    /**
     * Resolve protocol bootstrap params from tx hash or use default
     */
    private ProtocolBootstrapParams resolveProtocolParams(String protocolTxHash) {
        if (protocolTxHash != null && !protocolTxHash.isEmpty()) {
            var bootstrapOpt = protocolBootstrapService.getProtocolBootstrapParamsByTxHash(protocolTxHash);
            if (bootstrapOpt.isEmpty()) {
                log.warn("Protocol version not found: {}. Available versions: {}", 
                        protocolTxHash, 
                        protocolBootstrapService.getAllBootstraps().keySet());
                // Fall back to default instead of throwing error
                log.info("Falling back to default protocol bootstrap");
                return protocolBootstrapService.getProtocolBootstrapParams();
            }
            return bootstrapOpt.get();
        }
        return protocolBootstrapService.getProtocolBootstrapParams();
    }

    /**
     * Resolve substandard ID from the unified programmable token registry.
     *
     * @param policyId The programmable token policy ID
     * @return The substandard ID
     * @throws IllegalArgumentException if the token is not registered
     */
    private String resolveSubstandardId(String policyId) {
        log.debug("Resolving substandard for policy ID: {}", policyId);

        return programmableTokenRegistryRepository.findByPolicyId(policyId)
                .map(ProgrammableTokenRegistryEntity::getSubstandardId)
                .orElseThrow(() -> new IllegalArgumentException(
                        "Token not registered in programmable token registry: " + policyId));
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
