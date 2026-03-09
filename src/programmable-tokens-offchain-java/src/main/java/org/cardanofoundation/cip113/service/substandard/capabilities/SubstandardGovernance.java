package org.cardanofoundation.cip113.service.substandard.capabilities;

import org.cardanofoundation.cip113.model.TransactionContext;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;

/**
 * Governance capability for managing role-specific credential lists.
 * Used by substandards with multi-admin hierarchies where a super-admin
 * manages a list of managers (e.g., whitelist managers, compliance officers).
 *
 * <p>This is generic enough for any substandard where a higher-tier admin
 * manages lower-tier admin credential lists on-chain.</p>
 */
public interface SubstandardGovernance {

    record GovernanceInitResult(
            String managerSigsPolicyId,
            String managerListPolicyId,
            String managerAuthHash,
            String whitelistPolicyId,
            String unsignedCborTx,
            String addAdminUnsignedCborTx
    ) {}

    record GovernanceInitRequest(
            String adminAddress,
            String bootstrapTxHash,
            int bootstrapOutputIndex
    ) {}

    record AddAdminRequest(
            String adminAddress,
            String targetCredential,
            String policyId,
            String role
    ) {}

    record RemoveAdminRequest(
            String adminAddress,
            String targetCredential,
            String policyId,
            String role
    ) {}

    /**
     * Build a transaction to initialize the governance (manager) linked list.
     */
    TransactionContext<GovernanceInitResult> buildGovernanceInitTransaction(
            GovernanceInitRequest request,
            ProtocolBootstrapParams params);

    /**
     * Build a transaction to add an admin/manager credential to the governance list.
     */
    TransactionContext<Void> buildAddAdminTransaction(
            AddAdminRequest request,
            ProtocolBootstrapParams params);

    /**
     * Build a transaction to remove an admin/manager credential from the governance list.
     */
    TransactionContext<Void> buildRemoveAdminTransaction(
            RemoveAdminRequest request,
            ProtocolBootstrapParams params);
}
