package org.cardanofoundation.cip113.service.substandard.context;

import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import lombok.Builder;
import lombok.Getter;
import lombok.ToString;

/**
 * Context for freeze-and-seize substandard instances.
 *
 * Each freeze-and-seize deployment (e.g., each stablecoin) has its own:
 * - Programmable token policy ID
 * - Blacklist policy ID and bootstrap parameters
 * - Admin credentials for authorization
 *
 * This context must be provided when creating a FreezeAndSeizeHandler
 * to specify which stablecoin instance to operate on.
 */
@Getter
@Builder
@ToString
public class FreezeAndSeizeContext implements SubstandardContext {

    private static final String SUBSTANDARD_ID = "freeze-and-seize";

    /**
     * Issuer PKH (payment or staking), can be script
     */
    private final String issuerAdminPkh;

    /**
     * Blacklist Manager Payment PKH
     */
    private final String blacklistManagerPkh;

    /**
     * The utxo ref input used to initialize blacklist
     */
    private final TransactionInput blacklistInitTxInput;

    /**
     * The policy id of the blacklist node nft
     */
    private final String blacklistNodePolicyId;

    @Override
    public String getSubstandardId() {
        return SUBSTANDARD_ID;
    }

    public static FreezeAndSeizeContext emptyContext() {
        return FreezeAndSeizeContext.builder().build();
    }

}
