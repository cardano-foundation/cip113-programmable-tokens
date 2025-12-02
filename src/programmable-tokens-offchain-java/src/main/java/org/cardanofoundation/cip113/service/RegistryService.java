package org.cardanofoundation.cip113.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.cardanofoundation.cip113.repository.RegistryNodeRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

/**
 * Service for managing the CIP-0113 programmable token registry.
 *
 * <p>The registry maintains a sorted linked list of registered programmable tokens,
 * stored on-chain as UTxOs and synchronized to a local database for efficient querying.
 * Each registry node contains:</p>
 * <ul>
 *   <li><strong>Key</strong>: The token policy ID (hex-encoded)</li>
 *   <li><strong>Next</strong>: Pointer to the next node in the sorted list</li>
 *   <li><strong>Configuration</strong>: Token-specific parameters and transfer logic reference</li>
 * </ul>
 *
 * <h2>Linked List Structure</h2>
 * <p>The registry uses a sorted linked list for efficient on-chain operations:</p>
 * <pre>
 * Sentinel ("") → Token_A → Token_B → Token_C → ""
 *                 ↓           ↓           ↓
 *              Config_A    Config_B    Config_C
 * </pre>
 *
 * <p>The sentinel node (empty key) serves as the list head, enabling O(1) insertion
 * at any position without modifying the entire list.</p>
 *
 * <h2>Synchronization</h2>
 * <p>Registry state is synchronized from the blockchain via {@link RegistryEventListener},
 * which processes registry transactions and calls {@link #upsert(RegistryNodeEntity)}
 * to update the local database.</p>
 *
 * <h2>Protocol Params Versioning</h2>
 * <p>The registry supports multiple protocol parameter versions, allowing tracking
 * of registry state across protocol upgrades. Each node is associated with a
 * specific {@link ProtocolParamsEntity} version.</p>
 *
 * @see RegistryNodeEntity
 * @see RegistryEventListener
 * @see RegistryNodeRepository
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class RegistryService {

    /** Repository for registry node persistence operations */
    private final RegistryNodeRepository repository;

    /**
     * Upsert a registry node (create if doesn't exist, update if exists)
     * Only the 'next' field can be updated for existing nodes
     *
     * @param entity the registry node entity to upsert
     * @return the saved/updated entity
     */
    @Transactional
    public RegistryNodeEntity upsert(RegistryNodeEntity entity) {
        Optional<RegistryNodeEntity> existingOpt = repository.findByKeyAndProtocolParamsId(
                entity.getKey(),
                entity.getProtocolParams().getId()
        );

        if (existingOpt.isPresent()) {
            RegistryNodeEntity existing = existingOpt.get();

            // Check if 'next' changed (the only mutable field)
            if (!existing.getNext().equals(entity.getNext())) {
                log.info("Updating registry node: key={}, old_next={}, new_next={}, tx={}",
                        entity.getKey(), existing.getNext(), entity.getNext(), entity.getLastTxHash());

                existing.setNext(entity.getNext());
                existing.setLastTxHash(entity.getLastTxHash());
                existing.setLastSlot(entity.getLastSlot());
                existing.setLastBlockHeight(entity.getLastBlockHeight());

                return repository.save(existing);
            } else {
                log.debug("Registry node already exists with same next pointer, skipping: key={}", entity.getKey());
                return existing;
            }
        } else {
            log.info("Creating new registry node: key={}, next={}, tx={}, protocolParamsId={}",
                    entity.getKey(), entity.getNext(), entity.getLastTxHash(), entity.getProtocolParams().getId());
            return repository.save(entity);
        }
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
     * @param key the token policy ID
     * @param protocolParamsId the protocol params ID
     * @return the registry node or empty if not found
     */
    public Optional<RegistryNodeEntity> getByKeyAndProtocolParams(String key, Long protocolParamsId) {
        return repository.findByKeyAndProtocolParamsId(key, protocolParamsId);
    }
}
