package org.cardanofoundation.cip113.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.EqualsAndHashCode;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

/**
 * Registration request for the "freeze-and-seize" substandard.
 * Includes additional fields for admin management and blacklist configuration.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
public class FreezeAndSeizeRegisterRequest extends RegisterTokenRequest {

    /**
     * Public key hash of the admin who will manage this token.
     * Used to parameterize the issuer admin contract.
     */
    private String adminPubKeyHash;

    /**
     * Policy ID of the blacklist node NFTs.
     * Links this token to its blacklist for freeze/seize operations.
     */
    private String blacklistNodePolicyId;
}
