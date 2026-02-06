package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Entity representing freeze-and-seize token registration data.
 * Links programmable tokens to their blacklist initialization.
 */
@Entity
@Table(name = "freeze_and_seize_token_registration")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FreezeAndSeizeTokenRegistrationEntity {

    /**
     * Policy ID of the programmable token (primary key).
     */
    @Id
    @Column(name = "programmable_token_policy_id", nullable = false, length = 56)
    private String programmableTokenPolicyId;

    /**
     * Public key hash of the issuer admin.
     */
    @Column(name = "issuer_admin_pkh", nullable = false, length = 56)
    private String issuerAdminPkh;

    /**
     * Foreign key to the blacklist init record.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "blacklist_node_policy_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_blacklist_init"))
    private BlacklistInitEntity blacklistInit;
}
