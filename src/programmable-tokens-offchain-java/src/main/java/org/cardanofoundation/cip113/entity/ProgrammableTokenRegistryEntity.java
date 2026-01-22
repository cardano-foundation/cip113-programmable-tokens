package org.cardanofoundation.cip113.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Unified registry mapping programmable token policy IDs to their substandard.
 * All substandards insert here during token registration.
 */
@Entity
@Table(name = "programmable_token_registry")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ProgrammableTokenRegistryEntity {

    /**
     * Policy ID of the programmable token (primary key).
     */
    @Id
    @Column(name = "policy_id", nullable = false, length = 56)
    private String policyId;

    /**
     * Substandard identifier (e.g., "dummy", "freeze-and-seize").
     */
    @Column(name = "substandard_id", nullable = false, length = 50)
    private String substandardId;
}
