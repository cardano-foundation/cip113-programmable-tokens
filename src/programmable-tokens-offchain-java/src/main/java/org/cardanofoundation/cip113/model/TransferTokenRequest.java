package org.cardanofoundation.cip113.model;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * Request DTO for transferring programmable tokens under the CIP-0113 protocol.
 *
 * <p>This request is used by the {@code POST /api/v1/transfer-token/transfer} endpoint
 * to create transfers of registered programmable tokens. Unlike regular Cardano token
 * transfers, programmable transfers are validated by the token's registered transfer
 * logic contract.</p>
 *
 * <h2>Transfer Flow</h2>
 * <ol>
 *   <li>Client submits TransferTokenRequest with sender, recipient, and token details</li>
 *   <li>Backend looks up the token's policy ID in the registry to find transfer logic</li>
 *   <li>Backend constructs a transaction that:
 *     <ul>
 *       <li>Spends sender's programmable UTxO containing the tokens</li>
 *       <li>Creates new programmable UTxO for recipient with transferred tokens</li>
 *       <li>Returns change to sender's programmable address</li>
 *       <li>Invokes the global programmable logic stake validator</li>
 *       <li>Provides the transfer logic script as a reference input</li>
 *     </ul>
 *   </li>
 *   <li>The transfer logic validator is executed on-chain to verify the transfer</li>
 *   <li>Returns unsigned transaction CBOR for client to sign</li>
 * </ol>
 *
 * <h2>Programmable Addresses</h2>
 * <p>Programmable tokens must be held at programmable addresses, which have:</p>
 * <ul>
 *   <li>Payment credential: The global programmable_logic_base script</li>
 *   <li>Stake credential: The user's key or script (for authorization)</li>
 * </ul>
 * <p>The backend automatically derives the correct programmable addresses from
 * the provided sender/recipient base addresses.</p>
 *
 * <h2>Token Unit Format</h2>
 * <p>The {@code unit} field is a Cardano asset unit: policyId + assetName concatenated
 * as a hex string. Example:</p>
 * <pre>
 * policyId (56 hex chars) + assetName (variable, up to 64 hex chars)
 * = "abc123...def456" + "4d79546f6b656e" (hex for "MyToken")
 * </pre>
 *
 * <h2>Transfer Logic Validation</h2>
 * <p>The registered transfer logic contract is invoked during the transfer to enforce
 * business rules such as:</p>
 * <ul>
 *   <li>Permissioned transfers (require issuer signature)</li>
 *   <li>Blacklist checking (reject transfers to/from blacklisted addresses)</li>
 *   <li>Transfer limits or time locks</li>
 *   <li>Custom business logic defined by the token issuer</li>
 * </ul>
 *
 * @param senderAddress the sender's base address in bech32 format; the actual spending
 *                      will be from their derived programmable address
 * @param unit the token unit (policyId + assetName) as 56-120 hex characters; this
 *             uniquely identifies the token to transfer
 * @param quantity the amount of tokens to transfer as a positive integer string
 * @param recipientAddress the recipient's base address in bech32 format; tokens will
 *                         be sent to their derived programmable address
 *
 * @see RegisterTokenRequest for registering tokens with transfer logic
 * @see org.cardanofoundation.cip113.controller.TransferTokenController#transfer
 */
public record TransferTokenRequest(
        @NotBlank(message = "Sender address is required")
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid sender address format")
        String senderAddress,

        @NotBlank(message = "Token unit is required")
        @Pattern(regexp = "^[0-9a-fA-F]{56,120}$", message = "Unit must be 56-120 hex characters (policyId + assetName)")
        String unit,

        @NotBlank(message = "Quantity is required")
        @Pattern(regexp = "^[1-9][0-9]*$", message = "Quantity must be a positive integer")
        String quantity,

        @NotBlank(message = "Recipient address is required")
        @Pattern(regexp = "^addr(_test)?1[a-z0-9]+$", message = "Invalid recipient address format")
        String recipientAddress) {
}
