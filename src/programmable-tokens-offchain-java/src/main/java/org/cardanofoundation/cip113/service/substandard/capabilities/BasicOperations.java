package org.cardanofoundation.cip113.service.substandard.capabilities;

import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.TransactionContext.RegistrationResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;

/**
 * Basic operations capability that all substandard handlers must implement.
 * Includes: register, mint (and burn), transfer
 *
 * @param <R> The specific registration request type for this substandard
 */
public interface BasicOperations<R extends RegisterTokenRequest> {

    /**
     * Build registration transaction for this substandard.
     * Registers a new programmable token in the protocol registry.
     *
     * @param request        The registration request (subtype-specific)
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return Transaction context with unsigned CBOR tx and registration metadata (policyId)
     */
    TransactionContext<RegistrationResult> buildRegistrationTransaction(
            R request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Build mint transaction for this substandard.
     * Mints new tokens of an already registered programmable token.
     *
     * @param request        The mint request
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return Transaction context with unsigned CBOR tx
     */
    TransactionContext<Void> buildMintTransaction(
            MintTokenRequest request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Build burn transaction for this substandard.
     * Burns (destroys) tokens of a programmable token.
     * Default implementation delegates to mint with negative quantity.
     *
     * @param request        The burn request (similar to mint but destroys tokens)
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return Transaction context with unsigned CBOR tx
     */
    default TransactionContext<Void> buildBurnTransaction(
            MintTokenRequest request,
            ProtocolBootstrapParams protocolParams) {
        // Default: burn is mint with negative quantity - handlers can override
        return buildMintTransaction(request, protocolParams);
    }

    /**
     * Build transfer transaction for this substandard.
     * Transfers tokens from one address to another.
     *
     * @param request        The transfer request
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return Transaction context with unsigned CBOR tx
     */
    TransactionContext<Void> buildTransferTransaction(
            TransferTokenRequest request,
            ProtocolBootstrapParams protocolParams);
}
