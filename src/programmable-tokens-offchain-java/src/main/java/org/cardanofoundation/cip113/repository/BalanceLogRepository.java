package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/**
 * JPA Repository for CIP-113 Token Balance Entries.
 *
 * <p>Provides data access methods for querying and persisting token balance
 * records. Supports queries by address, payment script hash, stake key, and
 * historical balance lookups.</p>
 *
 * <h2>Query Methods</h2>
 * <ul>
 *   <li><b>findLatestByAddress:</b> Latest balance for a specific address</li>
 *   <li><b>findHistoryByAddress:</b> Balance history with pagination</li>
 *   <li><b>findLatestByPaymentScriptHash:</b> Balances by programmable logic script</li>
 *   <li><b>findAllHolders:</b> All unique addresses holding tokens</li>
 * </ul>
 *
 * @see BalanceLogEntity
 * @see org.cardanofoundation.cip113.service.BalanceService
 */
@Repository
public interface BalanceLogRepository extends JpaRepository<BalanceLogEntity, Long> {

    /**
     * Find the latest balance entry for an address
     */
    @Query("SELECT b FROM BalanceLogEntity b WHERE b.address = :address ORDER BY b.slot DESC, b.id DESC")
    List<BalanceLogEntity> findLatestByAddress(@Param("address") String address, Pageable pageable);

    /**
     * Find balance history for an address
     */
    @Query("SELECT b FROM BalanceLogEntity b WHERE b.address = :address ORDER BY b.slot DESC")
    List<BalanceLogEntity> findHistoryByAddress(@Param("address") String address, Pageable pageable);

    /**
     * Find latest balances by payment script hash (one per address)
     */
    @Query("SELECT b FROM BalanceLogEntity b WHERE b.paymentScriptHash = :paymentScriptHash " +
           "AND b.id IN (" +
           "  SELECT MAX(b2.id) FROM BalanceLogEntity b2 " +
           "  WHERE b2.paymentScriptHash = :paymentScriptHash " +
           "  GROUP BY b2.address" +
           ") ORDER BY b.slot DESC")
    List<BalanceLogEntity> findLatestByPaymentScriptHash(@Param("paymentScriptHash") String paymentScriptHash);

    /**
     * Find latest balances by stake key hash (one per address)
     */
    @Query("SELECT b FROM BalanceLogEntity b WHERE b.stakeKeyHash = :stakeKeyHash " +
           "AND b.id IN (" +
           "  SELECT MAX(b2.id) FROM BalanceLogEntity b2 " +
           "  WHERE b2.stakeKeyHash = :stakeKeyHash " +
           "  GROUP BY b2.address" +
           ") ORDER BY b.slot DESC")
    List<BalanceLogEntity> findLatestByStakeKeyHash(@Param("stakeKeyHash") String stakeKeyHash);

    /**
     * Find latest balances by payment script hash and stake key hash
     */
    @Query("SELECT b FROM BalanceLogEntity b WHERE b.paymentScriptHash = :paymentScriptHash " +
           "AND b.stakeKeyHash = :stakeKeyHash " +
           "AND b.id IN (" +
           "  SELECT MAX(b2.id) FROM BalanceLogEntity b2 " +
           "  WHERE b2.paymentScriptHash = :paymentScriptHash " +
           "  AND b2.stakeKeyHash = :stakeKeyHash " +
           "  GROUP BY b2.address" +
           ") ORDER BY b.slot DESC")
    List<BalanceLogEntity> findLatestByPaymentScriptHashAndStakeKeyHash(
            @Param("paymentScriptHash") String paymentScriptHash,
            @Param("stakeKeyHash") String stakeKeyHash
    );

    /**
     * Find balance entries by transaction hash
     */
    @Query("SELECT b FROM BalanceLogEntity b WHERE b.txHash = :txHash ORDER BY b.address")
    List<BalanceLogEntity> findByTxHash(@Param("txHash") String txHash);

    /**
     * Check if balance entry exists for this address and transaction
     */
    boolean existsByAddressAndTxHash(String address, String txHash);
}
