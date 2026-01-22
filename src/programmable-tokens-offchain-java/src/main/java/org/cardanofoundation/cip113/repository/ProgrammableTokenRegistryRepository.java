package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * Repository for the unified programmable token registry.
 * Used to look up which substandard a token belongs to.
 */
@Repository
public interface ProgrammableTokenRegistryRepository extends JpaRepository<ProgrammableTokenRegistryEntity, String> {

    /**
     * Find the substandard for a given policy ID.
     */
    Optional<ProgrammableTokenRegistryEntity> findByPolicyId(String policyId);

    /**
     * Find all tokens for a given substandard.
     */
    List<ProgrammableTokenRegistryEntity> findBySubstandardId(String substandardId);

    /**
     * Check if a token is registered.
     */
    boolean existsByPolicyId(String policyId);
}
