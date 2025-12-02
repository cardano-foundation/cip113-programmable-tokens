package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * JPA Repository for CIP-113 Protocol Parameters.
 *
 * <p>Provides data access for querying and persisting protocol parameter
 * versions. Protocol params are immutable once created, and this repository
 * supports finding the latest version or looking up by transaction hash.</p>
 *
 * <h2>Query Methods</h2>
 * <ul>
 *   <li><b>findLatest:</b> Most recent protocol parameters</li>
 *   <li><b>findByTxHash:</b> Lookup by creating transaction</li>
 *   <li><b>findAllByOrderBySlotAsc:</b> All versions in chronological order</li>
 * </ul>
 *
 * @see ProtocolParamsEntity
 * @see org.cardanofoundation.cip113.service.ProtocolParamsService
 */
@Repository
public interface ProtocolParamsRepository extends JpaRepository<ProtocolParamsEntity, Long> {

    Optional<ProtocolParamsEntity> findByTxHash(String txHash);

    List<ProtocolParamsEntity> findAllByOrderBySlotAsc();

    @Query("SELECT p FROM ProtocolParamsEntity p ORDER BY p.slot DESC LIMIT 1")
    Optional<ProtocolParamsEntity> findLatest();

    Optional<ProtocolParamsEntity> findBySlot(Long slot);

    boolean existsByTxHash(String txHash);
}
