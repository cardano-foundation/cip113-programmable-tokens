package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.BlacklistInitEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/**
 * Repository for freeze-and-seize blacklist initialization data.
 */
@Repository
public interface BlacklistInitRepository extends JpaRepository<BlacklistInitEntity, String> {

    /**
     * Find blacklist init by policy ID.
     */
    Optional<BlacklistInitEntity> findByBlacklistNodePolicyId(String blacklistNodePolicyId);

    /**
     * Find blacklist init by transaction hash.
     */
    Optional<BlacklistInitEntity> findByTxHash(String txHash);

    /**
     * Check if a blacklist init exists for the given policy ID.
     */
    boolean existsByBlacklistNodePolicyId(String blacklistNodePolicyId);

    /**
     * Find blacklist init by admin public key hash.
     */
    Optional<BlacklistInitEntity> findByAdminPkh(String adminPkh);
}
