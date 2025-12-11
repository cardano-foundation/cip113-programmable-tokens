package org.cardanofoundation.cip113.model;

import jakarta.annotation.Nullable;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * Request to issue programmable tokens (register + mint in one step).
 *
 * @param issuerBaseAddress the base address of the issuer (bech32 format)
 * @param substandardName the name of the substandard to use
 * @param substandardIssueContractName the name of the issuance contract within the substandard
 * @param substandardTransferContractName the name of the transfer logic contract within the substandard
 * @param substandardThirdPartyContractName optional third-party contract name (can be null)
 * @param recipientAddress optional recipient address; if null, uses issuerBaseAddress (bech32 format)
 */
public record IssueTokenRequest(
        @NotBlank(message = "Issuer base address is required")
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid issuer address format")
        String issuerBaseAddress,

        @NotBlank(message = "Substandard name is required")
        String substandardName,

        @NotBlank(message = "Substandard issue contract name is required")
        String substandardIssueContractName,

        @NotBlank(message = "Substandard transfer contract name is required")
        String substandardTransferContractName,

        @Nullable
        String substandardThirdPartyContractName,

        @Nullable
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid recipient address format")
        String recipientAddress) {
}
