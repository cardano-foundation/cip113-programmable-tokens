package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Entity representing whitelist-send-receive-multiadmin token registration data.
 * Links programmable tokens to their whitelist, manager list, and manager signatures init records.
 */
@Entity
@Table(name = "whitelist_token_registration")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class WhitelistTokenRegistrationEntity {

    /**
     * Policy ID of the programmable token (primary key).
     */
    @Id
    @Column(name = "programmable_token_policy_id", nullable = false, length = 56)
    private String programmableTokenPolicyId;

    /**
     * Public key hash of the issuer admin (super-admin).
     */
    @Column(name = "issuer_admin_pkh", nullable = false, length = 56)
    private String issuerAdminPkh;

    /**
     * Foreign key to the whitelist init record.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "whitelist_policy_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_whitelist_init"))
    private WhitelistInitEntity whitelistInit;

    /**
     * Foreign key to the manager list init record.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "manager_list_policy_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_manager_list_init"))
    private ManagerListInitEntity managerListInit;

    /**
     * Foreign key to the manager signatures init record.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "manager_sigs_policy_id", nullable = false,
            foreignKey = @ForeignKey(name = "fk_manager_sigs_init_reg"))
    private ManagerSignaturesInitEntity managerSigsInit;
}
