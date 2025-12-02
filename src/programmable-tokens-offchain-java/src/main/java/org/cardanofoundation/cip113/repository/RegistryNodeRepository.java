package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * JPA Repository for CIP-113 Registry Nodes.
 *
 * <p>Provides data access for the sorted linked list registry. Supports
 * queries for individual nodes, all nodes by protocol params, and counting
 * registered tokens.</p>
 *
 * <h2>Query Methods</h2>
 * <ul>
 *   <li><b>findByKey:</b> Lookup node by unique key</li>
 *   <li><b>findAllExcludingSentinel:</b> All token nodes (excludes sentinel)</li>
 *   <li><b>findAllByProtocolParamsId:</b> Nodes for a specific protocol version</li>
 *   <li><b>countByProtocolParamsId:</b> Number of registered tokens</li>
 * </ul>
 *
 * <h2>Sentinel Node</h2>
 * <p>The linked list uses a sentinel node with empty key ("") as the head.
 * Most queries exclude this sentinel to return only actual token entries.</p>
 *
 * @see RegistryNodeEntity
 * @see org.cardanofoundation.cip113.service.RegistryService
 */
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
