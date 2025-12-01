package org.cardanofoundation.cip113.exception;

import org.springframework.http.HttpStatus;

/**
 * Custom exception for API errors with HTTP status code.
 * Controllers can throw this exception to return a specific HTTP status and message.
 */
public class ApiException extends RuntimeException {

    private final HttpStatus status;

    public ApiException(HttpStatus status, String message) {
        super(message);
        this.status = status;
    }

    public ApiException(HttpStatus status, String message, Throwable cause) {
        super(message, cause);
        this.status = status;
    }

    public HttpStatus getStatus() {
        return status;
    }

    /**
     * Create a 400 Bad Request exception.
     */
    public static ApiException badRequest(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, message);
    }

    /**
     * Create a 404 Not Found exception.
     */
    public static ApiException notFound(String message) {
        return new ApiException(HttpStatus.NOT_FOUND, message);
    }

    /**
     * Create a 409 Conflict exception.
     */
    public static ApiException conflict(String message) {
        return new ApiException(HttpStatus.CONFLICT, message);
    }

    /**
     * Create a 500 Internal Server Error exception.
     */
    public static ApiException internalError(String message) {
        return new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, message);
    }

    /**
     * Create a 500 Internal Server Error exception with cause.
     */
    public static ApiException internalError(String message, Throwable cause) {
        return new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, message, cause);
    }

    /**
     * Create a 503 Service Unavailable exception.
     */
    public static ApiException serviceUnavailable(String message) {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, message);
    }
}
