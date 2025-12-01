package org.cardanofoundation.cip113.controller;

import org.cardanofoundation.cip113.model.Substandard;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.model.bootstrap.TxInput;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.Collections;
import java.util.List;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Controller tests for Healthcheck endpoints.
 * Uses standalone MockMvc setup for fast, isolated unit testing.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("Healthcheck Controller Tests")
class HealthcheckControllerTest {

    private MockMvc mockMvc;

    @Mock
    private ProtocolBootstrapService protocolBootstrapService;

    @Mock
    private SubstandardService substandardService;

    @InjectMocks
    private Healthcheck healthcheck;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(healthcheck).build();
    }

    @Nested
    @DisplayName("GET /healthcheck")
    class BasicHealthCheck {

        @Test
        @DisplayName("should return UP status with timestamp")
        void shouldReturnUpStatus() throws Exception {
            mockMvc.perform(get("/healthcheck")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                    .andExpect(jsonPath("$.status").value("UP"))
                    .andExpect(jsonPath("$.timestamp").exists())
                    .andExpect(jsonPath("$.timestamp").isString());
        }
    }

    @Nested
    @DisplayName("GET /healthcheck/details")
    class DetailedHealthCheck {

        @Test
        @DisplayName("should return detailed status when all components are healthy")
        void shouldReturnDetailedStatusWhenHealthy() throws Exception {
            // Given
            ProtocolBootstrapParams params = createValidProtocolParams();
            when(protocolBootstrapService.getProtocolBootstrapParams()).thenReturn(params);
            when(substandardService.getAllSubstandards()).thenReturn(List.of(
                    createTestSubstandard("test-substandard")
            ));

            // When/Then
            mockMvc.perform(get("/healthcheck/details")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                    .andExpect(jsonPath("$.status").value("UP"))
                    .andExpect(jsonPath("$.timestamp").exists())
                    .andExpect(jsonPath("$.protocolBootstrap.status").value("UP"))
                    .andExpect(jsonPath("$.protocolBootstrap.protocolParamsUtxo").value(true))
                    .andExpect(jsonPath("$.protocolBootstrap.issuanceUtxo").value(true))
                    .andExpect(jsonPath("$.protocolBootstrap.directoryUtxo").value(true))
                    .andExpect(jsonPath("$.substandards.status").value("UP"))
                    .andExpect(jsonPath("$.substandards.count").value(1));
        }

        @Test
        @DisplayName("should show DOWN status when protocol bootstrap fails")
        void shouldShowDownWhenProtocolBootstrapFails() throws Exception {
            // Given
            when(protocolBootstrapService.getProtocolBootstrapParams())
                    .thenThrow(new RuntimeException("Protocol not initialized"));
            when(substandardService.getAllSubstandards()).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get("/healthcheck/details")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("UP"))
                    .andExpect(jsonPath("$.protocolBootstrap.status").value("DOWN"))
                    .andExpect(jsonPath("$.protocolBootstrap.error").value("Protocol not initialized"))
                    .andExpect(jsonPath("$.substandards.status").value("UP"));
        }

        @Test
        @DisplayName("should show DOWN status when substandard service fails")
        void shouldShowDownWhenSubstandardsFails() throws Exception {
            // Given
            ProtocolBootstrapParams params = createValidProtocolParams();
            when(protocolBootstrapService.getProtocolBootstrapParams()).thenReturn(params);
            when(substandardService.getAllSubstandards())
                    .thenThrow(new RuntimeException("Substandards not available"));

            // When/Then
            mockMvc.perform(get("/healthcheck/details")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("UP"))
                    .andExpect(jsonPath("$.protocolBootstrap.status").value("UP"))
                    .andExpect(jsonPath("$.substandards.status").value("DOWN"))
                    .andExpect(jsonPath("$.substandards.error").value("Substandards not available"));
        }

        @Test
        @DisplayName("should handle null UTxO references gracefully")
        void shouldHandleNullUtxoReferences() throws Exception {
            // Given - params with null UTxO references
            ProtocolBootstrapParams params = new ProtocolBootstrapParams(
                    null, null, null, null, null, null, null, null, null, null, null, null
            );
            when(protocolBootstrapService.getProtocolBootstrapParams()).thenReturn(params);
            when(substandardService.getAllSubstandards()).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get("/healthcheck/details")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.protocolBootstrap.status").value("UP"))
                    .andExpect(jsonPath("$.protocolBootstrap.protocolParamsUtxo").value(false))
                    .andExpect(jsonPath("$.protocolBootstrap.issuanceUtxo").value(false))
                    .andExpect(jsonPath("$.protocolBootstrap.directoryUtxo").value(false));
        }
    }

    private Substandard createTestSubstandard(String id) {
        return new Substandard(id, Collections.emptyList());
    }

    private ProtocolBootstrapParams createValidProtocolParams() {
        TxInput protocolParamsUtxo = new TxInput("txhash1", 0);
        TxInput issuanceUtxo = new TxInput("txhash2", 1);
        TxInput directoryUtxo = new TxInput("txhash3", 2);

        return new ProtocolBootstrapParams(
                null, // protocolParams
                null, // programmableLogicGlobalPrams
                null, // programmableLogicBaseParams
                null, // issuanceParams
                null, // directoryMintParams
                null, // directorySpendParams
                null, // programmableBaseRefInput
                null, // programmableGlobalRefInput
                protocolParamsUtxo,
                directoryUtxo,
                issuanceUtxo,
                null  // txHash
        );
    }
}
