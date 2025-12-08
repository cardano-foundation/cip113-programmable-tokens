package org.cardanofoundation.cip113.exception;

/**
 * Base exception for substandard-related errors
 */
public class SubstandardException extends RuntimeException {

    public SubstandardException(String message) {
        super(message);
    }

    public SubstandardException(String message, Throwable cause) {
        super(message, cause);
    }
}
