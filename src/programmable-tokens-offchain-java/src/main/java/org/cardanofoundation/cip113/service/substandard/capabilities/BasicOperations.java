package org.cardanofoundation.cip113.service.substandard.capabilities;

import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.TransactionContext.RegistrationResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;

import java.math.BigInteger;
import java.util.List;

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
     * It is usually required to register some stake addresses onchain to enable the withdraw-0 trick.
     * Returns a stake registration unsigned tx if required or a list of required but already registered
     * stake addresses
     * @param request same request as register
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return a list of required but already registered stake addresses
     */
    TransactionContext<List<String>> buildPreRegistrationTransaction(
            R request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Build burn transaction from a specific UTxO.
     * Burns (destroys) tokens from a designated UTxO for precise control.
     * Default implementation converts to MintTokenRequest and delegates to buildMintTransaction.
     *
     * @param request        The burn request with UTxO reference
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return Transaction context with unsigned CBOR tx
     */
    default TransactionContext<Void> buildBurnTransaction(
            BurnTokenRequest request,
            ProtocolBootstrapParams protocolParams) {
        // Default: convert to MintTokenRequest with negative quantity
        // Handlers can override to use UTxO information
        MintTokenRequest mintRequest = new MintTokenRequest(
                request.feePayerAddress(),
                request.tokenPolicyId(),
                request.assetName(),
                new java.math.BigInteger(request.quantity()).negate().toString(),
                request.feePayerAddress()
        );
        return buildMintTransaction(mintRequest, protocolParams);
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
