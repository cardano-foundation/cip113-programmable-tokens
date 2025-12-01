package org.cardanofoundation.cip113.controller;

import org.cardanofoundation.cip113.model.Substandard;
import org.cardanofoundation.cip113.model.SubstandardValidator;
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
import java.util.Optional;

import static org.hamcrest.Matchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Controller tests for SubstandardController endpoints.
 * Uses standalone MockMvc setup for fast, isolated unit testing.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("Substandard Controller Tests")
class SubstandardControllerTest {

    private MockMvc mockMvc;

    @Mock
    private SubstandardService substandardService;

    @InjectMocks
    private SubstandardController substandardController;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(substandardController)
                .addPlaceholderValue("apiPrefix", "/api/v1")
                .build();
    }

    @Nested
    @DisplayName("GET /api/v1/substandards")
    class GetAllSubstandards {

        @Test
        @DisplayName("should return empty list when no substandards exist")
        void shouldReturnEmptyListWhenNoSubstandards() throws Exception {
            // Given
            when(substandardService.getAllSubstandards()).thenReturn(Collections.emptyList());

            // When/Then
            mockMvc.perform(get("/api/v1/substandards")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                    .andExpect(jsonPath("$").isArray())
                    .andExpect(jsonPath("$", hasSize(0)));
        }

        @Test
        @DisplayName("should return list of substandards when they exist")
        void shouldReturnSubstandardsWhenExist() throws Exception {
            // Given
            List<Substandard> substandards = List.of(
                    createSubstandard("blacklist", List.of(
                            new SubstandardValidator("blacklist_mint", "script_bytes_1", "script_hash_1"),
                            new SubstandardValidator("blacklist_transfer", "script_bytes_2", "script_hash_2")
                    )),
                    createSubstandard("kyc", List.of(
                            new SubstandardValidator("kyc_mint", "script_bytes_3", "script_hash_3")
                    ))
            );
            when(substandardService.getAllSubstandards()).thenReturn(substandards);

            // When/Then
            mockMvc.perform(get("/api/v1/substandards")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                    .andExpect(jsonPath("$", hasSize(2)))
                    .andExpect(jsonPath("$[0].id").value("blacklist"))
                    .andExpect(jsonPath("$[0].validators", hasSize(2)))
                    .andExpect(jsonPath("$[0].validators[0].title").value("blacklist_mint"))
                    .andExpect(jsonPath("$[1].id").value("kyc"))
                    .andExpect(jsonPath("$[1].validators", hasSize(1)));
        }
    }

    @Nested
    @DisplayName("GET /api/v1/substandards/{id}")
    class GetSubstandardById {

        @Test
        @DisplayName("should return substandard when found")
        void shouldReturnSubstandardWhenFound() throws Exception {
            // Given
            Substandard substandard = createSubstandard("blacklist", List.of(
                    new SubstandardValidator("blacklist_mint", "script_bytes", "script_hash")
            ));
            when(substandardService.getSubstandardById("blacklist"))
                    .thenReturn(Optional.of(substandard));

            // When/Then
            mockMvc.perform(get("/api/v1/substandards/blacklist")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                    .andExpect(jsonPath("$.id").value("blacklist"))
                    .andExpect(jsonPath("$.validators").isArray())
                    .andExpect(jsonPath("$.validators", hasSize(1)))
                    .andExpect(jsonPath("$.validators[0].title").value("blacklist_mint"));
        }

        @Test
        @DisplayName("should return 404 when substandard not found")
        void shouldReturn404WhenNotFound() throws Exception {
            // Given
            when(substandardService.getSubstandardById("nonexistent"))
                    .thenReturn(Optional.empty());

            // When/Then
            mockMvc.perform(get("/api/v1/substandards/nonexistent")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("should handle special characters in ID")
        void shouldHandleSpecialCharactersInId() throws Exception {
            // Given
            when(substandardService.getSubstandardById("test-substandard_v1"))
                    .thenReturn(Optional.empty());

            // When/Then
            mockMvc.perform(get("/api/v1/substandards/test-substandard_v1")
                            .accept(MediaType.APPLICATION_JSON))
                    .andExpect(status().isNotFound());
        }
    }

    private Substandard createSubstandard(String id, List<SubstandardValidator> validators) {
        return new Substandard(id, validators);
    }
}
