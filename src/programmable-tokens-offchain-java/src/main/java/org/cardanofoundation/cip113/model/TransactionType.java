package org.cardanofoundation.cip113.model;

/**
 * Type of transaction that affects token balances
 */
public enum TransactionType {
    /**
     * New tokens were created (minted)
     */
    MINT,

    /**
     * Tokens were destroyed (burned)
     */
    BURN,

    /**
     * Tokens were moved between addresses
     */
    TRANSFER,

    /**
     * New token policy was registered on-chain
     */
    REGISTER
}
