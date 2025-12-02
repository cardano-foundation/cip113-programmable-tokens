package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigInteger;
import java.time.LocalDateTime;

/**
 * JPA Entity for tracking CIP-113 token balances.
 *
 * <p>Stores balance entries for each address that holds programmable tokens.
 * Each entry records the token value at a specific slot, allowing for
 * historical balance queries and event-driven updates.</p>
 *
 * <h2>Indexing Strategy</h2>
 * <ul>
 *   <li><b>address:</b> Fast lookup by holder address</li>
 *   <li><b>paymentScriptHash:</b> Query by programmable logic script</li>
 *   <li><b>stakeKeyHash:</b> Query by staking key</li>
 *   <li><b>txHash:</b> Trace balance to originating transaction</li>
 *   <li><b>slot:</b> Time-based queries and ordering</li>
 * </ul>
 *
 * @see org.cardanofoundation.cip113.service.BalanceService
 * @see org.cardanofoundation.cip113.repository.BalanceLogRepository
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
