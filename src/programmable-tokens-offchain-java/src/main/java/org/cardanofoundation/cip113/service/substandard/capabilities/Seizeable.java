package org.cardanofoundation.cip113.service.substandard.capabilities;

import org.cardanofoundation.cip113.model.TransactionContext;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;

import java.util.List;

/**
 * Seize capability for taking assets from blacklisted/sanctioned addresses.
 * This is typically used by regulated stablecoins to comply with legal requirements
 * for asset recovery from sanctioned entities.
 *
 * Seize operations require:
 * 1. The target address to be on the blacklist
 * 2. Admin authorization
 * 3. Proper on-chain proofs
 */
public interface Seizeable {

    /**
     * Request to seize assets from a single UTxO.
     */
    record SeizeRequest(
            String feePayerAddress,
            /** Policy ID of + Asset Name of the programmable token to seize */
            String unit,
            /** Transaction hash containing the UTxO to seize */
            String utxoTxHash,
            /** Output index of the UTxO to seize */
            int utxoOutputIndex,
            /** Destination address for seized assets */
            String destinationAddress
    ) {}

    /**
     * Request to seize assets from multiple UTxOs in a single transaction.
     * More efficient for seizing from addresses with multiple token UTxOs.
     */
    record MultiSeizeRequest(
            /** The admin address performing the seizure */
            String adminAddress,
            /** List of UTxO references to seize (txHash#outputIndex format) */
            List<String> utxoReferences,
            /** Policy ID of the programmable token to seize */
            String policyId,
            /** Destination address for seized assets */
            String destinationAddress
    ) {}

    /**
     * Build a transaction to seize assets from a blacklisted address.
     * The target address must already be on the blacklist for this to succeed.
     *
     * @param request        The seize request
     * @param protocolParams The protocol bootstrap parameters
     * @return Transaction context with unsigned CBOR tx
     */
    TransactionContext<Void> buildSeizeTransaction(
            SeizeRequest request,
            ProtocolBootstrapParams protocolParams);

    /**
     * Build a transaction to seize assets from multiple UTxOs in one transaction.
     * More gas-efficient when seizing from multiple UTxOs.
     *
     * @param request        The multi-seize request
     * @param protocolParams The protocol bootstrap parameters
     * @return Transaction context with unsigned CBOR tx
     */
    default TransactionContext<Void> buildMultiSeizeTransaction(
            MultiSeizeRequest request,
            ProtocolBootstrapParams protocolParams) {
        // Default implementation: process first UTxO only
        // Handlers should override for proper multi-seize support
        if (request.utxoReferences().isEmpty()) {
            return TransactionContext.typedError("No UTxOs specified for seizure");
        }

       return TransactionContext.typedError("not implemented");
    }
}
