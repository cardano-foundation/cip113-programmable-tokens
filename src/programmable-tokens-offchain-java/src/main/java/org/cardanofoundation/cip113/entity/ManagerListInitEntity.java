package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Entity representing manager list initialization data for the
 * whitelist-send-receive-multiadmin substandard.
 * Tracks the linked-list NFT policy used for manager credential nodes.
 */
@Entity
@Table(name = "whitelist_manager_list_init", uniqueConstraints = {
    @UniqueConstraint(name = "uk_mgr_list_tx_output", columnNames = {"tx_hash", "output_index"})
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ManagerListInitEntity {

    /**
     * Policy ID of the manager list node NFTs (primary key).
     * Derived from manager_list_mint validator parameterized with (utxo_ref, manager_sigs_hash).
     */
    @Id
    @Column(name = "manager_list_policy_id", nullable = false, length = 56)
    private String managerListPolicyId;

    /**
     * Foreign key to the manager signatures init record.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "manager_sigs_policy_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_manager_sigs_init"))
    private ManagerSignaturesInitEntity managerSigsInit;

    /**
     * Transaction hash of the seed UTxO consumed to initialize.
     */
    @Column(name = "tx_hash", nullable = false, length = 64)
    private String txHash;

    /**
     * Output index of the seed UTxO consumed to initialize.
     */
    @Column(name = "output_index", nullable = false)
    private Integer outputIndex;
}
