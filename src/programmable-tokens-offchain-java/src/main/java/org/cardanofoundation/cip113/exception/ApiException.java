package org.cardanofoundation.cip113.exception;

import org.springframework.http.HttpStatus;

/**
 * Custom exception for API errors with HTTP status code.
 * Controllers can throw this exception to return a specific HTTP status and message.
 */
public class ApiException extends RuntimeException {

    private final HttpStatus status;

    /**
     * Create an API exception with the given status and message.
     *
     * @param status  the HTTP status code
     * @param message the error message
     */
    public ApiException(HttpStatus status, String message) {
        super(message);
        this.status = status;
    }

    /**
     * Create an API exception with the given status, message, and cause.
     *
     * @param status  the HTTP status code
     * @param message the error message
     * @param cause   the underlying cause
     */
    public ApiException(HttpStatus status, String message, Throwable cause) {
        super(message, cause);
        this.status = status;
    }

    /**
     * Get the HTTP status code for this exception.
     *
     * @return the HTTP status
     */
    public HttpStatus getStatus() {
        return status;
    }

    /**
     * Create a 400 Bad Request exception.
     *
     * @param message the error message
     * @return ApiException with BAD_REQUEST status
     */
    public static ApiException badRequest(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, message);
    }

    /**
     * Create a 404 Not Found exception.
     *
     * @param message the error message
     * @return ApiException with NOT_FOUND status
     */
    public static ApiException notFound(String message) {
        return new ApiException(HttpStatus.NOT_FOUND, message);
    }

    /**
     * Create a 409 Conflict exception.
     *
     * @param message the error message
     * @return ApiException with CONFLICT status
     */
    public static ApiException conflict(String message) {
        return new ApiException(HttpStatus.CONFLICT, message);
    }

    /**
     * Create a 500 Internal Server Error exception.
     *
     * @param message the error message
     * @return ApiException with INTERNAL_SERVER_ERROR status
     */
    public static ApiException internalError(String message) {
        return new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, message);
    }

    /**
     * Create a 500 Internal Server Error exception with cause.
     *
     * @param message the error message
     * @param cause the underlying cause
     * @return ApiException with INTERNAL_SERVER_ERROR status
     */
    public static ApiException internalError(String message, Throwable cause) {
        return new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, message, cause);
    }

    /**
     * Create a 503 Service Unavailable exception.
     *
     * @param message the error message
     * @return ApiException with SERVICE_UNAVAILABLE status
     */
    public static ApiException serviceUnavailable(String message) {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, message);
    }
}
