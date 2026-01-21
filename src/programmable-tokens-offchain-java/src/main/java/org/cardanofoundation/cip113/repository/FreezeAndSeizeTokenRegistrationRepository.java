package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.FreezeAndSeizeTokenRegistrationEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * Repository for freeze-and-seize token registration data.
 */
@Repository
public interface FreezeAndSeizeTokenRegistrationRepository extends JpaRepository<FreezeAndSeizeTokenRegistrationEntity, String> {

    /**
     * Find token registration by programmable token policy ID.
     */
    Optional<FreezeAndSeizeTokenRegistrationEntity> findByProgrammableTokenPolicyId(String programmableTokenPolicyId);

    /**
     * Find all token registrations by issuer admin public key hash.
     */
    List<FreezeAndSeizeTokenRegistrationEntity> findByIssuerAdminPkh(String issuerAdminPkh);

    /**
     * Find all token registrations linked to a specific blacklist.
     */
    List<FreezeAndSeizeTokenRegistrationEntity> findByBlacklistInit_BlacklistNodePolicyId(String blacklistNodePolicyId);

    /**
     * Check if a token registration exists for the given policy ID.
     */
    boolean existsByProgrammableTokenPolicyId(String programmableTokenPolicyId);
}
