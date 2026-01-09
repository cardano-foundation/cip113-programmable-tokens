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

    /**
     * Get the latest (non-deleted) state for a given key.
     * Uses native query with DISTINCT ON to get the most recent entry by slot.
     */
    @Query(value = "SELECT DISTINCT ON (key) * FROM registry_node " +
                   "WHERE key = :key AND is_deleted = false " +
                   "ORDER BY key, slot DESC, block_height DESC",
           nativeQuery = true)
    Optional<RegistryNodeEntity> findByKey(@Param("key") String key);

    /**
     * Get all latest (non-deleted) tokens for a protocol params version, excluding sentinel.
     * Uses native query with DISTINCT ON grouped by key to get most recent state of each token.
     */
    @Query(value = "SELECT DISTINCT ON (key) * FROM registry_node " +
                   "WHERE protocol_params_id = :protocolParamsId AND key != '' AND is_deleted = false " +
                   "ORDER BY key, slot DESC, block_height DESC",
           nativeQuery = true)
    List<RegistryNodeEntity> findAllByProtocolParamsIdExcludingSentinel(@Param("protocolParamsId") Long protocolParamsId);

    /**
     * Get all latest (non-deleted) tokens across all protocol params, excluding sentinels.
     */
    @Query(value = "SELECT DISTINCT ON (key) * FROM registry_node " +
                   "WHERE key != '' AND is_deleted = false " +
                   "ORDER BY key, slot DESC, block_height DESC",
           nativeQuery = true)
    List<RegistryNodeEntity> findAllExcludingSentinel();

    /**
     * Get all latest (non-deleted) nodes (including sentinel) for a protocol params.
     */
    @Query(value = "SELECT DISTINCT ON (key) * FROM registry_node " +
                   "WHERE protocol_params_id = :protocolParamsId AND is_deleted = false " +
                   "ORDER BY key, slot DESC, block_height DESC",
           nativeQuery = true)
    List<RegistryNodeEntity> findAllByProtocolParamsId(@Param("protocolParamsId") Long protocolParamsId);

    /**
     * Get all latest (non-deleted) nodes sorted by key.
     */
    @Query(value = "SELECT DISTINCT ON (key) * FROM registry_node " +
                   "WHERE is_deleted = false " +
                   "ORDER BY key, slot DESC, block_height DESC",
           nativeQuery = true)
    List<RegistryNodeEntity> findAllByOrderByKeyAsc();

    /**
     * Check if a key exists (non-deleted).
     */
    @Query("SELECT CASE WHEN COUNT(r) > 0 THEN true ELSE false END FROM RegistryNodeEntity r " +
           "WHERE r.key = :key AND r.isDeleted = false")
    boolean existsByKey(@Param("key") String key);

    /**
     * Count latest (non-deleted) tokens for a protocol params, excluding sentinel.
     */
    @Query(value = "SELECT COUNT(DISTINCT key) FROM registry_node " +
                   "WHERE protocol_params_id = :protocolParamsId AND key != '' AND is_deleted = false",
           nativeQuery = true)
    long countByProtocolParamsIdExcludingSentinel(@Param("protocolParamsId") Long protocolParamsId);

    /**
     * Get the latest (non-deleted) state for a key in a specific protocol params.
     */
    @Query(value = "SELECT DISTINCT ON (key) * FROM registry_node " +
                   "WHERE key = :key AND protocol_params_id = :protocolParamsId AND is_deleted = false " +
                   "ORDER BY key, slot DESC, block_height DESC",
           nativeQuery = true)
    Optional<RegistryNodeEntity> findByKeyAndProtocolParamsId(@Param("key") String key, @Param("protocolParamsId") Long protocolParamsId);

    /**
     * Find all latest (non-deleted) nodes between two keys (for orphan detection).
     */
    @Query(value = "SELECT DISTINCT ON (key) * FROM registry_node " +
                   "WHERE protocol_params_id = :protocolParamsId AND key > :startKey AND key < :endKey AND is_deleted = false " +
                   "ORDER BY key, slot DESC, block_height DESC",
           nativeQuery = true)
    List<RegistryNodeEntity> findNodesBetweenKeys(@Param("protocolParamsId") Long protocolParamsId, @Param("startKey") String startKey, @Param("endKey") String endKey);
}
