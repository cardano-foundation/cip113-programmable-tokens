package org.cardanofoundation.cip113.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * Protocol version information for frontend display
 * Includes essential fields for version selection and identification
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ProtocolVersionInfo {

    /**
     * Registry node policy ID for this protocol version
     */
    private String registryNodePolicyId;

    /**
     * Programmable logic script hash for this protocol version
     * Used to filter balances and transactions
     */
    private String progLogicScriptHash;

    /**
     * Bootstrap transaction hash identifying this protocol version
     */
    private String txHash;

    /**
     * Slot number when this protocol version was bootstrapped
     */
    private Long slot;

    /**
     * Timestamp (slot converted to LocalDateTime)
     */
    private Long timestamp;

    /**
     * Whether this is the current/default protocol version
     * (matches txHash from protocol-bootstraps-preview.json)
     */
    private boolean isDefault;
}
