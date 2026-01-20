package org.cardanofoundation.cip113.service.substandard.capabilities;

import org.cardanofoundation.cip113.model.TransactionContext;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;

/**
 * Whitelist management capability for KYC/securities compliance.
 * Used for security tokens where only whitelisted (KYC-verified) addresses
 * are permitted to hold or transfer the asset.
 *
 * Unlike blacklist (which blocks specific addresses), whitelist requires
 * addresses to be explicitly approved before they can receive tokens.
 */
public interface WhitelistManageable {

    /**
     * Metadata for whitelist initialization operations.
     */
    record WhitelistInitResult(String bootstrapParameters) {}

    /**
     * Request to initialize a whitelist for a programmable token.
     */
    record WhitelistInitRequest(
            /** The admin address that will manage this whitelist */
            String adminAddress,
            /** Bootstrap UTxO transaction hash */
            String bootstrapTxHash,
            /** Bootstrap UTxO output index */
            int bootstrapOutputIndex
    ) {}

    /**
     * Request to add an address to the whitelist (KYC approval).
     */
    record AddToWhitelistRequest(
            /** The admin address performing the action */
            String adminAddress,
            /** The address/credential to add to whitelist (KYC verified) */
            String targetCredential,
            /** Policy ID of the programmable token */
            String policyId,
            /** Optional: KYC verification reference/ID */
            String kycReference
    ) {}

    /**
     * Request to remove an address from the whitelist (revoke KYC approval).
     */
    record RemoveFromWhitelistRequest(
            /** The admin address performing the action */
            String adminAddress,
            /** The address/credential to remove from whitelist */
            String targetCredential,
            /** Policy ID of the programmable token */
            String policyId,
            /** Optional: Reason for removal */
            String reason
    ) {}

    /**
     * Initialize a new whitelist for a programmable token (security token).
     * This creates the on-chain linked list structure for tracking approved addresses.
     *
     * @param request        The whitelist initialization request
     * @param protocolParams The protocol bootstrap parameters
     * @return Transaction context with unsigned CBOR tx and bootstrap parameters
     */
    TransactionContext<WhitelistInitResult> buildWhitelistInitTransaction(
            WhitelistInitRequest request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Add an address/credential to the whitelist (grant KYC approval).
     * Once whitelisted, the address can receive and transfer the security token.
     *
     * @param request        The add to whitelist request
     * @param protocolParams The protocol bootstrap parameters
     * @return Transaction context with unsigned CBOR tx
     */
    TransactionContext<Void> buildAddToWhitelistTransaction(
            AddToWhitelistRequest request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Remove an address/credential from the whitelist (revoke KYC approval).
     * Once removed, the address can no longer receive the security token.
     * Note: Existing holdings may need to be handled separately based on regulations.
     *
     * @param request        The remove from whitelist request
     * @param protocolParams The protocol bootstrap parameters
     * @return Transaction context with unsigned CBOR tx
     */
    TransactionContext<Void> buildRemoveFromWhitelistTransaction(
            RemoveFromWhitelistRequest request,
            ProtocolBootstrapParams protocolParams);
}
