package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Entity representing whitelist initialization data for the
 * whitelist-send-receive-multiadmin substandard.
 * Tracks the linked-list NFT policy used for whitelisted address nodes.
 */
@Entity
@Table(name = "whitelist_init", uniqueConstraints = {
    @UniqueConstraint(name = "uk_whitelist_tx_output", columnNames = {"tx_hash", "output_index"})
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class WhitelistInitEntity {

    /**
     * Policy ID of the whitelist node NFTs (primary key).
     * Derived from whitelist_mint validator parameterized with (utxo_ref, manager_auth_hash).
     */
    @Id
    @Column(name = "whitelist_policy_id", nullable = false, length = 56)
    private String whitelistPolicyId;

    /**
     * Script hash of the manager_auth withdraw validator.
     * Computed from manager_auth(manager_list_cs).
     */
    @Column(name = "manager_auth_hash", nullable = false, length = 56)
    private String managerAuthHash;

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
