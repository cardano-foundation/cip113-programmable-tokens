package org.cardanofoundation.cip113.model;

import jakarta.annotation.Nullable;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * Request to mint programmable tokens.
 *
 * @param issuerBaseAddress the base address of the issuer (bech32 format)
 * @param substandardName the name of the substandard to use
 * @param substandardIssueContractName the name of the issuance contract within the substandard
 * @param assetName the hex-encoded asset name (max 64 hex chars = 32 bytes)
 * @param quantity the quantity of tokens to mint (positive integer string)
 * @param recipientAddress optional recipient address; if null, uses issuerBaseAddress (bech32 format)
 */
public record MintTokenRequest(
        @NotBlank(message = "Issuer base address is required")
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid issuer address format")
        String issuerBaseAddress,

        @NotBlank(message = "Substandard name is required")
        String substandardName,

        @NotBlank(message = "Substandard issue contract name is required")
        String substandardIssueContractName,

        @NotBlank(message = "Asset name is required")
        @Pattern(regexp = "^[a-fA-F0-9]{1,64}$", message = "Asset name must be 1-64 hex characters")
        String assetName,

        @NotBlank(message = "Quantity is required")
        @Pattern(regexp = "^[1-9][0-9]*$", message = "Quantity must be a positive integer")
        String quantity,

        @Nullable
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid recipient address format")
        String recipientAddress) {
}
