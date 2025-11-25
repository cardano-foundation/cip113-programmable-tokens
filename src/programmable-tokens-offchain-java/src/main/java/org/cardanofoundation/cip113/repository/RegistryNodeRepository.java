package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface RegistryNodeRepository extends JpaRepository<RegistryNodeEntity, Long> {

    Optional<RegistryNodeEntity> findByKey(String key);

    @Query("SELECT r FROM RegistryNodeEntity r WHERE r.protocolParams.id = :protocolParamsId AND r.key != '' ORDER BY r.key ASC")
    List<RegistryNodeEntity> findAllByProtocolParamsIdExcludingSentinel(@Param("protocolParamsId") Long protocolParamsId);

    @Query("SELECT r FROM RegistryNodeEntity r WHERE r.key != '' ORDER BY r.key ASC")
    List<RegistryNodeEntity> findAllExcludingSentinel();

    @Query("SELECT r FROM RegistryNodeEntity r WHERE r.protocolParams.id = :protocolParamsId ORDER BY r.key ASC")
    List<RegistryNodeEntity> findAllByProtocolParamsId(@Param("protocolParamsId") Long protocolParamsId);

    List<RegistryNodeEntity> findAllByOrderByKeyAsc();

    boolean existsByKey(String key);

    @Query("SELECT COUNT(r) FROM RegistryNodeEntity r WHERE r.protocolParams.id = :protocolParamsId AND r.key != ''")
    long countByProtocolParamsIdExcludingSentinel(@Param("protocolParamsId") Long protocolParamsId);

    @Query("SELECT r FROM RegistryNodeEntity r WHERE r.key = :key AND r.protocolParams.id = :protocolParamsId")
    Optional<RegistryNodeEntity> findByKeyAndProtocolParamsId(@Param("key") String key, @Param("protocolParamsId") Long protocolParamsId);
}
