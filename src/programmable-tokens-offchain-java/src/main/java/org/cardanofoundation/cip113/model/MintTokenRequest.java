package org.cardanofoundation.cip113.model;

/**
 * Request to mint programmable tokens.
 * The handler knows its contract names internally, so no script names are required.
 *
 * @param feePayerAddress  The address that pays for the transaction
 * @param substandardName  The substandard identifier for routing (e.g., "dummy", "freeze-and-seize")
 * @param assetName        The asset name (hex-encoded)
 * @param quantity         The quantity to mint (positive) or burn (negative)
 * @param recipientAddress The recipient address for minted tokens (defaults to feePayerAddress if null)
 */
public record MintTokenRequest(
        String feePayerAddress,
        String substandardName,
        String tokenPolicyId,
        String assetName,
        String quantity,
        String recipientAddress) {
}
