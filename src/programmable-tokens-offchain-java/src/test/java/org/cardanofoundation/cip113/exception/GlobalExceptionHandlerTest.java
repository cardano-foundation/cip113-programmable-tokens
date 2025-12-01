package org.cardanofoundation.cip113.exception;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.validation.BeanPropertyBindingResult;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.context.request.ServletWebRequest;
import org.springframework.web.context.request.WebRequest;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for GlobalExceptionHandler.
 * Verifies consistent error response format across different exception types.
 */
@DisplayName("GlobalExceptionHandler Tests")
class GlobalExceptionHandlerTest {

    private GlobalExceptionHandler handler;
    private WebRequest webRequest;

    @BeforeEach
    void setUp() {
        handler = new GlobalExceptionHandler();
        webRequest = new ServletWebRequest(new MockHttpServletRequest());
    }

    @Test
    @DisplayName("should handle ApiException with correct status")
    void shouldHandleApiExceptionWithCorrectStatus() {
        // Given
        ApiException exception = ApiException.badRequest("Invalid token name");

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleApiException(exception, webRequest);

        // Then
        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("Invalid token name", response.getBody().get("message"));
        assertEquals(400, response.getBody().get("status"));
        assertEquals("Bad Request", response.getBody().get("error"));
        assertNotNull(response.getBody().get("timestamp"));
    }

    @Test
    @DisplayName("should handle ApiException with internal server error")
    void shouldHandleApiExceptionWithInternalServerError() {
        // Given
        ApiException exception = ApiException.internalError("Database connection failed");

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleApiException(exception, webRequest);

        // Then
        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertEquals("Database connection failed", response.getBody().get("message"));
        assertEquals(500, response.getBody().get("status"));
    }

    @Test
    @DisplayName("should handle ApiException with not found status")
    void shouldHandleApiExceptionWithNotFound() {
        // Given
        ApiException exception = ApiException.notFound("Token not found");

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleApiException(exception, webRequest);

        // Then
        assertEquals(HttpStatus.NOT_FOUND, response.getStatusCode());
        assertEquals("Token not found", response.getBody().get("message"));
        assertEquals(404, response.getBody().get("status"));
    }

    @Test
    @DisplayName("should handle IllegalArgumentException as bad request")
    void shouldHandleIllegalArgumentExceptionAsBadRequest() {
        // Given
        IllegalArgumentException exception = new IllegalArgumentException("Invalid parameter value");

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleIllegalArgumentException(exception, webRequest);

        // Then
        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertEquals("Invalid parameter value", response.getBody().get("message"));
        assertEquals(400, response.getBody().get("status"));
    }

    @Test
    @DisplayName("should handle IllegalStateException as conflict")
    void shouldHandleIllegalStateExceptionAsConflict() {
        // Given
        IllegalStateException exception = new IllegalStateException("Token already minted");

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleIllegalStateException(exception, webRequest);

        // Then
        assertEquals(HttpStatus.CONFLICT, response.getStatusCode());
        assertEquals("Token already minted", response.getBody().get("message"));
        assertEquals(409, response.getBody().get("status"));
    }

    @Test
    @DisplayName("should handle RuntimeException as internal server error with generic message")
    void shouldHandleRuntimeExceptionAsInternalServerError() {
        // Given
        RuntimeException exception = new RuntimeException("Unexpected database error");

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleRuntimeException(exception, webRequest);

        // Then
        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertEquals("An unexpected error occurred. Please try again later.", response.getBody().get("message"));
        assertEquals(500, response.getBody().get("status"));
    }

    @Test
    @DisplayName("should handle validation exception with field errors")
    void shouldHandleValidationExceptionWithFieldErrors() throws NoSuchMethodException {
        // Given - Create a mock validation error
        Object target = new Object();
        BeanPropertyBindingResult bindingResult = new BeanPropertyBindingResult(target, "request");
        bindingResult.addError(new FieldError("request", "assetName", "Asset name is required"));
        bindingResult.addError(new FieldError("request", "quantity", "Quantity must be positive"));

        MethodArgumentNotValidException exception = new MethodArgumentNotValidException(
                null, bindingResult);

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleValidationException(exception, webRequest);

        // Then
        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        String message = (String) response.getBody().get("message");
        assertTrue(message.contains("assetName"));
        assertTrue(message.contains("quantity"));
    }

    @Test
    @DisplayName("should include timestamp in error response")
    void shouldIncludeTimestampInErrorResponse() {
        // Given
        ApiException exception = ApiException.badRequest("Test error");

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleApiException(exception, webRequest);

        // Then
        assertNotNull(response.getBody().get("timestamp"));
    }

    @Test
    @DisplayName("should handle service unavailable exception")
    void shouldHandleServiceUnavailableException() {
        // Given
        ApiException exception = ApiException.serviceUnavailable("Blockchain node unavailable");

        // When
        ResponseEntity<Map<String, Object>> response = handler.handleApiException(exception, webRequest);

        // Then
        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, response.getStatusCode());
        assertEquals("Blockchain node unavailable", response.getBody().get("message"));
        assertEquals(503, response.getBody().get("status"));
    }
}
