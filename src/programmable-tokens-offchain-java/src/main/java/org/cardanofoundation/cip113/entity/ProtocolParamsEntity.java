package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * JPA Entity for CIP-113 Protocol Parameters.
 *
 * <p>Stores versioned protocol parameters that define the on-chain
 * configuration for programmable tokens. Each version is immutable and
 * identified by the transaction hash that created it.</p>
 *
 * <h2>Protocol Parameters</h2>
 * <ul>
 *   <li><b>registryNodePolicyId:</b> Policy ID for registry NFTs</li>
 *   <li><b>progLogicScriptHash:</b> Script hash for programmable logic</li>
 *   <li><b>transLogicScriptHash:</b> Script hash for transfer logic</li>
 *   <li><b>illiquidSupplyScriptHash:</b> Script hash for illiquid supply tracking</li>
 * </ul>
 *
 * @see org.cardanofoundation.cip113.service.ProtocolParamsService
 * @see org.cardanofoundation.cip113.repository.ProtocolParamsRepository
 */
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
