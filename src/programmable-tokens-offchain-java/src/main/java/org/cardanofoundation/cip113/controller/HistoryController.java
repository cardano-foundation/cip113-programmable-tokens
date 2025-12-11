package org.cardanofoundation.cip113.controller;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.service.BalanceService;
import org.cardanofoundation.cip113.util.BalanceValueHelper;
import org.cardanofoundation.conversions.CardanoConverters;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("${apiPrefix}/history")
@RequiredArgsConstructor
@Slf4j
@Tag(name = "History", description = "Transaction history")
public class HistoryController {

    private final BalanceService balanceService;
    private final CardanoConverters cardanoConverters;

    /**
     * Get transaction history by stake key hash
     * Returns all transactions across all addresses with this stake key,
     * sorted by slot DESC with balance diffs computed
     *
     * @param stakeKeyHash the stake key hash (user hash)
     * @param limit maximum number of entries (default 10)
     * @return list of transaction history entries
     */
    @GetMapping("/by-stake/{stakeKeyHash}")
    @Operation(
            summary = "Get transaction history by stake key",
            description = "Returns transaction history for all addresses associated with a stake key. " +
                    "Includes balance differences for each transaction."
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "History retrieved successfully"),
            @ApiResponse(responseCode = "404", description = "Stake key not found")
    })
    public ResponseEntity<List<TransactionHistoryResponse>> getHistoryByStakeKey(
            @Parameter(description = "Stake key hash") @PathVariable String stakeKeyHash,
            @Parameter(description = "Maximum entries to return") @RequestParam(defaultValue = "10") int limit) {
        log.debug("GET /history/by-stake/{} - fetching history, limit={}", stakeKeyHash, limit);

        // Get all latest balances for this stake key to find all addresses
        List<BalanceLogEntity> latestBalances = balanceService.getLatestBalancesByStakeKey(stakeKeyHash);

        // For each address, get their history and compute diffs
        List<TransactionHistoryResponse> allHistory = new ArrayList<>();

        for (BalanceLogEntity latestBalance : latestBalances) {
            String address = latestBalance.getAddress();

            // Get full history for this address (we'll limit globally later)
            List<BalanceLogEntity> addressHistory = balanceService.getBalanceHistory(address, Integer.MAX_VALUE);

            // Process each entry and compute diff
            for (BalanceLogEntity entry : addressHistory) {
                // Get previous balance to calculate diff
                Optional<BalanceLogEntity> previousOpt = balanceService.getPreviousBalance(entry);

                // Calculate signed diff
                String previousBalanceJson = previousOpt.map(BalanceLogEntity::getBalance).orElse(null);
                Map<String, String> diffMap = BalanceValueHelper.calculateSignedDiff(
                        entry.getBalance(),
                        previousBalanceJson
                );

                // Convert slot to timestamp
                LocalDateTime timestamp = cardanoConverters.slot().slotToTime(entry.getSlot());

                TransactionHistoryResponse response = TransactionHistoryResponse.builder()
                        .txHash(entry.getTxHash())
                        .address(entry.getAddress())
                        .slot(entry.getSlot())
                        .timestamp(timestamp)
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
     * Response DTO for transaction history
     */
    @lombok.Data
    @lombok.Builder
    public static class TransactionHistoryResponse {
        private String txHash;
        private String address;
        private Long slot;
        private LocalDateTime timestamp;
        private Map<String, String> balanceDiff;  // unit -> signed amount
    }
}
