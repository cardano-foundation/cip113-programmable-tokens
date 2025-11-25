package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ProtocolParamsRepository extends JpaRepository<ProtocolParamsEntity, Long> {

    Optional<ProtocolParamsEntity> findByTxHash(String txHash);

    List<ProtocolParamsEntity> findAllByOrderBySlotAsc();

    @Query("SELECT p FROM ProtocolParamsEntity p ORDER BY p.slot DESC LIMIT 1")
    Optional<ProtocolParamsEntity> findLatest();

    Optional<ProtocolParamsEntity> findBySlot(Long slot);

    boolean existsByTxHash(String txHash);
}
