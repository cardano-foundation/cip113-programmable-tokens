package org.cardanofoundation.cip113.model;

/**
 * Generic wrapper for transaction results containing the unsigned CBOR transaction
 * and any additional metadata needed for the operation.
 *
 * <p>Usage examples:</p>
 * <ul>
 *   <li>{@code TransactionContext<Void>} - simple transactions with no extra data</li>
 *   <li>{@code TransactionContext<RegistrationResult>} - registration with policyId</li>
 *   <li>{@code TransactionContext<BlacklistInitResult>} - blacklist init with bootstrap params</li>
 * </ul>
 *
 * @param <T> The type of additional metadata returned with the transaction
 * @param unsignedCborTx The unsigned transaction in CBOR hex format
 * @param metadata       Additional operation-specific data (null for simple transactions)
 * @param isSuccessful   Whether the transaction was built successfully
 * @param error          Error message if unsuccessful
 */
public record TransactionContext<T>(
        String unsignedCborTx,
        T metadata,
        boolean isSuccessful,
        String error
) {

    /**
     * Create a successful transaction context with no metadata.
     */
    public static TransactionContext<Void> ok(String unsignedCborTx) {
        return new TransactionContext<>(unsignedCborTx, null, true, null);
    }

    /**
     * Create a successful transaction context with metadata.
     */
    public static <T> TransactionContext<T> ok(String unsignedCborTx, T metadata) {
        return new TransactionContext<>(unsignedCborTx, metadata, true, null);
    }

    /**
     * Create an error transaction context with no metadata type.
     */
    public static TransactionContext<Void> error(String error) {
        return new TransactionContext<>(null, null, false, error);
    }

    /**
     * Create a typed error transaction context.
     * Useful when the return type must match a specific generic type.
     */
    public static <T> TransactionContext<T> typedError(String error) {
        return new TransactionContext<>(null, null, false, error);
    }

    // ========== Common Metadata Types ==========

    /**
     * Metadata for token registration operations.
     */
    public record RegistrationResult(String policyId) {}

    /**
     * Metadata for Minting Transactions
     */
    public record MintingResult(String policyId, String assetName) {}

    /**
     * Metadata for blacklist initialization operations.
     */
    public record BlacklistInitResult(String bootstrapParameters) {}
}
