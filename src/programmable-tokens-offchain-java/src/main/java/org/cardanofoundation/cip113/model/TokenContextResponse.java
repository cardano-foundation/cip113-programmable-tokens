package org.cardanofoundation.cip113.model;

public record TokenContextResponse(
        String policyId,
        String substandardId,
        String blacklistNodePolicyId
) {}
