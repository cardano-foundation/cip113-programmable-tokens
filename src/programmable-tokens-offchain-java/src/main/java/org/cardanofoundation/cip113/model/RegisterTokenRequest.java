package org.cardanofoundation.cip113.model;

import jakarta.annotation.Nullable;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * Request DTO for registering a new programmable token policy in the CIP-0113 protocol.
 *
 * <p>Registration is the first step in the programmable token lifecycle. It creates a new
 * entry in the on-chain registry that associates a token policy ID with its transfer logic
 * contracts. This enables the protocol to enforce programmable behavior on all tokens
 * minted under that policy.</p>
 *
 * <h2>Registration Flow</h2>
 * <ol>
 *   <li>Client selects a substandard (e.g., permissioned, blacklistable) and its validators</li>
 *   <li>Client submits RegisterTokenRequest with the validator triple:
 *     <ul>
 *       <li><b>Issue contract</b>: Controls who can mint tokens</li>
 *       <li><b>Transfer contract</b>: Controls transfer conditions (main programmable logic)</li>
 *       <li><b>Third-party contract</b>: Optional additional validation (e.g., blacklist check)</li>
 *     </ul>
 *   </li>
 *   <li>Backend constructs a transaction that:
 *     <ul>
 *       <li>Mints a registry NFT with the policy ID as the token name</li>
 *       <li>Stores the validator credentials in the registry node datum</li>
 *       <li>Inserts the node into the sorted linked list</li>
 *       <li>Optionally mints initial tokens to the registrar</li>
 *     </ul>
 *   </li>
 *   <li>Returns unsigned transaction CBOR for client to sign</li>
 * </ol>
 *
 * <h2>Validator Triple</h2>
 * <p>The three validators form a "validator triple" that defines the token's programmable
 * behavior:</p>
 * <ul>
 *   <li><b>Issue contract</b>: Called during minting to verify authorization</li>
 *   <li><b>Transfer contract</b>: Called during every transfer to enforce business logic</li>
 *   <li><b>Third-party contract</b>: Optional hook for external validation (blacklist, KYC, etc.)</li>
 * </ul>
 *
 * <h2>Registry Structure</h2>
 * <p>The registry is a sorted linked list stored on-chain. Each node contains:</p>
 * <ul>
 *   <li>{@code key}: The policy ID (32 bytes hex)</li>
 *   <li>{@code next}: Pointer to the next node's key</li>
 *   <li>{@code issueLogic}: Credential of the issue validator</li>
 *   <li>{@code transferLogic}: Credential of the transfer validator</li>
 *   <li>{@code thirdPartyLogic}: Optional third-party credential</li>
 *   <li>{@code owner}: The registrar's credential for administrative actions</li>
 * </ul>
 *
 * @param registrarAddress the address of the account registering the token; this becomes
 *                         the token owner with administrative rights
 * @param substandardName the ID of the substandard providing the validators
 * @param substandardIssueContractName the title of the issue logic validator in the blueprint
 * @param substandardTransferContractName the title of the transfer logic validator in the blueprint
 * @param substandardThirdPartyContractName optional title of the third-party validator
 * @param assetName the token's asset name as a hex string (for initial minting)
 * @param quantity the initial quantity to mint (can be "0" for registration-only)
 * @param recipientAddress optional recipient for initial tokens; defaults to registrar's
 *                         programmable address
 *
 * @see MintTokenRequest for minting additional tokens after registration
 * @see org.cardanofoundation.cip113.controller.IssueTokenController#register
 */
public record RegisterTokenRequest(
        @NotBlank(message = "Registrar address is required")
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid bech32 address format")
        String registrarAddress,

        @NotBlank(message = "Substandard name is required")
        String substandardName,

        @NotBlank(message = "Substandard issue contract name is required")
        String substandardIssueContractName,

        @NotBlank(message = "Substandard transfer contract name is required")
        String substandardTransferContractName,

        @Nullable
        String substandardThirdPartyContractName,

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
