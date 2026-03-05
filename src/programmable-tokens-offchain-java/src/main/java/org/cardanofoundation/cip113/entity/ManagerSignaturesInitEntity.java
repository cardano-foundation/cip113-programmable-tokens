package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Entity representing manager signatures initialization data for the
 * whitelist-send-receive-multiadmin substandard.
 * Tracks the one-shot NFT policy used for the ManagerConfig (super-admin credential list).
 */
@Entity
@Table(name = "whitelist_manager_signatures_init", uniqueConstraints = {
    @UniqueConstraint(name = "uk_mgr_sigs_admin_tx_output", columnNames = {"admin_pkh", "tx_hash", "output_index"})
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ManagerSignaturesInitEntity {

    /**
     * Policy ID of the manager signatures NFTs (primary key).
     * Derived from manager_signatures.mint validator parameterized with utxo_ref.
     */
    @Id
    @Column(name = "manager_sigs_policy_id", nullable = false, length = 56)
    private String managerSigsPolicyId;

    /**
     * Public key hash of the super-admin who initialized this manager config.
     */
    @Column(name = "admin_pkh", nullable = false, length = 56)
    private String adminPkh;

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

    /**
     * JSON array of super-admin public key hashes.
     */
    @Column(name = "super_admin_pkhs", columnDefinition = "TEXT")
    private String superAdminPkhs;
}
