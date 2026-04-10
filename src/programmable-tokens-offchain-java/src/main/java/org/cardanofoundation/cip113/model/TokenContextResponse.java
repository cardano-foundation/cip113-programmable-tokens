package org.cardanofoundation.cip113.model;

public record TokenContextResponse(
        String policyId,
        String substandardId,
        String assetName,
        String blacklistNodePolicyId,
        String issuerAdminPkh,
        String blacklistInitTxHash,
        Integer blacklistInitOutputIndex
) {}
