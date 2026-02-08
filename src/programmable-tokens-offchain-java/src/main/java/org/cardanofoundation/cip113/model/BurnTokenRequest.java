package org.cardanofoundation.cip113.model;

import java.math.BigInteger;

import static java.math.BigInteger.ZERO;
import static java.util.Objects.requireNonNull;

/**
 * Request model for burning programmable tokens from specific UTxOs.
 * Used by the /issue-token/burn endpoint for compliance-driven burn operations.
 */
public record BurnTokenRequest(
        String feePayerAddress,      // Admin's wallet address (pays fees)
        String tokenPolicyId,        // Policy ID of token to burn
        String assetName,            // Hex-encoded asset name
        String quantity,             // Amount to burn (positive string, backend converts to negative)
        String utxoTxHash,           // Specific UTxO to burn from
        int utxoOutputIndex          // Output index of UTxO
) {
    /**
     * Compact constructor with validation.
     * Validates that all required fields are present and quantity is positive.
     */
    public BurnTokenRequest {
        requireNonNull(feePayerAddress, "feePayerAddress required");
        requireNonNull(tokenPolicyId, "tokenPolicyId required");
        requireNonNull(assetName, "assetName required");
        requireNonNull(quantity, "quantity required");
        requireNonNull(utxoTxHash, "utxoTxHash required");

        // Validate quantity is positive (will be negated by backend for burn)
        try {
            BigInteger quantityValue = new BigInteger(quantity);
            if (quantityValue.compareTo(ZERO) <= 0) {
                throw new IllegalArgumentException("Burn quantity must be positive");
            }
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Burn quantity must be a valid number");
        }
    }
}
