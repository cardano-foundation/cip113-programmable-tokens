package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "registry_node",
    uniqueConstraints = {
        @UniqueConstraint(name = "uq_registry_key_slot_tx", columnNames = {"key", "slot", "txHash"})
    },
    indexes = {
        @Index(name = "idx_registry_key", columnList = "key"),
        @Index(name = "idx_registry_next", columnList = "next"),
        @Index(name = "idx_registry_protocol_params", columnList = "protocolParamsId"),
        @Index(name = "idx_registry_slot", columnList = "slot"),
        @Index(name = "idx_registry_is_deleted", columnList = "isDeleted"),
        @Index(name = "idx_registry_key_slot_deleted", columnList = "key, slot, isDeleted")
    })
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RegistryNodeEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // NOTE: In the rare edge case where multiple transactions in the same slot modify the same key,
    // we won't know which one is "latest" within that slot. This is unlikely in practice.
    // The composite unique constraint (key, slot, txHash) prevents race conditions during bulk processing.
    @Column(nullable = false, length = 64)
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
    private String txHash;

    @Column(nullable = false)
    private Long slot;

    @Column(nullable = false)
    private Long blockHeight;

    // Marks whether this UTxO was spent/burned (node removed from linked list)
    @Column(nullable = false)
    private Boolean isDeleted;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
        if (isDeleted == null) {
            isDeleted = false;
        }
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
