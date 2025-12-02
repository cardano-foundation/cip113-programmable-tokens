package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * JPA Entity for CIP-113 Registry Nodes.
 *
 * <p>Represents a node in the on-chain sorted linked list registry.
 * Each node stores token metadata and points to the next node in the list,
 * allowing efficient on-chain iteration and membership verification.</p>
 *
 * <h2>Linked List Structure</h2>
 * <ul>
 *   <li><b>key:</b> Unique token identifier (policy ID + asset name hash)</li>
 *   <li><b>next:</b> Key of the next node in sorted order (empty for tail)</li>
 *   <li><b>protocolParamsId:</b> Associated protocol parameters version</li>
 * </ul>
 *
 * <h2>Indexing</h2>
 * <p>Indexes on key and next enable efficient traversal and insertion
 * operations for the sorted linked list data structure.</p>
 *
 * @see org.cardanofoundation.cip113.service.RegistryService
 * @see org.cardanofoundation.cip113.repository.RegistryNodeRepository
 */
@Entity
@Table(name = "registry_node", indexes = {
    @Index(name = "idx_registry_key", columnList = "\"key\""),
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

    // Note: Column named with quotes to escape SQL reserved word "key"
    @Column(name = "\"key\"", nullable = false, unique = true, length = 64)
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
