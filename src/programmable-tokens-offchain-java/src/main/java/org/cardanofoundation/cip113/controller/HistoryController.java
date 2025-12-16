package org.cardanofoundation.cip113.controller;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.model.TransactionType;
import org.cardanofoundation.cip113.service.BalanceService;
import org.cardanofoundation.cip113.service.ProtocolParamsService;
import org.cardanofoundation.cip113.util.BalanceValueHelper;
import org.cardanofoundation.conversions.CardanoConverters;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("${apiPrefix}/history")
@RequiredArgsConstructor
@Slf4j
public class HistoryController {

    private final BalanceService balanceService;
    private final ProtocolParamsService protocolParamsService;
    private final CardanoConverters cardanoConverters;
    private final ObjectMapper objectMapper;

    /**
     * Get transaction history by stake key hash with optional protocol filtering
     * Returns all transactions across all addresses with this stake key,
     * sorted by slot DESC with balance diffs from the database
     *
     * @param stakeKeyHash the stake key hash (user hash)
     * @param protocolTxHash optional protocol transaction hash to filter by protocol version
     * @param limit maximum number of entries (default 10)
     * @return list of transaction history entries
     */
    @GetMapping("/by-stake/{stakeKeyHash}")
    public ResponseEntity<List<TransactionHistoryResponse>> getHistoryByStakeKey(
            @PathVariable String stakeKeyHash,
            @RequestParam(required = false) String protocolTxHash,
            @RequestParam(defaultValue = "10") int limit) {
        log.debug("GET /history/by-stake/{} - protocolTxHash={}, limit={}", stakeKeyHash, protocolTxHash, limit);

        // Resolve payment script hash from protocol tx hash if provided
        String paymentScriptHash = null;
        if (protocolTxHash != null && !protocolTxHash.isEmpty()) {
            Optional<ProtocolParamsEntity> protocolOpt = protocolParamsService.getByTxHash(protocolTxHash);
            if (protocolOpt.isPresent()) {
                paymentScriptHash = protocolOpt.get().getProgLogicScriptHash();
                log.debug("Resolved paymentScriptHash={} from protocolTxHash={}", paymentScriptHash, protocolTxHash);
            } else {
                log.warn("Protocol not found for txHash={}", protocolTxHash);
                return ResponseEntity.ok(Collections.emptyList());
            }
        }

        // Get all latest balances for this stake key (optionally filtered by protocol)
        List<BalanceLogEntity> latestBalances;
        if (paymentScriptHash != null) {
            latestBalances = balanceService.getLatestBalancesByPaymentScriptAndStakeKey(paymentScriptHash, stakeKeyHash);
        } else {
            latestBalances = balanceService.getLatestBalancesByStakeKey(stakeKeyHash);
        }

        // For each address, get their history
        List<TransactionHistoryResponse> allHistory = new ArrayList<>();

        for (BalanceLogEntity latestBalance : latestBalances) {
            String address = latestBalance.getAddress();

            // Get full history for this address (we'll limit globally later)
            List<BalanceLogEntity> addressHistory = balanceService.getBalanceHistory(address, Integer.MAX_VALUE);

            // Process each entry - use stored balance diff and transaction type
            for (BalanceLogEntity entry : addressHistory) {
                // Deserialize stored balance diff (or calculate if not present for backward compatibility)
                Map<String, String> diffMap;
                if (entry.getBalanceDiff() != null && !entry.getBalanceDiff().isEmpty()) {
                    diffMap = deserializeBalanceDiff(entry.getBalanceDiff());
                } else {
                    // Fallback to calculation for old entries
                    Optional<BalanceLogEntity> previousOpt = balanceService.getPreviousBalance(entry);
                    String previousBalanceJson = previousOpt.map(BalanceLogEntity::getBalance).orElse(null);
                    diffMap = BalanceValueHelper.calculateSignedDiff(entry.getBalance(), previousBalanceJson);
                }

                // Filter out zero amounts from balance diff
                diffMap = filterZeroAmounts(diffMap);

                // Convert slot to timestamp
                var timestamp = cardanoConverters.slot().slotToTime(entry.getSlot()).toInstant(ZoneOffset.UTC).getEpochSecond();

                TransactionHistoryResponse response = TransactionHistoryResponse.builder()
                        .txHash(entry.getTxHash())
                        .address(entry.getAddress())
                        .slot(entry.getSlot())
                        .timestamp(timestamp)
                        .transactionType(entry.getTransactionType())
                        .balanceDiff(diffMap)
                        .build();

                allHistory.add(response);
            }
        }

        // Sort all transactions by slot DESC (most recent first) and apply limit
        List<TransactionHistoryResponse> sortedHistory = allHistory.stream()
                .sorted(Comparator.comparing(TransactionHistoryResponse::getSlot).reversed())
                .limit(limit)
                .collect(Collectors.toList());

        return ResponseEntity.ok(sortedHistory);
    }

    /**
     * Deserialize balance diff JSON string to map
     *
     * @param balanceDiffJson JSON string representation
     * @return map of unit to signed amount string
     */
    private Map<String, String> deserializeBalanceDiff(String balanceDiffJson) {
        try {
            return objectMapper.readValue(balanceDiffJson, new TypeReference<Map<String, String>>() {});
        } catch (JsonProcessingException e) {
            log.error("Failed to deserialize balance diff: {}", balanceDiffJson, e);
            return new HashMap<>();
        }
    }

    /**
     * Filter out zero amounts from balance diff map
     * Removes entries where the amount is "0", "+0", "-0", etc.
     *
     * @param balanceDiff map of unit to signed amount string
     * @return filtered map with only non-zero amounts
     */
    private Map<String, String> filterZeroAmounts(Map<String, String> balanceDiff) {
        if (balanceDiff == null || balanceDiff.isEmpty()) {
            return balanceDiff;
        }

        return balanceDiff.entrySet().stream()
                .filter(entry -> {
                    String amount = entry.getValue();
                    if (amount == null || amount.isEmpty()) {
                        return false;
                    }

                    // Remove + or - prefix for comparison
                    String numericPart = amount.startsWith("+") || amount.startsWith("-")
                            ? amount.substring(1)
                            : amount;

                    try {
                        return !numericPart.equals("0") && new java.math.BigInteger(numericPart).compareTo(java.math.BigInteger.ZERO) != 0;
                    } catch (NumberFormatException e) {
                        log.warn("Invalid amount format in balance diff: {}", amount);
                        return false;
                    }
                })
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    /**
     * Response DTO for transaction history
     */
    @lombok.Data
    @lombok.Builder
    public static class TransactionHistoryResponse {
        private String txHash;
        private String address;
        private Long slot;
        private Long timestamp;
        private TransactionType transactionType;  // MINT, BURN, TRANSFER, REGISTER, or null
        private Map<String, String> balanceDiff;  // unit -> signed amount (e.g., "+1000", "-50")
    }
}
