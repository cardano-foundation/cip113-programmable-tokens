package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;

import java.util.Set;

/**
 * Interface for handling different programmable token substandards (dummy, bafin, etc.)
 * Each substandard implementation provides its own logic for registration, minting, and transfer.
 */
public interface SubstandardHandler {

    /**
     * Returns the unique identifier for this substandard (e.g., "dummy", "bafin")
     */
    String getSubstandardId();

    /**
     * Build registration transaction for this substandard
     *
     * @param request        The registration request
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return Transaction context with unsigned CBOR tx and metadata
     */
    RegisterTransactionContext buildRegistrationTransaction(
            RegisterTokenRequest request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Build mint transaction for this substandard
     *
     * @param request        The mint request
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return Transaction context with unsigned CBOR tx and metadata
     */
    TransactionContext buildMintTransaction(
            MintTokenRequest request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Build transfer transaction for this substandard
     *
     * @param request        The transfer request
     * @param protocolParams The protocol bootstrap parameters (from bootstrap tx)
     * @return Transaction context with unsigned CBOR tx and metadata
     */
    TransactionContext buildTransferTransaction(TransferTokenRequest request,
                                                ProtocolBootstrapParams protocolParams);

    /**
     * Returns the set of validator script names required by this substandard
     * For example: ["issue_validator", "transfer_validator"] for dummy
     * or all 22 validators for bafin
     */
    Set<String> getRequiredValidators();

    /**
     * Get a parameterized issue validator for this substandard
     *
     * @param contractName The name of the contract (e.g., "issue_validator")
     * @param params       Parameters to apply to the script
     * @return Parameterized PlutusScript
     */
    PlutusScript getParameterizedIssueValidator(String contractName, Object... params);

    /**
     * Get a parameterized transfer validator for this substandard
     *
     * @param contractName The name of the contract (e.g., "transfer_validator")
     * @param params       Parameters to apply to the script
     * @return Parameterized PlutusScript
     */
    PlutusScript getParameterizedTransferValidator(String contractName, Object... params);

    /**
     * Get a parameterized third-party validator for this substandard
     * (Used by bafin for its 20 additional validators)
     *
     * @param contractName The name of the contract
     * @param params       Parameters to apply to the script
     * @return Parameterized PlutusScript
     */
    PlutusScript getParameterizedThirdPartyValidator(String contractName, Object... params);
}
