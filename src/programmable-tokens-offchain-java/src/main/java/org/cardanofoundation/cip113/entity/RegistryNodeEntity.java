package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

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
