package org.cardanofoundation.cip113.model;

public record RegisterTokenRequest<T>(String feePayerAddress,
                                   String substandardName,
                                   String substandardIssueContractName,
                                   String substandardTransferContractName,
                                   String substandardThirdPartyContractName,
                                   String assetName,
                                   String quantity,
                                   String recipientAddress,
                                   T additionalData) {

    public record FreezeAndSeizeData(String adminPubKeyHash, String blacklistNodePolicyId) {}

}
