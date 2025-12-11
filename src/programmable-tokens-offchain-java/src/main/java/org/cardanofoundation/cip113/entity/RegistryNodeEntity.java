package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * JPA entity representing a node in the CIP-0113 token registry.
 *
 * <p>Each registry node stores the configuration for a registered programmable token,
 * including its transfer logic scripts and global state policy. The nodes form a
 * sorted linked list on-chain, indexed by the token's policy ID.
 *
 * <h2>Database Schema</h2>
 * <ul>
 *   <li><b>key</b>: Token policy ID (unique per protocol params version)</li>
 *   <li><b>next</b>: Pointer to next node in linked list</li>
 *   <li><b>transferLogicScript</b>: Script hash for owner-initiated transfers</li>
 *   <li><b>thirdPartyTransferLogicScript</b>: Script hash for delegated transfers</li>
 *   <li><b>globalStatePolicyId</b>: Optional policy for shared token state</li>
 * </ul>
 *
 * <h2>Linked List Structure</h2>
 * <p>The registry is a sorted linked list where:
 * <ul>
 *   <li>Head node has key "" (empty string) as sentinel</li>
 *   <li>Nodes are sorted lexicographically by policy ID</li>
 *   <li>Last node points to sentinel (key "")</li>
 * </ul>
 *
 * @see org.cardanofoundation.cip113.service.RegistryService
 * @see org.cardanofoundation.cip113.repository.RegistryNodeRepository
 */
@Entity
@Table(name = "registry_node", indexes = {
    @Index(name = "idx_registry_key", columnList = "key"),
    @Index(name = "idx_registry_next", columnList = "next"),
    @Index(name = "idx_registry_protocol_params", columnList = "protocolParamsId"),
    @Index(name = "idx_registry_last_slot", columnList = "lastSlot")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RegistryNodeEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 64)
    private String key;

    @Column(nullable = false, length = 64)
    private String next;

    @Column(nullable = false, length = 56)
    private String transferLogicScript;

    @Column(nullable = false, length = 56)
    private String thirdPartyTransferLogicScript;

    @Column(length = 56)
    private String globalStatePolicyId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "protocolParamsId", nullable = false)
    private ProtocolParamsEntity protocolParams;

    @Column(nullable = false, length = 64)
    private String lastTxHash;

    @Column(nullable = false)
    private Long lastSlot;

    @Column(nullable = false)
    private Long lastBlockHeight;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
