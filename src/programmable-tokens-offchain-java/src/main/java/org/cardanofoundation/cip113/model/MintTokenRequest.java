package org.cardanofoundation.cip113.model;

import jakarta.annotation.Nullable;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * Request DTO for minting programmable tokens under the CIP-0113 protocol.
 *
 * <p>This request is used by the {@code POST /api/v1/issue-token/mint} endpoint to create
 * new programmable tokens. The tokens are minted according to the specified substandard's
 * issuance logic contract.</p>
 *
 * <h2>Minting Flow</h2>
 * <ol>
 *   <li>Client submits MintTokenRequest with issuer address and token details</li>
 *   <li>Backend looks up the substandard's issuance validator from the blueprint</li>
 *   <li>Backend constructs an unsigned Cardano transaction with:
 *     <ul>
 *       <li>Minting action for the specified quantity of tokens</li>
 *       <li>Output to recipient address (or issuer if not specified)</li>
 *       <li>Required script witnesses and reference inputs</li>
 *     </ul>
 *   </li>
 *   <li>Returns unsigned transaction CBOR for client to sign with wallet</li>
 * </ol>
 *
 * <h2>Address Formats</h2>
 * <p>All addresses must be in Cardano bech32 format:</p>
 * <ul>
 *   <li>Mainnet: {@code addr1...}</li>
 *   <li>Testnet: {@code addr_test1...}</li>
 * </ul>
 *
 * <h2>Asset Names</h2>
 * <p>Cardano asset names are raw bytes (up to 32 bytes). This API expects asset names
 * as hex-encoded strings, which the frontend converts from user input using
 * {@code stringToHex()}.</p>
 *
 * @param issuerBaseAddress the issuer's base address in bech32 format; this address
 *                          will be used for collateral and change outputs
 * @param substandardName the ID of the substandard defining the token's behavior
 *                        (e.g., "dummy", "permissioned", "blacklistable")
 * @param substandardIssueContractName the name of the issuance logic validator within
 *                                     the substandard's plutus.json blueprint
 * @param assetName the token's asset name as a hex string (1-64 hex chars, representing
 *                  up to 32 bytes)
 * @param quantity the number of tokens to mint as a positive integer string
 * @param recipientAddress optional recipient address; if null, tokens are sent to
 *                         the issuer's programmable address
 *
 * @see RegisterTokenRequest for initial token registration
 * @see org.cardanofoundation.cip113.controller.IssueTokenController#mint
 */
public record MintTokenRequest(
        @NotBlank(message = "Issuer base address is required")
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid bech32 address format")
        String issuerBaseAddress,

        @NotBlank(message = "Substandard name is required")
        String substandardName,

        @NotBlank(message = "Substandard issue contract name is required")
        String substandardIssueContractName,

        @NotBlank(message = "Asset name is required")
        @Pattern(regexp = "^[0-9a-fA-F]{1,64}$", message = "Asset name must be 1-64 hex characters")
        String assetName,

        @NotBlank(message = "Quantity is required")
        @Pattern(regexp = "^[1-9][0-9]*$", message = "Quantity must be a positive integer")
        String quantity,

        @Nullable
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid recipient address format")
        String recipientAddress) {
}
