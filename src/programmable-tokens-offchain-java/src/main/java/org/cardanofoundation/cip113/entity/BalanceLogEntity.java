package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigInteger;
import java.time.LocalDateTime;

/**
 * JPA entity representing a balance snapshot at a specific point in time.
 *
 * <p>Each entry captures the complete balance state of a programmable token address
 * after a transaction. This enables:
 * <ul>
 *   <li>Current balance queries (latest entry per address)</li>
 *   <li>Historical balance tracking</li>
 *   <li>Balance aggregation by payment credential</li>
 * </ul>
 *
 * <h2>Balance Format</h2>
 * <p>The {@code balance} field is a JSON string mapping asset units to amounts:
 * <pre>{@code
 * {
 *   "lovelace": "5000000",
 *   "policyId+assetName": "100"
 * }
 * }</pre>
 *
 * <h2>Address Decomposition</h2>
 * <p>Addresses are decomposed for efficient querying:
 * <ul>
 *   <li><b>paymentScriptHash</b>: Always the programmable logic base hash</li>
 *   <li><b>stakeKeyHash</b>: User's stake credential for aggregation</li>
 * </ul>
 *
 * @see org.cardanofoundation.cip113.service.BalanceService
 * @see org.cardanofoundation.cip113.util.BalanceValueHelper
 */
@Entity
@Table(name = "balance_log", indexes = {
    @Index(name = "idx_balance_address", columnList = "address"),
    @Index(name = "idx_balance_payment_script", columnList = "paymentScriptHash"),
    @Index(name = "idx_balance_stake_key", columnList = "stakeKeyHash"),
    @Index(name = "idx_balance_payment_stake", columnList = "paymentScriptHash, stakeKeyHash"),
    @Index(name = "idx_balance_tx_hash", columnList = "txHash"),
    @Index(name = "idx_balance_slot", columnList = "slot")
}, uniqueConstraints = {
    @UniqueConstraint(name = "unique_balance_entry", columnNames = {"address", "txHash"})
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BalanceLogEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // Address Information
    @Column(nullable = false, length = 200)
    private String address;

    @Column(nullable = false, length = 56)
    private String paymentScriptHash;

    @Column(length = 56)
    private String stakeKeyHash;

    // Transaction Context
    @Column(nullable = false, length = 64)
    private String txHash;

    @Column(nullable = false)
    private Long slot;

    @Column(nullable = false)
    private Long blockHeight;

    // Balance State (after this transaction) - JSON format: {"lovelace": "1000000", "unit": "amount"}
    @Column(nullable = false, columnDefinition = "TEXT")
    private String balance;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }
}
