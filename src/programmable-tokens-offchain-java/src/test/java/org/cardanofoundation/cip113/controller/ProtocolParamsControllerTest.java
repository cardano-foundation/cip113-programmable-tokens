package org.cardanofoundation.cip113.controller;

import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.service.ProtocolParamsService;
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

import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Unit tests for {@link ProtocolParamsController}.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("ProtocolParamsController")
class ProtocolParamsControllerTest {

    private MockMvc mockMvc;

    @Mock
    private ProtocolParamsService protocolParamsService;

    private ProtocolParamsController controller;

    private static final String API_PREFIX = "/api/v1";

    @BeforeEach
    void setUp() {
        controller = new ProtocolParamsController(protocolParamsService);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .addPlaceholderValue("apiPrefix", API_PREFIX)
                .build();
    }

    @Nested
    @DisplayName("GET /protocol-params/latest")
    class GetLatest {

        @Test
        @DisplayName("should return latest protocol params when exists")
        void shouldReturnLatestWhenExists() throws Exception {
            // Given
            ProtocolParamsEntity entity = createProtocolParams(1L, "policyId1", "scriptHash1", 1000L);
            when(protocolParamsService.getLatest()).thenReturn(Optional.of(entity));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/latest")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.registryNodePolicyId").value("policyId1"));

            verify(protocolParamsService).getLatest();
        }

        @Test
        @DisplayName("should return 404 when no protocol params exist")
        void shouldReturn404WhenNotExists() throws Exception {
            // Given
            when(protocolParamsService.getLatest()).thenReturn(Optional.empty());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/latest")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("GET /protocol-params/all")
    class GetAll {

        @Test
        @DisplayName("should return all protocol params")
        void shouldReturnAllParams() throws Exception {
            // Given
            ProtocolParamsEntity entity1 = createProtocolParams(1L, "policyId1", "scriptHash1", 1000L);
            ProtocolParamsEntity entity2 = createProtocolParams(2L, "policyId2", "scriptHash2", 2000L);
            when(protocolParamsService.getAll()).thenReturn(List.of(entity1, entity2));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/all")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(2))
                    .andExpect(jsonPath("$[0].id").value(1))
                    .andExpect(jsonPath("$[1].id").value(2));

            verify(protocolParamsService).getAll();
        }

        @Test
        @DisplayName("should return empty list when no params exist")
        void shouldReturnEmptyList() throws Exception {
            // Given
            when(protocolParamsService.getAll()).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/all")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().string("[]"));
        }
    }

    @Nested
    @DisplayName("GET /protocol-params/by-tx/{txHash}")
    class GetByTxHash {

        @Test
        @DisplayName("should return protocol params when found by tx hash")
        void shouldReturnWhenFoundByTxHash() throws Exception {
            // Given
            String txHash = "abc123def456";
            ProtocolParamsEntity entity = createProtocolParams(1L, "policyId1", "scriptHash1", 1000L);
            entity.setTxHash(txHash);
            when(protocolParamsService.getByTxHash(txHash)).thenReturn(Optional.of(entity));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/by-tx/{txHash}", txHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.txHash").value(txHash));

            verify(protocolParamsService).getByTxHash(txHash);
        }

        @Test
        @DisplayName("should return 404 when tx hash not found")
        void shouldReturn404WhenTxHashNotFound() throws Exception {
            // Given
            String txHash = "nonexistent";
            when(protocolParamsService.getByTxHash(txHash)).thenReturn(Optional.empty());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/by-tx/{txHash}", txHash)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("GET /protocol-params/by-slot/{slot}")
    class GetBySlot {

        @Test
        @DisplayName("should return protocol params when found by slot")
        void shouldReturnWhenFoundBySlot() throws Exception {
            // Given
            Long slot = 1000L;
            ProtocolParamsEntity entity = createProtocolParams(1L, "policyId1", "scriptHash1", slot);
            when(protocolParamsService.getBySlot(slot)).thenReturn(Optional.of(entity));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/by-slot/{slot}", slot)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.slot").value(1000));

            verify(protocolParamsService).getBySlot(slot);
        }

        @Test
        @DisplayName("should return 404 when slot not found")
        void shouldReturn404WhenSlotNotFound() throws Exception {
            // Given
            Long slot = 9999L;
            when(protocolParamsService.getBySlot(slot)).thenReturn(Optional.empty());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/by-slot/{slot}", slot)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("GET /protocol-params/valid-at-slot/{slot}")
    class GetValidAtSlot {

        @Test
        @DisplayName("should return protocol params valid at slot")
        void shouldReturnValidAtSlot() throws Exception {
            // Given
            Long slot = 1500L;
            ProtocolParamsEntity entity = createProtocolParams(1L, "policyId1", "scriptHash1", 1000L);
            when(protocolParamsService.getValidAtSlot(slot)).thenReturn(Optional.of(entity));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/valid-at-slot/{slot}", slot)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1));

            verify(protocolParamsService).getValidAtSlot(slot);
        }

        @Test
        @DisplayName("should return 404 when no params valid at slot")
        void shouldReturn404WhenNoParamsValidAtSlot() throws Exception {
            // Given
            Long slot = 500L;
            when(protocolParamsService.getValidAtSlot(slot)).thenReturn(Optional.empty());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/protocol-params/valid-at-slot/{slot}", slot)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());
        }
    }

    /**
     * Create a ProtocolParamsEntity for testing.
     */
    private ProtocolParamsEntity createProtocolParams(Long id, String policyId, String scriptHash, Long slot) {
        ProtocolParamsEntity entity = new ProtocolParamsEntity();
        entity.setId(id);
        entity.setRegistryNodePolicyId(policyId);
        entity.setProgLogicScriptHash(scriptHash);
        entity.setSlot(slot);
        entity.setTxHash("txHash" + id);
        return entity;
    }
}
