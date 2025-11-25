package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "protocol_params", indexes = {
    @Index(name = "idx_tx_hash", columnList = "txHash"),
    @Index(name = "idx_slot", columnList = "slot")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ProtocolParamsEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 56)
    private String registryNodePolicyId;

    @Column(nullable = false, length = 56)
    private String progLogicScriptHash;

    @Column(nullable = false, unique = true, length = 64)
    private String txHash;

    @Column(nullable = false)
    private Long slot;

    @Column(nullable = false)
    private Long blockHeight;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }
}
