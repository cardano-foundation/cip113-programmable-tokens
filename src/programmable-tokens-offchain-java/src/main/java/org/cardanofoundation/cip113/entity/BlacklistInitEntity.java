package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Entity representing freeze-and-seize blacklist initialization data.
 * Used to build FreezeAndSeizeContext for compliance operations.
 */
@Entity
@Table(name = "freeze_and_seize_blacklist_init", uniqueConstraints = {
    @UniqueConstraint(name = "uk_admin_tx_output", columnNames = {"admin_pkh", "tx_hash", "output_index"})
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BlacklistInitEntity {

    /**
     * Policy ID of the blacklist node NFTs (primary key).
     */
    @Id
    @Column(name = "blacklist_node_policy_id", nullable = false, length = 56)
    private String blacklistNodePolicyId;

    /**
     * Public key hash of the admin who manages this blacklist.
     */
    @Column(name = "admin_pkh", nullable = false, length = 56)
    private String adminPkh;

    /**
     * Transaction hash where the blacklist was initialized.
     */
    @Column(name = "tx_hash", nullable = false, length = 64)
    private String txHash;

    /**
     * Output index of the blacklist init UTxO.
     */
    @Column(name = "output_index", nullable = false)
    private Integer outputIndex;
}
