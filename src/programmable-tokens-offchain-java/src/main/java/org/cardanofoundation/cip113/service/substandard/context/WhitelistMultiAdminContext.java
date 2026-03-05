package org.cardanofoundation.cip113.service.substandard.context;

import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import lombok.Builder;
import lombok.Getter;
import lombok.ToString;

/**
 * Context for whitelist-send-receive-multiadmin substandard instances.
 *
 * <p>Each whitelist deployment has its own:</p>
 * <ul>
 *   <li>Super-admin credentials (issuer admin)</li>
 *   <li>Manager signatures policy (ManagerConfig NFT)</li>
 *   <li>Manager list policy (manager credential linked list)</li>
 *   <li>Whitelist policy (user address linked list)</li>
 *   <li>Manager auth script hash (authorization for whitelist ops)</li>
 * </ul>
 *
 * <p>This context must be provided when creating a WhitelistSendReceiveMultiAdminHandler
 * to specify which token instance to operate on.</p>
 */
@Getter
@Builder
@ToString
public class WhitelistMultiAdminContext implements SubstandardContext {

    private static final String SUBSTANDARD_ID = "whitelist-send-receive-multiadmin";

    /** Super-admin credential (issuer admin PKH) */
    private final String issuerAdminPkh;

    /** Policy ID of the manager signatures NFTs (ManagerConfig) */
    private final String managerSigsPolicyId;

    /** Policy ID of the manager list node NFTs */
    private final String managerListPolicyId;

    /** Script hash of the manager_auth withdraw validator */
    private final String managerAuthHash;

    /** Policy ID of the whitelist node NFTs */
    private final String whitelistPolicyId;

    /** Seed UTxO consumed for manager_signatures init */
    private final TransactionInput managerSigsInitTxInput;

    /** Seed UTxO consumed for manager_list init */
    private final TransactionInput managerListInitTxInput;

    /** Seed UTxO consumed for whitelist init */
    private final TransactionInput whitelistInitTxInput;

    @Override
    public String getSubstandardId() {
        return SUBSTANDARD_ID;
    }

    public static WhitelistMultiAdminContext emptyContext() {
        return WhitelistMultiAdminContext.builder().build();
    }
}
