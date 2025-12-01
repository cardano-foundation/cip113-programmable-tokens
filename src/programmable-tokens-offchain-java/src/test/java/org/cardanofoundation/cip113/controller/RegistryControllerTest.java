package org.cardanofoundation.cip113.controller;

import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.cardanofoundation.cip113.service.ProtocolParamsService;
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

import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Unit tests for {@link RegistryController}.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("RegistryController")
class RegistryControllerTest {

    private MockMvc mockMvc;

    @Mock
    private RegistryService registryService;

    @Mock
    private ProtocolParamsService protocolParamsService;

    private RegistryController controller;

    private static final String API_PREFIX = "/api/v1";

    @BeforeEach
    void setUp() {
        controller = new RegistryController(registryService, protocolParamsService);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .addPlaceholderValue("apiPrefix", API_PREFIX)
                .build();
    }

    @Nested
    @DisplayName("GET /registry/tokens")
    class GetAllTokens {

        @Test
        @DisplayName("should return empty list when no tokens registered")
        void shouldReturnEmptyList() throws Exception {
            // Given
            when(registryService.getAllTokens()).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/tokens")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().string("[]"));

            verify(registryService).getAllTokens();
        }

        @Test
        @DisplayName("should filter by protocolParamsId when provided")
        void shouldFilterByProtocolParamsId() throws Exception {
            // Given
            Long protocolParamsId = 1L;
            when(registryService.getAllTokens(protocolParamsId)).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/tokens")
                            .param("protocolParamsId", "1")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk());

            verify(registryService).getAllTokens(protocolParamsId);
            verify(registryService, never()).getAllTokens();
        }

        @Test
        @DisplayName("should return tokens grouped by protocol params")
        void shouldReturnTokensGroupedByProtocol() throws Exception {
            // Given
            ProtocolParamsEntity protocolParams = createProtocolParams(1L, "policyId1", "scriptHash1");
            RegistryNodeEntity token = createRegistryNode("tokenKey1", "tokenNext1", protocolParams);

            when(registryService.getAllTokens()).thenReturn(List.of(token));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/tokens")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(1))
                    .andExpect(jsonPath("$[0].protocolParams.registryNodePolicyId").value("policyId1"));
        }
    }

    @Nested
    @DisplayName("GET /registry/token/{policyId}")
    class GetTokenByPolicyId {

        @Test
        @DisplayName("should return token when found")
        void shouldReturnTokenWhenFound() throws Exception {
            // Given
            String policyId = "abc123";
            ProtocolParamsEntity protocolParams = createProtocolParams(1L, "policyId1", "scriptHash1");
            RegistryNodeEntity token = createRegistryNode(policyId, "nextKey", protocolParams);

            when(registryService.getByKey(policyId)).thenReturn(Optional.of(token));

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/token/{policyId}", policyId)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.key").value(policyId));

            verify(registryService).getByKey(policyId);
        }

        @Test
        @DisplayName("should return 404 when token not found")
        void shouldReturn404WhenNotFound() throws Exception {
            // Given
            String policyId = "nonexistent";
            when(registryService.getByKey(policyId)).thenReturn(Optional.empty());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/token/{policyId}", policyId)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());

            verify(registryService).getByKey(policyId);
        }
    }

    @Nested
    @DisplayName("GET /registry/is-registered/{policyId}")
    class IsTokenRegistered {

        @Test
        @DisplayName("should return true when token is registered")
        void shouldReturnTrueWhenRegistered() throws Exception {
            // Given
            String policyId = "abc123";
            when(registryService.isTokenRegistered(policyId)).thenReturn(true);

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/is-registered/{policyId}", policyId)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.registered").value(true));

            verify(registryService).isTokenRegistered(policyId);
        }

        @Test
        @DisplayName("should return false when token is not registered")
        void shouldReturnFalseWhenNotRegistered() throws Exception {
            // Given
            String policyId = "abc123";
            when(registryService.isTokenRegistered(policyId)).thenReturn(false);

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/is-registered/{policyId}", policyId)
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.registered").value(false));
        }
    }

    @Nested
    @DisplayName("GET /registry/protocols")
    class GetProtocolsWithStats {

        @Test
        @DisplayName("should return protocol params with token counts")
        void shouldReturnProtocolsWithStats() throws Exception {
            // Given
            ProtocolParamsEntity pp = createProtocolParams(1L, "policyId1", "scriptHash1");
            when(protocolParamsService.getAll()).thenReturn(List.of(pp));
            when(registryService.countTokens(1L)).thenReturn(5L);

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/protocols")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(1))
                    .andExpect(jsonPath("$[0].protocolParamsId").value(1))
                    .andExpect(jsonPath("$[0].registryNodePolicyId").value("policyId1"))
                    .andExpect(jsonPath("$[0].tokenCount").value(5));

            verify(protocolParamsService).getAll();
            verify(registryService).countTokens(1L);
        }

        @Test
        @DisplayName("should return empty list when no protocols")
        void shouldReturnEmptyListWhenNoProtocols() throws Exception {
            // Given
            when(protocolParamsService.getAll()).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/protocols")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().string("[]"));
        }
    }

    @Nested
    @DisplayName("GET /registry/tokens/sorted")
    class GetTokensSorted {

        @Test
        @DisplayName("should return sorted tokens for protocol")
        void shouldReturnSortedTokens() throws Exception {
            // Given
            Long protocolParamsId = 1L;
            when(registryService.getTokensSorted(protocolParamsId)).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/tokens/sorted")
                            .param("protocolParamsId", "1")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk());

            verify(registryService).getTokensSorted(protocolParamsId);
        }
    }

    @Nested
    @DisplayName("GET /registry/nodes/all")
    class GetAllNodes {

        @Test
        @DisplayName("should return all nodes including sentinel")
        void shouldReturnAllNodes() throws Exception {
            // Given
            Long protocolParamsId = 1L;
            when(registryService.getAllNodes(protocolParamsId)).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get(API_PREFIX + "/registry/nodes/all")
                            .param("protocolParamsId", "1")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk());

            verify(registryService).getAllNodes(protocolParamsId);
        }
    }

    /**
     * Create a ProtocolParamsEntity for testing.
     */
    private ProtocolParamsEntity createProtocolParams(Long id, String policyId, String scriptHash) {
        ProtocolParamsEntity entity = new ProtocolParamsEntity();
        entity.setId(id);
        entity.setRegistryNodePolicyId(policyId);
        entity.setProgLogicScriptHash(scriptHash);
        entity.setSlot(12345L);
        entity.setTxHash("txHash123");
        return entity;
    }

    /**
     * Create a RegistryNodeEntity for testing.
     */
    private RegistryNodeEntity createRegistryNode(String key, String next, ProtocolParamsEntity protocolParams) {
        RegistryNodeEntity entity = new RegistryNodeEntity();
        entity.setKey(key);
        entity.setNext(next);
        entity.setProtocolParams(protocolParams);
        entity.setLastSlot(12345L);
        entity.setLastTxHash("txHash123");
        entity.setLastBlockHeight(1000L);
        entity.setTransferLogicScript("script123");
        entity.setThirdPartyTransferLogicScript("script456");
        return entity;
    }
}
