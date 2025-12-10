package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.model.TransactionType;
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

import static org.cardanofoundation.cip113.util.BalanceValueHelper.fromUnitMap2;

@Service
@Slf4j
@RequiredArgsConstructor
public class BalanceService {

    private final BalanceLogRepository repository;
    private final ObjectMapper objectMapper;

    /**
     * Append a new balance entry to the log
     *
     * @param entity the balance log entry to append
     * @return the saved entity
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
     * Append a new balance entry to the log with transaction type and balance diff
     *
     * @param address         the address
     * @param txHash          the transaction hash
     * @param slot            the slot number
     * @param blockHeight     the block height
     * @param balance         the complete balance map
     * @param transactionType the type of transaction (MINT, BURN, TRANSFER, REGISTER)
     * @param balanceDiff     the signed balance differences (e.g., "+1000", "-50")
     * @return the saved entity
     */
    @Transactional
    public BalanceLogEntity append(
            String address,
            String txHash,
            Long slot,
            Long blockHeight,
            Map<String, BigInteger> balance,
            TransactionType transactionType,
            Map<String, String> balanceDiff) {

        // Check if entry already exists (idempotency)
        if (repository.existsByAddressAndTxHash(address, txHash)) {
            log.debug("Balance entry already exists, skipping: address={}, tx={}",
                    address, txHash);
            // Fetch and return existing entity
            return repository.findByTxHash(txHash).stream()
                    .filter(e -> e.getAddress().equals(address))
                    .findFirst()
                    .orElseThrow();
        }

        // Serialize balance and diff to JSON
        String balanceJson = BalanceValueHelper.toJson(fromUnitMap2(balance));
        String balanceDiffJson = serializeBalanceDiff(balanceDiff);

        var add = new Address(address);
        var paymentHash = HexUtil.encodeHexString(add.getPaymentCredentialHash().get());
        var stakeHash = HexUtil.encodeHexString(add.getDelegationCredentialHash().get());

        // Create entity
        BalanceLogEntity entity = BalanceLogEntity.builder()
                .address(address)
                .paymentScriptHash(paymentHash)
                .stakeKeyHash(stakeHash)
                .txHash(txHash)
                .slot(slot)
                .blockHeight(blockHeight)
                .balance(balanceJson)
                .transactionType(transactionType)
                .balanceDiff(balanceDiffJson)
                .build();

        log.info("Appending balance entry: address={}, tx={}, slot={}, type={}",
                address, txHash, slot, transactionType);

        return repository.save(entity);
    }

    /**
     * Serialize balance diff map to JSON string
     *
     * @param balanceDiff map of unit to signed amount string
     * @return JSON string representation
     */
    private String serializeBalanceDiff(Map<String, String> balanceDiff) {
        if (balanceDiff == null || balanceDiff.isEmpty()) {
            return null;
        }
        try {
            return objectMapper.writeValueAsString(balanceDiff);
        } catch (JsonProcessingException e) {
            log.error("Failed to serialize balance diff: {}", balanceDiff, e);
            throw new RuntimeException("Failed to serialize balance diff", e);
        }
    }


    /**
     * Get the latest balance for an address
     *
     * @param address the address
     * @return the latest balance entry or empty if no history
     */
    public Optional<BalanceLogEntity> getLatestBalance(String address) {
        return repository.findLatestByAddress(address, PageRequest.of(0, 1))
                .stream()
                .findFirst();
    }

    /**
     * Get the current balance as a Value object
     *
     * @param address the address
     * @return Value object representing current balance
     */
    public Value getCurrentBalanceAsValue(String address) {
        return getLatestBalance(address)
                .map(entity -> BalanceValueHelper.fromJson(entity.getBalance()))
                .orElse(BalanceValueHelper.empty());
    }

    /**
     * Get the current balance as a unit map
     *
     * @param address the address
     * @return map of unit to amount (as string)
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
     * Get balance history for an address
     *
     * @param address the address
     * @param limit   maximum number of entries to return
     * @return list of balance entries (ordered by slot DESC)
     */
    public List<BalanceLogEntity> getBalanceHistory(String address, int limit) {
        Pageable pageable = PageRequest.of(0, limit);
        return repository.findHistoryByAddress(address, pageable);
    }

    /**
     * Get latest balances by payment script hash (one per address)
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
     * @param stakeKeyHash      the stake key hash
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
     * @param currentEntry  the current balance entry
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
     * @param unit    the asset unit (e.g., "lovelace" or "policyId+assetName")
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
     * @param txHash  the transaction hash
     * @return true if exists
     */
    public boolean exists(String address, String txHash) {
        return repository.existsByAddressAndTxHash(address, txHash);
    }
}
