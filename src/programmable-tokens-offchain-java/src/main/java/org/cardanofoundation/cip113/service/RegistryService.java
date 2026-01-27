package org.cardanofoundation.cip113.service;

import com.easy1staking.cardano.model.AssetType;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.cardanofoundation.cip113.repository.RegistryNodeRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

@Service
@Slf4j
@RequiredArgsConstructor
public class RegistryService {

    private final RegistryNodeRepository repository;

    /**
     * Insert a new registry node state into the append-only log.
     * No checking for existing entries - just insert.
     * Duplicate entries are prevented by the unique constraint (key, slot, txHash).
     *
     * @param entity the registry node entity to insert
     * @return the saved entity
     */
    @Transactional
    public RegistryNodeEntity insert(RegistryNodeEntity entity) {
        log.info("Inserting registry node state: key={}, next={}, slot={}, tx={}, protocolParamsId={}",
                entity.getKey(), entity.getNext(), entity.getSlot(), entity.getTxHash(), entity.getProtocolParams().getId());
        return repository.save(entity);
    }

    /**
     * Get all registered tokens for a specific protocol params version
     * Excludes the sentinel/head node (key = "")
     *
     * @param protocolParamsId the protocol params ID
     * @return list of registry nodes (sorted by key)
     */
    public List<RegistryNodeEntity> getAllTokens(Long protocolParamsId) {
        return repository.findAllByProtocolParamsIdExcludingSentinel(protocolParamsId);
    }

    /**
     * Get all registered tokens across all protocol params versions
     * Excludes sentinel nodes
     *
     * @return list of all registry nodes (sorted by key)
     */
    public List<RegistryNodeEntity> getAllTokens() {
        return repository.findAllExcludingSentinel();
    }

    /**
     * Check if a token is registered in any registry
     *
     * @param policyId the token policy ID
     * @return true if registered, false otherwise
     */
    public boolean isTokenRegistered(String policyId) {
        return repository.existsByKey(policyId);
    }

    /**
     * Get token configuration by policy ID
     *
     * @param key the token policy ID
     * @return the registry node or empty if not found
     */
    public Optional<RegistryNodeEntity> getByKey(String key) {
        return repository.findByKey(key);
    }

    /**
     * Get tokens sorted alphabetically (linked list order) for a specific protocol params
     *
     * @param protocolParamsId the protocol params ID
     * @return list of registry nodes sorted by key
     */
    public List<RegistryNodeEntity> getTokensSorted(Long protocolParamsId) {
        return repository.findAllByProtocolParamsIdExcludingSentinel(protocolParamsId);
    }

    /**
     * Get all registry nodes (including sentinel) for a protocol params
     *
     * @param protocolParamsId the protocol params ID
     * @return list of all registry nodes
     */
    public List<RegistryNodeEntity> getAllNodes(Long protocolParamsId) {
        return repository.findAllByProtocolParamsId(protocolParamsId);
    }

    /**
     * Count registered tokens for a protocol params version (excluding sentinel)
     *
     * @param protocolParamsId the protocol params ID
     * @return count of registered tokens
     */
    public long countTokens(Long protocolParamsId) {
        return repository.countByProtocolParamsIdExcludingSentinel(protocolParamsId);
    }

    /**
     * Get registry node by key and protocol params ID
     *
     * @param key              the token policy ID
     * @param protocolParamsId the protocol params ID
     * @return the registry node or empty if not found
     */
    public Optional<RegistryNodeEntity> getByKeyAndProtocolParams(String key, Long protocolParamsId) {
        return repository.findByKeyAndProtocolParamsId(key, protocolParamsId);
    }

    /**
     * Find registry node by policy ID extracted from a unit string.
     * Uses AssetType utility to parse the unit into blacklistNodePolicyId and assetName.
     *
     * @param unit the unit string (blacklistNodePolicyId + assetNameHex)
     * @return the registry node or empty if not found
     */
    public Optional<RegistryNodeEntity> findByPolicyId(String unit) {
        // Use AssetType utility to extract policy ID from unit
        AssetType assetType = AssetType.fromUnit(unit);
        String policyId = assetType.policyId();

        log.debug("Finding registry node by policy ID: {} (from unit: {})", policyId, unit);

        return repository.findByKey(policyId);
    }

    /**
     * Find registry node by policy ID for a specific protocol params version.
     * Uses AssetType utility to parse the unit into blacklistNodePolicyId and assetName.
     *
     * @param unit             the unit string (blacklistNodePolicyId + assetNameHex)
     * @param protocolParamsId the protocol params ID
     * @return the registry node or empty if not found
     */
    public Optional<RegistryNodeEntity> findByPolicyIdAndProtocolParams(String unit, Long protocolParamsId) {
        // Use AssetType utility to extract policy ID from unit
        AssetType assetType = AssetType.fromUnit(unit);
        String policyId = assetType.policyId();

        log.debug("Finding registry node by policy ID: {} for protocol params: {} (from unit: {})",
                policyId, protocolParamsId, unit);

        return repository.findByKeyAndProtocolParamsId(policyId, protocolParamsId);
    }

    /**
     * Mark orphaned nodes as deleted (they were removed from the linked list).
     * When a node is updated to point to a new 'next', any nodes between
     * the current node and the new 'next' are considered deleted from the list.
     *
     * Creates new log entries with isDeleted=true for each orphaned node.
     *
     * @param key              the current node's key
     * @param next             the current node's next pointer
     * @param protocolParamsId the protocol params ID
     * @param slot             the slot where this deletion is detected
     * @param blockHeight      the block height where this deletion is detected
     * @param txHash           the transaction hash that triggered the deletion detection
     */
    @Transactional
    public void deleteOrphanedNodes(String key, String next, Long protocolParamsId, Long slot, Long blockHeight, String txHash) {
        List<RegistryNodeEntity> orphanedNodes = repository.findNodesBetweenKeys(protocolParamsId, key, next);

        if (!orphanedNodes.isEmpty()) {
            log.info("Found {} orphaned node(s) between key='{}' and next='{}' for protocolParamsId={}",
                    orphanedNodes.size(), key, next, protocolParamsId);

            orphanedNodes.forEach(node -> {
                log.info("Marking orphaned node as deleted: key={}, next={}, originalTxHash={}, deletionTxHash={}",
                        node.getKey(), node.getNext(), node.getTxHash(), txHash);

                // Create a new log entry marking this node as deleted
                RegistryNodeEntity deletedEntry = RegistryNodeEntity.builder()
                        .key(node.getKey())
                        .next(node.getNext())
                        .transferLogicScript(node.getTransferLogicScript())
                        .thirdPartyTransferLogicScript(node.getThirdPartyTransferLogicScript())
                        .globalStatePolicyId(node.getGlobalStatePolicyId())
                        .protocolParams(node.getProtocolParams())
                        .txHash(txHash)
                        .slot(slot)
                        .blockHeight(blockHeight)
                        .isDeleted(true)
                        .build();

                repository.save(deletedEntry);
            });
        }
    }
}
