package org.cardanofoundation.cip113.model;

/**
 * Wrapper for transaction results containing the unsigned CBOR transaction
 * and any additional metadata needed for the operation.
 *
 * @param unsignedCborTx The unsigned transaction in CBOR hex format
 */
public record TransactionContext(String unsignedCborTx,
                                 boolean isSuccessful,
                                 String error) {

    /**
     * Create a simple transaction context with just the CBOR transaction
     */
    public static TransactionContext ok(String unsignedCborTx) {
        return new TransactionContext(unsignedCborTx, true, null);
    }

    /**
     * Create a transaction context with metadata
     */
    public static TransactionContext error(String error) {
        return new TransactionContext(null, false, error);
    }

}
