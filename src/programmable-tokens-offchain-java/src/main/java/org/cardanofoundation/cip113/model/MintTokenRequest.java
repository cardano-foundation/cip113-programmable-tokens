package org.cardanofoundation.cip113.model;

/**
 * Request to mint programmable tokens.
 * The handler knows its contract names internally, so no script names are required.
 * The substandard is resolved from tokenPolicyId via the programmable token registry.
 *
 * @param feePayerAddress  The address that pays for the transaction
 * @param tokenPolicyId    The policy ID of the programmable token (used to resolve substandard)
 * @param assetName        The asset name (hex-encoded)
 * @param quantity         The quantity to mint (positive) or burn (negative)
 * @param recipientAddress The recipient address for minted tokens (defaults to feePayerAddress if null)
 */
public record MintTokenRequest(
        String feePayerAddress,
        String tokenPolicyId,
        String assetName,
        String quantity,
        String recipientAddress) {
}
