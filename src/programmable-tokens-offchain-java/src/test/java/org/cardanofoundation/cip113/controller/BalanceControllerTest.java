package org.cardanofoundation.cip113.controller;

import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.service.BalanceService;
import org.cardanofoundation.cip113.service.RegistryService;
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

import java.math.BigInteger;
import java.util.*;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Unit tests for {@link BalanceController}.
 * Uses standalone MockMvc setup to avoid Spring context loading.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("BalanceController")
class BalanceControllerTest {

    private MockMvc mockMvc;

    @Mock
    private BalanceService balanceService;

    @Mock
    private RegistryService registryService;

    private BalanceController controller;

    private static final String API_PREFIX = "/api/v1";

    @BeforeEach
    void setUp() {
        controller = new BalanceController(balanceService, registryService);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .addPlaceholderValue("apiPrefix", API_PREFIX)
                .build();
    }

    @Nested
    @DisplayName("GET /balances/current/{address}")
    class GetCurrentBalance {

        @Test
        @DisplayName("should return balance map for address")
        void shouldReturnBalanceMap() throws Exception {
            // Given
            String address = "addr_test1qz...";
            Map<String, String> balanceMap = Map.of(
                    "lovelace", "10000000",
                    "abc123+tokenA", "100"
            );
            when(balanceService.getCurrentBalanceByUnit(address)).thenReturn(balanceMap);

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current/{address}", address)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                    .andExpect(jsonPath("$.lovelace").value("10000000"))
                    .andExpect(jsonPath("$.['abc123+tokenA']").value("100"));

            verify(balanceService).getCurrentBalanceByUnit(address);
        }

        @Test
        @DisplayName("should return empty map for address with no balance")
        void shouldReturnEmptyMap() throws Exception {
            // Given
            String address = "addr_test1qz...";
            when(balanceService.getCurrentBalanceByUnit(address)).thenReturn(Collections.emptyMap());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current/{address}", address)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().string("{}"));
        }
    }

    @Nested
    @DisplayName("GET /balances/current/{address}/{unit}")
    class GetCurrentBalanceForAsset {

        @Test
        @DisplayName("should return balance for specific asset")
        void shouldReturnBalanceForAsset() throws Exception {
            // Given
            String address = "addr_test1qz...";
            String unit = "lovelace";
            BalanceLogEntity entity = createBalanceEntity(address, "txHash123", 12345L);

            when(balanceService.getLatestBalance(address)).thenReturn(Optional.of(entity));
            when(balanceService.getAssetAmount(anyString(), eq(unit))).thenReturn(BigInteger.valueOf(5000000));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current/{address}/{unit}", address, unit)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.address").value(address))
                    .andExpect(jsonPath("$.unit").value(unit))
                    .andExpect(jsonPath("$.amount").value("5000000"))
                    .andExpect(jsonPath("$.txHash").value("txHash123"))
                    .andExpect(jsonPath("$.slot").value("12345"));
        }

        @Test
        @DisplayName("should return 404 when balance not found")
        void shouldReturn404WhenNotFound() throws Exception {
            // Given
            String address = "addr_test1qz...";
            String unit = "lovelace";
            when(balanceService.getLatestBalance(address)).thenReturn(Optional.empty());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current/{address}/{unit}", address, unit)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("GET /balances/current-by-payment/{scriptHash}")
    class GetCurrentBalanceByPaymentScript {

        @Test
        @DisplayName("should return balances for payment script hash")
        void shouldReturnBalancesForScriptHash() throws Exception {
            // Given
            String scriptHash = "abc123def456";
            List<BalanceLogEntity> balances = List.of(
                    createBalanceEntity("addr1", "tx1", 100L),
                    createBalanceEntity("addr2", "tx2", 200L)
            );
            when(balanceService.getLatestBalancesByPaymentScript(scriptHash)).thenReturn(balances);

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current-by-payment/{scriptHash}", scriptHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(2))
                    .andExpect(jsonPath("$[0].address").value("addr1"))
                    .andExpect(jsonPath("$[1].address").value("addr2"));

            verify(balanceService).getLatestBalancesByPaymentScript(scriptHash);
        }

        @Test
        @DisplayName("should return empty list when no balances found")
        void shouldReturnEmptyList() throws Exception {
            // Given
            String scriptHash = "abc123def456";
            when(balanceService.getLatestBalancesByPaymentScript(scriptHash)).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current-by-payment/{scriptHash}", scriptHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().string("[]"));
        }
    }

    @Nested
    @DisplayName("GET /balances/current-by-stake/{stakeHash}")
    class GetCurrentBalanceByStakeKey {

        @Test
        @DisplayName("should return balances for stake key hash")
        void shouldReturnBalancesForStakeHash() throws Exception {
            // Given
            String stakeHash = "stake123";
            List<BalanceLogEntity> balances = List.of(
                    createBalanceEntity("addr1", "tx1", 100L)
            );
            when(balanceService.getLatestBalancesByStakeKey(stakeHash)).thenReturn(balances);

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current-by-stake/{stakeHash}", stakeHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(1))
                    .andExpect(jsonPath("$[0].address").value("addr1"));

            verify(balanceService).getLatestBalancesByStakeKey(stakeHash);
        }
    }

    @Nested
    @DisplayName("GET /balances/current-by-payment-and-stake/{scriptHash}/{stakeHash}")
    class GetCurrentBalanceByPaymentAndStake {

        @Test
        @DisplayName("should return balance for payment script and stake key")
        void shouldReturnBalance() throws Exception {
            // Given
            String scriptHash = "script123";
            String stakeHash = "stake123";
            List<BalanceLogEntity> balances = List.of(
                    createBalanceEntity("addr1", "tx1", 100L)
            );
            when(balanceService.getLatestBalancesByPaymentScriptAndStakeKey(scriptHash, stakeHash))
                    .thenReturn(balances);

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current-by-payment-and-stake/{scriptHash}/{stakeHash}",
                            scriptHash, stakeHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.address").value("addr1"));

            verify(balanceService).getLatestBalancesByPaymentScriptAndStakeKey(scriptHash, stakeHash);
        }

        @Test
        @DisplayName("should return 404 when not found")
        void shouldReturn404WhenNotFound() throws Exception {
            // Given
            String scriptHash = "script123";
            String stakeHash = "stake123";
            when(balanceService.getLatestBalancesByPaymentScriptAndStakeKey(scriptHash, stakeHash))
                    .thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/balances/current-by-payment-and-stake/{scriptHash}/{stakeHash}",
                            scriptHash, stakeHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());
        }
    }

    /**
     * Create a BalanceLogEntity for testing.
     */
    private BalanceLogEntity createBalanceEntity(String address, String txHash, Long slot) {
        BalanceLogEntity entity = new BalanceLogEntity();
        entity.setAddress(address);
        entity.setTxHash(txHash);
        entity.setSlot(slot);
        entity.setBalance("{}");
        return entity;
    }
}
