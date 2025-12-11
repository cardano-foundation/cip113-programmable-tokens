package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * JPA entity representing a CIP-0113 protocol parameters version.
 *
 * <p>Each protocol params entity corresponds to a unique deployment of the
 * CIP-0113 protocol on-chain, identified by the bootstrap transaction hash.
 * Multiple protocol versions can coexist, allowing for protocol upgrades.
 *
 * <h2>Key Fields</h2>
 * <ul>
 *   <li><b>registryNodePolicyId</b>: Policy ID for minting registry NFTs</li>
 *   <li><b>progLogicScriptHash</b>: Programmable logic base script hash</li>
 *   <li><b>txHash</b>: Bootstrap transaction that created this version</li>
 * </ul>
 *
 * <h2>Version Management</h2>
 * <p>Protocol versions are loaded from {@code protocolBootstrap.json} at startup.
 * The latest version is typically used for new operations, while older versions
 * remain queryable for historical data.
 *
 * @see org.cardanofoundation.cip113.service.ProtocolParamsService
 * @see org.cardanofoundation.cip113.service.ProtocolBootstrapService
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
