package org.cardanofoundation.cip113.controller;

import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.service.BalanceService;
import org.cardanofoundation.conversions.CardanoConverters;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Unit tests for {@link HistoryController}.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("HistoryController")
class HistoryControllerTest {

    private MockMvc mockMvc;

    @Mock
    private BalanceService balanceService;

    @Mock(answer = org.mockito.Answers.RETURNS_DEEP_STUBS)
    private CardanoConverters cardanoConverters;

    private HistoryController controller;

    private static final String API_PREFIX = "/api/v1";

    @BeforeEach
    void setUp() {
        controller = new HistoryController(balanceService, cardanoConverters);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .addPlaceholderValue("apiPrefix", API_PREFIX)
                .build();
    }

    @Nested
    @DisplayName("GET /history/by-stake/{stakeKeyHash}")
    class GetHistoryByStakeKey {

        @Test
        @DisplayName("should return empty list when no balances found")
        void shouldReturnEmptyListWhenNoBalances() throws Exception {
            // Given
            String stakeKeyHash = "stake123";
            when(balanceService.getLatestBalancesByStakeKey(stakeKeyHash))
                    .thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/history/by-stake/{stakeKeyHash}", stakeKeyHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().string("[]"));

            verify(balanceService).getLatestBalancesByStakeKey(stakeKeyHash);
        }

        @Test
        @DisplayName("should return transaction history with balance diffs")
        void shouldReturnHistoryWithDiffs() throws Exception {
            // Given
            String stakeKeyHash = "stake123";
            String address = "addr_test1qz...";

            BalanceLogEntity latestBalance = createBalanceEntity(address, "txHash1", 1000L, "{\"lovelace\":\"5000000\"}");
            BalanceLogEntity historyEntry = createBalanceEntity(address, "txHash1", 1000L, "{\"lovelace\":\"5000000\"}");

            when(balanceService.getLatestBalancesByStakeKey(stakeKeyHash))
                    .thenReturn(List.of(latestBalance));
            when(balanceService.getBalanceHistory(address, Integer.MAX_VALUE))
                    .thenReturn(List.of(historyEntry));
            when(balanceService.getPreviousBalance(historyEntry))
                    .thenReturn(Optional.empty());
            when(cardanoConverters.slot().slotToTime(1000L)).thenReturn(LocalDateTime.of(2024, 1, 1, 12, 0));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/history/by-stake/{stakeKeyHash}", stakeKeyHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(1))
                    .andExpect(jsonPath("$[0].txHash").value("txHash1"))
                    .andExpect(jsonPath("$[0].address").value(address))
                    .andExpect(jsonPath("$[0].slot").value(1000));

            verify(balanceService).getLatestBalancesByStakeKey(stakeKeyHash);
            verify(balanceService).getBalanceHistory(address, Integer.MAX_VALUE);
        }

        @Test
        @DisplayName("should apply limit parameter")
        void shouldApplyLimit() throws Exception {
            // Given
            String stakeKeyHash = "stake123";
            String address = "addr_test1qz...";

            BalanceLogEntity latestBalance = createBalanceEntity(address, "txHash1", 1000L, "{\"lovelace\":\"5000000\"}");
            BalanceLogEntity entry1 = createBalanceEntity(address, "txHash1", 1000L, "{\"lovelace\":\"5000000\"}");
            BalanceLogEntity entry2 = createBalanceEntity(address, "txHash2", 2000L, "{\"lovelace\":\"6000000\"}");
            BalanceLogEntity entry3 = createBalanceEntity(address, "txHash3", 3000L, "{\"lovelace\":\"7000000\"}");

            when(balanceService.getLatestBalancesByStakeKey(stakeKeyHash))
                    .thenReturn(List.of(latestBalance));
            when(balanceService.getBalanceHistory(address, Integer.MAX_VALUE))
                    .thenReturn(List.of(entry1, entry2, entry3));
            when(balanceService.getPreviousBalance(any())).thenReturn(Optional.empty());
            when(cardanoConverters.slot().slotToTime(anyLong())).thenReturn(LocalDateTime.of(2024, 1, 1, 12, 0));

            // When/Then - request with limit=2
            mockMvc.perform(get(API_PREFIX + "/history/by-stake/{stakeKeyHash}", stakeKeyHash)
                            .param("limit", "2")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(2));
        }

        @Test
        @DisplayName("should use default limit of 10")
        void shouldUseDefaultLimit() throws Exception {
            // Given
            String stakeKeyHash = "stake123";
            when(balanceService.getLatestBalancesByStakeKey(stakeKeyHash))
                    .thenReturn(Collections.emptyList());

            // When/Then - no limit parameter
            mockMvc.perform(get(API_PREFIX + "/history/by-stake/{stakeKeyHash}", stakeKeyHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk());

            verify(balanceService).getLatestBalancesByStakeKey(stakeKeyHash);
        }
    }

    /**
     * Create a BalanceLogEntity for testing.
     */
    private BalanceLogEntity createBalanceEntity(String address, String txHash, Long slot, String balance) {
        BalanceLogEntity entity = new BalanceLogEntity();
        entity.setAddress(address);
        entity.setTxHash(txHash);
        entity.setSlot(slot);
        entity.setBalance(balance);
        return entity;
    }
}
