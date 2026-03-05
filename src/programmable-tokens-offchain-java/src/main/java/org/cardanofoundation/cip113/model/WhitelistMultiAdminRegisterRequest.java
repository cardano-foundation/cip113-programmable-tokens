package org.cardanofoundation.cip113.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.EqualsAndHashCode;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

import java.util.List;

/**
 * Registration request for the "whitelist-send-receive-multiadmin" substandard.
 * Includes fields for multi-admin hierarchy configuration.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
public class WhitelistMultiAdminRegisterRequest extends RegisterTokenRequest {

    /**
     * Public key hash of the issuer admin (super-admin).
     * Used to parameterize the issuer admin contract and manage managers.
     */
    private String adminPubKeyHash;

    /**
     * List of super-admin public key hashes for the manager signatures config.
     * These are the credentials authorized to add/remove managers.
     */
    private List<String> superAdminPkhs;

    /**
     * Policy ID of the whitelist node NFTs (if whitelist already initialized).
     */
    private String whitelistPolicyId;

    /**
     * Policy ID of the manager list node NFTs (if manager list already initialized).
     */
    private String managerListPolicyId;

    /**
     * Policy ID of the manager signatures NFTs (if manager sigs already initialized).
     */
    private String managerSigsPolicyId;
}
