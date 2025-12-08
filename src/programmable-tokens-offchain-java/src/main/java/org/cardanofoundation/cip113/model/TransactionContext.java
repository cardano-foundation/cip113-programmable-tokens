package org.cardanofoundation.cip113.model;

import java.util.Map;

/**
 * Wrapper for transaction results containing the unsigned CBOR transaction
 * and any additional metadata needed for the operation.
 *
 * @param unsignedCborTx The unsigned transaction in CBOR hex format
 * @param metadata Additional metadata about the transaction (optional)
 */
public record TransactionContext(
        String unsignedCborTx,
        Map<String, Object> metadata
) {
    /**
     * Create a simple transaction context with just the CBOR transaction
     */
    public static TransactionContext simple(String unsignedCborTx) {
        return new TransactionContext(unsignedCborTx, Map.of());
    }

    /**
     * Create a transaction context with metadata
     */
    public static TransactionContext withMetadata(String unsignedCborTx, Map<String, Object> metadata) {
        return new TransactionContext(unsignedCborTx, metadata);
    }
}
