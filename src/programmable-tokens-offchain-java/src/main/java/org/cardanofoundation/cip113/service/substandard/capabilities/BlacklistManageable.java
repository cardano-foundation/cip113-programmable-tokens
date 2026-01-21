package org.cardanofoundation.cip113.service.substandard.capabilities;

import org.cardanofoundation.cip113.model.TransactionContext;
import org.cardanofoundation.cip113.model.TransactionContext.MintingResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;

/**
 * Blacklist management capability for freeze-and-seize functionality.
 * Adding an address to the blacklist effectively "freezes" it (prevents transfers).
 * Removing from blacklist "unfreezes" the address.
 */
public interface BlacklistManageable {

    /**
     * Request to initialize a blacklist for a programmable token.
     */
    record BlacklistInitRequest(
            /** The admin address that will manage this blacklist */
            String adminAddress,
            /** The address that pays for hte tx */
            String feePayerAddress
    ) {
    }

    /**
     * Request to add an address to the blacklist (freeze).
     */
    record AddToBlacklistRequest(
            /**
             * The policy id of the programmable token
             */
            String tokenPolicyId,
            /** The address/credential to add to blacklist */
            String targetAddress,
            /** The address that pays for hte tx */
            String feePayerAddress
    ) {
    }

    /**
     * Request to remove an address from the blacklist (unfreeze).
     */
    record RemoveFromBlacklistRequest(
            /**
             * The policy id of the programmable token
             */
            String tokenPolicyId,
            /** The address/credential to remove from blacklist */
            String targetAddress,
            /** The address that pays for hte tx */
            String feePayerAddress
    ) {
    }

    /**
     * Initialize a new blacklist for a programmable token.
     * This creates the on-chain linked list structure for tracking blacklisted addresses.
     *
     * @param request        The blacklist initialization request
     * @param protocolParams The protocol bootstrap parameters
     * @return Transaction context with unsigned CBOR tx and bootstrap parameters
     */
    TransactionContext<MintingResult> buildBlacklistInitTransaction(
            BlacklistInitRequest request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Add an address/credential to the blacklist (freeze).
     * Once blacklisted, the address cannot transfer programmable tokens.
     *
     * @param request        The add to blacklist request
     * @param protocolParams The protocol bootstrap parameters
     * @return Transaction context with unsigned CBOR tx
     */
    TransactionContext<Void> buildAddToBlacklistTransaction(
            AddToBlacklistRequest request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Remove an address/credential from the blacklist (unfreeze).
     * Once removed, the address can transfer programmable tokens again.
     *
     * @param request        The remove from blacklist request
     * @param protocolParams The protocol bootstrap parameters
     * @return Transaction context with unsigned CBOR tx
     */
    TransactionContext<Void> buildRemoveFromBlacklistTransaction(
            RemoveFromBlacklistRequest request,
            ProtocolBootstrapParams protocolParams);
}
