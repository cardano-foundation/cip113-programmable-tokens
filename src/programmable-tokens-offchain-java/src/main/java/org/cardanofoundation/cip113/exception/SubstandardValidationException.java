package org.cardanofoundation.cip113.exception;

/**
 * Exception thrown when substandard validation fails
 */
public class SubstandardValidationException extends SubstandardException {

    public SubstandardValidationException(String message) {
        super(message);
    }

    public SubstandardValidationException(String message, Throwable cause) {
        super(message, cause);
    }
}
