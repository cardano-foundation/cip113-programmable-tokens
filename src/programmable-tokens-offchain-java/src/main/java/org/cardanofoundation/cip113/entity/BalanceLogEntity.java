package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.cardanofoundation.cip113.model.TransactionType;

import java.math.BigInteger;
import java.time.LocalDateTime;

@Entity
@Table(name = "balance_log", indexes = {
    @Index(name = "idx_balance_address", columnList = "address"),
    @Index(name = "idx_balance_payment_script", columnList = "paymentScriptHash"),
    @Index(name = "idx_balance_stake_key", columnList = "stakeKeyHash"),
    @Index(name = "idx_balance_payment_stake", columnList = "paymentScriptHash, stakeKeyHash"),
    @Index(name = "idx_balance_tx_hash", columnList = "txHash"),
    @Index(name = "idx_balance_slot", columnList = "slot"),
    @Index(name = "idx_balance_transaction_type", columnList = "transactionType"),
    @Index(name = "idx_balance_payment_type", columnList = "paymentScriptHash, transactionType")
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

    // Transaction Type and Balance Difference
    @Enumerated(EnumType.STRING)
    @Column(name = "transaction_type")
    private TransactionType transactionType;

    @Column(name = "balance_diff", columnDefinition = "TEXT")
    private String balanceDiff;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }
}
