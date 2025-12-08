package org.cardanofoundation.cip113.exception;

/**
 * Exception thrown when a requested substandard is not found or not registered
 */
public class SubstandardNotFoundException extends SubstandardException {

    public SubstandardNotFoundException(String substandardId) {
        super("Substandard not found: " + substandardId);
    }

    public SubstandardNotFoundException(String substandardId, Throwable cause) {
        super("Substandard not found: " + substandardId, cause);
    }
}
