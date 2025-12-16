package org.cardanofoundation.cip113.model;

/**
 * Wrapper for transaction results containing the unsigned CBOR transaction
 * and any additional metadata needed for the operation.
 *
 * @param unsignedCborTx The unsigned transaction in CBOR hex format
 */
public record RegisterTransactionContext(String unsignedCborTx,
                                         String policyId,
                                         boolean isSuccessful,
                                         String error) {

    /**
     * Create a simple transaction context with just the CBOR transaction
     */
    public static RegisterTransactionContext ok(String unsignedCborTx, String policyId) {
        return new RegisterTransactionContext(unsignedCborTx, policyId, true, null);
    }

    /**
     * Create a transaction context with metadata
     */
    public static RegisterTransactionContext error(String error) {
        return new RegisterTransactionContext(null, null, false, error);
    }

}
