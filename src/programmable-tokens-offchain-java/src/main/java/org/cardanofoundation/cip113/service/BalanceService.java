package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.transaction.spec.Value;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.repository.BalanceLogRepository;
import org.cardanofoundation.cip113.util.BalanceValueHelper;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigInteger;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Service for tracking programmable token balances at the programmable logic address.
 *
 * <p>This service maintains a log of balance changes for addresses holding CIP-0113
 * programmable tokens. Unlike traditional token tracking, programmable tokens are
 * held at a shared script address (the programmable logic base), with ownership
 * determined by datum content.</p>
 *
 * <h2>Balance Tracking Model</h2>
 * <p>The service uses an append-only log model where each balance change creates
 * a new entry. This provides:</p>
 * <ul>
 *   <li>Complete balance history for auditing</li>
 *   <li>Point-in-time balance reconstruction</li>
 *   <li>Idempotent event processing (duplicate detection)</li>
 * </ul>
 *
 * <h2>Address Types</h2>
 * <p>Addresses tracked by this service include:</p>
 * <ul>
 *   <li><strong>Script addresses</strong>: Programmable logic base address</li>
 *   <li><strong>Payment key hashes</strong>: Owner credentials in datums</li>
 * </ul>
 *
 * <h2>Event Processing</h2>
 * <p>Balance entries are created by {@link BalanceEventListener} when processing
 * transaction outputs at the programmable logic address. The service ensures
 * idempotency through transaction hash uniqueness checks.</p>
 *
 * <h2>Value Representation</h2>
 * <p>Balances are stored as JSON and can be converted to Cardano-client-lib
 * {@link Value} objects for transaction building. See {@link BalanceValueHelper}
 * for conversion utilities.</p>
 *
 * @see BalanceLogEntity
 * @see BalanceEventListener
 * @see BalanceValueHelper
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class BalanceService {

    /** Repository for balance log persistence operations */
    private final BalanceLogRepository repository;

    /**
     * Append a new balance entry to the log.
     *
     * <p>This operation is idempotent - if an entry already exists for the
     * same address and transaction hash, it will be skipped without error.</p>
     *
     * @param entity the balance log entry to append
     * @return the saved entity (or existing entity if duplicate)
     */
    @Transactional
    public BalanceLogEntity append(BalanceLogEntity entity) {
        // Check if entry already exists (idempotency)
        if (repository.existsByAddressAndTxHash(entity.getAddress(), entity.getTxHash())) {
            log.debug("Balance entry already exists, skipping: address={}, tx={}",
                    entity.getAddress(), entity.getTxHash());
            return entity;
        }

        log.info("Appending balance entry: address={}, tx={}, slot={}",
                entity.getAddress(), entity.getTxHash(), entity.getSlot());

        return repository.save(entity);
    }

    /**
     * Get the latest (most recent) balance for an address.
     *
     * @param address the address to query
     * @return the latest balance entry, or empty if no history exists
     */
    public Optional<BalanceLogEntity> getLatestBalance(String address) {
        return repository.findLatestByAddress(address, PageRequest.of(0, 1))
                .stream()
                .findFirst();
    }

    /**
     * Get the current balance as a Cardano-client-lib Value object.
     *
     * <p>The Value object can be used directly for transaction building
     * and balance calculations.</p>
     *
     * @param address the address to query
     * @return Value object representing current balance (empty Value if no history)
     */
    public Value getCurrentBalanceAsValue(String address) {
        return getLatestBalance(address)
                .map(entity -> BalanceValueHelper.fromJson(entity.getBalance()))
                .orElse(BalanceValueHelper.empty());
    }

    /**
     * Get the current balance as a map of unit to amount.
     *
     * <p>Units are in the format "policyId.assetName" for native assets,
     * or "lovelace" for ADA.</p>
     *
     * @param address the address to query
     * @return map of unit to amount string (empty map if no history)
     */
    public Map<String, String> getCurrentBalanceByUnit(String address) {
        return getLatestBalance(address)
                .map(entity -> {
                    Value value = BalanceValueHelper.fromJson(entity.getBalance());
                    return BalanceValueHelper.toUnitMap(value);
                })
                .orElse(Map.of());
    }

    /**
     * Get balance history for an address.
     *
     * <p>Returns balance entries in reverse chronological order (newest first).</p>
     *
     * @param address the address to query
     * @param limit maximum number of entries to return
     * @return list of balance entries ordered by slot descending
     */
    public List<BalanceLogEntity> getBalanceHistory(String address, int limit) {
        Pageable pageable = PageRequest.of(0, limit);
        return repository.findHistoryByAddress(address, pageable);
    }

    /**
     * Get latest balances by payment script hash (one per address).
     *
     * @param paymentScriptHash the payment script hash
     * @return list of latest balance entries
     */
    public List<BalanceLogEntity> getLatestBalancesByPaymentScript(String paymentScriptHash) {
        return repository.findLatestByPaymentScriptHash(paymentScriptHash);
    }

    /**
     * Get latest balances by stake key hash
     *
     * @param stakeKeyHash the stake key hash
     * @return list of latest balance entries
     */
    public List<BalanceLogEntity> getLatestBalancesByStakeKey(String stakeKeyHash) {
        return repository.findLatestByStakeKeyHash(stakeKeyHash);
    }

    /**
     * Get latest balances by payment script hash and stake key hash
     *
     * @param paymentScriptHash the payment script hash
     * @param stakeKeyHash the stake key hash
     * @return list of latest balance entries
     */
    public List<BalanceLogEntity> getLatestBalancesByPaymentScriptAndStakeKey(
            String paymentScriptHash, String stakeKeyHash) {
        return repository.findLatestByPaymentScriptHashAndStakeKeyHash(paymentScriptHash, stakeKeyHash);
    }

    /**
     * Get all balance entries for a transaction
     *
     * @param txHash the transaction hash
     * @return list of balance entries
     */
    public List<BalanceLogEntity> getBalancesByTransaction(String txHash) {
        return repository.findByTxHash(txHash);
    }

    /**
     * Calculate balance difference between two entries using Value subtraction
     *
     * @param currentEntry the current balance entry
     * @param previousEntry the previous balance entry (or null if first)
     * @return Value representing the difference
     */
    public Value calculateBalanceDiff(BalanceLogEntity currentEntry, BalanceLogEntity previousEntry) {
        Value currentValue = BalanceValueHelper.fromJson(currentEntry.getBalance());

        if (previousEntry == null) {
            return currentValue;
        }

        Value previousValue = BalanceValueHelper.fromJson(previousEntry.getBalance());
        return currentValue.minus(previousValue);
    }

    /**
     * Get previous balance entry for a given entry
     *
     * @param entry the current entry
     * @return the previous entry or empty if this is the first
     */
    public Optional<BalanceLogEntity> getPreviousBalance(BalanceLogEntity entry) {
        List<BalanceLogEntity> history = repository.findHistoryByAddress(
                entry.getAddress(),
                PageRequest.of(0, 2)
        );

        // Find the entry before this one (by slot)
        for (BalanceLogEntity historyEntry : history) {
            if (!historyEntry.getId().equals(entry.getId()) &&
                historyEntry.getSlot() < entry.getSlot()) {
                return Optional.of(historyEntry);
            }
        }

        return Optional.empty();
    }

    /**
     * Extract a specific asset amount from a balance
     *
     * @param balance the balance JSON string
     * @param unit the asset unit (e.g., "lovelace" or "policyId+assetName")
     * @return the amount or zero if not found
     */
    public BigInteger getAssetAmount(String balance, String unit) {
        Value value = BalanceValueHelper.fromJson(balance);
        Map<String, String> unitMap = BalanceValueHelper.toUnitMap(value);
        String amountStr = unitMap.get(unit);
        return amountStr != null ? new BigInteger(amountStr) : BigInteger.ZERO;
    }

    /**
     * Check if an address has a balance entry
     *
     * @param address the address
     * @param txHash the transaction hash
     * @return true if exists
     */
    public boolean exists(String address, String txHash) {
        return repository.existsByAddressAndTxHash(address, txHash);
    }
}
