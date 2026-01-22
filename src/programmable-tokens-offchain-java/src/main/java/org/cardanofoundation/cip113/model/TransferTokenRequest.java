package org.cardanofoundation.cip113.model;

public record TransferTokenRequest(String senderAddress,
                                   String substandardId,
                                   String unit,
                                   String quantity,
                                   String recipientAddress) {

}
