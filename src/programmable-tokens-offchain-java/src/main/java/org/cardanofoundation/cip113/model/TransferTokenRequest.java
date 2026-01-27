package org.cardanofoundation.cip113.model;

/**
 * Request to transfer programmable tokens.
 * The substandard is resolved from the unit (policyId) via the programmable token registry.
 *
 * @param senderAddress    The sender's wallet address
 * @param unit             The token unit (policyId + assetNameHex) - used to resolve substandard
 * @param quantity         The quantity to transfer
 * @param recipientAddress The recipient's wallet address
 */
public record TransferTokenRequest(String senderAddress,
                                   String unit,
                                   String quantity,
                                   String recipientAddress) {

}
