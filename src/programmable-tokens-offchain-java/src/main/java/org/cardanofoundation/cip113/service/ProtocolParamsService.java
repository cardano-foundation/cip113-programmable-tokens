package org.cardanofoundation.cip113.service;

import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.repository.ProtocolParamsRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;

@Service
@Slf4j
@RequiredArgsConstructor
public class ProtocolParamsService {

    private final ProtocolParamsRepository repository;

    // Thread-safe in-memory cache, ordered by slot
    private final CopyOnWriteArrayList<ProtocolParamsEntity> inMemoryCache = new CopyOnWriteArrayList<>();

    /**
     * Load all protocol params from database into memory at boot time
     */
    @PostConstruct
    public void init() {
        log.info("Loading protocol params from database into memory...");
        List<ProtocolParamsEntity> allParams = repository.findAllByOrderBySlotAsc();
        inMemoryCache.addAll(allParams);
        log.info("Loaded {} protocol params versions into memory", inMemoryCache.size());
    }

    /**
     * Save a new protocol params version to both database and in-memory cache
     *
     * @param entity the protocol params entity to save
     * @return the saved entity
     */
    @Transactional
    public ProtocolParamsEntity save(ProtocolParamsEntity entity) {
        // Check if already exists
        if (repository.existsByTxHash(entity.getTxHash())) {
            log.warn("Protocol params with txHash {} already exists, skipping", entity.getTxHash());
            return repository.findByTxHash(entity.getTxHash()).orElseThrow();
        }

        log.info("Saving new protocol params version: txHash={}, slot={}, registryNodePolicyId={}, progLogicScriptHash={}",
                entity.getTxHash(), entity.getSlot(), entity.getRegistryNodePolicyId(), entity.getProgLogicScriptHash());

        // Save to database
        ProtocolParamsEntity saved = repository.save(entity);

        // Add to in-memory cache (sorted by slot)
        addToMemorySorted(saved);

        log.info("Successfully saved protocol params version with id={}", saved.getId());
        return saved;
    }

    /**
     * Add entity to in-memory cache in sorted order (by slot)
     */
    private void addToMemorySorted(ProtocolParamsEntity entity) {
        int insertIndex = 0;
        for (int i = 0; i < inMemoryCache.size(); i++) {
            if (inMemoryCache.get(i).getSlot() > entity.getSlot()) {
                insertIndex = i;
                break;
            }
            insertIndex = i + 1;
        }
        inMemoryCache.add(insertIndex, entity);
        log.debug("Added protocol params to in-memory cache at index {} (slot={})", insertIndex, entity.getSlot());
    }

    /**
     * Get the latest protocol params version
     *
     * @return the latest protocol params or empty if none exist
     */
    public Optional<ProtocolParamsEntity> getLatest() {
        if (inMemoryCache.isEmpty()) {
            return Optional.empty();
        }
        return Optional.of(inMemoryCache.get(inMemoryCache.size() - 1));
    }

    /**
     * Get all protocol params versions from memory (ordered by slot ascending)
     *
     * @return list of all protocol params
     */
    public List<ProtocolParamsEntity> getAll() {
        return List.copyOf(inMemoryCache);
    }

    /**
     * Get protocol params by transaction hash
     *
     * @param txHash the transaction hash
     * @return the protocol params or empty if not found
     */
    public Optional<ProtocolParamsEntity> getByTxHash(String txHash) {
        return inMemoryCache.stream()
                .filter(p -> p.getTxHash().equals(txHash))
                .findFirst();
    }

    /**
     * Get protocol params by slot
     *
     * @param slot the slot number
     * @return the protocol params or empty if not found
     */
    public Optional<ProtocolParamsEntity> getBySlot(Long slot) {
        return inMemoryCache.stream()
                .filter(p -> p.getSlot().equals(slot))
                .findFirst();
    }

    /**
     * Get protocol params valid at a given slot (closest version <= slot)
     *
     * @param slot the slot number
     * @return the protocol params valid at that slot or empty if none
     */
    public Optional<ProtocolParamsEntity> getValidAtSlot(Long slot) {
        for (int i = inMemoryCache.size() - 1; i >= 0; i--) {
            ProtocolParamsEntity entity = inMemoryCache.get(i);
            if (entity.getSlot() <= slot) {
                return Optional.of(entity);
            }
        }
        return Optional.empty();
    }

    /**
     * Check if protocol params exists by transaction hash
     *
     * @param txHash the transaction hash
     * @return true if exists, false otherwise
     */
    public boolean existsByTxHash(String txHash) {
        return inMemoryCache.stream()
                .anyMatch(p -> p.getTxHash().equals(txHash));
    }
}
