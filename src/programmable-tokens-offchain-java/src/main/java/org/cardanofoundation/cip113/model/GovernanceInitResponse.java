package org.cardanofoundation.cip113.model;

public record GovernanceInitResponse(
        String managerSigsPolicyId,
        String managerListPolicyId,
        String managerAuthHash,
        String whitelistPolicyId,
        String unsignedCborTx,
        String addAdminUnsignedCborTx
) {}
