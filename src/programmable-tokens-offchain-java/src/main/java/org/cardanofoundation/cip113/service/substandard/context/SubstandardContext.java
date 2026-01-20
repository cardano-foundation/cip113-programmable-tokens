package org.cardanofoundation.cip113.service.substandard.context;

/**
 * Base interface for substandard-specific context/configuration.
 * <p>
 * Some substandards (like freeze-and-seize) can have multiple instances
 * (e.g., multiple stablecoins), each with their own configuration.
 * This context carries instance-specific parameters needed to build transactions.
 * <p>
 * Simple substandards like "dummy" don't need context and can use {@link EmptyContext}.
 */
public interface SubstandardContext {

    /**
     * Get the substandard ID this context is for.
     *
     * @return The substandard identifier (e.g., "freeze-and-seize", "dummy")
     */
    String getSubstandardId();

    /**
     * Empty context for substandards that don't need configuration.
     */
    record EmptyContext(String substandardId) implements SubstandardContext {
        @Override
        public String getSubstandardId() {
            return substandardId;
        }

        public static EmptyContext forSubstandard(String substandardId) {
            return new EmptyContext(substandardId);
        }
    }
}
