package org.cardanofoundation.cip113.service.substandard;

import org.cardanofoundation.cip113.exception.SubstandardNotFoundException;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Factory service for creating and managing substandard handlers.
 * Automatically registers all SubstandardHandler beans from Spring context.
 */
@Service
public class SubstandardHandlerFactory {

    private final Map<String, SubstandardHandler> handlers = new HashMap<>();

    /**
     * Constructor that auto-registers all SubstandardHandler beans
     *
     * @param handlerList List of all SubstandardHandler beans from Spring context
     */
    public SubstandardHandlerFactory(List<SubstandardHandler> handlerList) {
        for (SubstandardHandler handler : handlerList) {
            handlers.put(handler.getSubstandardId().toLowerCase(), handler);
        }
    }

    /**
     * Get a handler for the specified substandard
     *
     * @param substandardId The substandard identifier (e.g., "dummy", "bafin")
     * @return The handler for the substandard
     * @throws SubstandardNotFoundException if the substandard is not found
     */
    public SubstandardHandler getHandler(String substandardId) {
        String normalizedId = substandardId.toLowerCase();
        SubstandardHandler handler = handlers.get(normalizedId);

        if (handler == null) {
            throw new SubstandardNotFoundException(substandardId);
        }

        return handler;
    }

    /**
     * Check if a substandard handler is registered
     *
     * @param substandardId The substandard identifier
     * @return true if handler exists, false otherwise
     */
    public boolean hasHandler(String substandardId) {
        return handlers.containsKey(substandardId.toLowerCase());
    }

    /**
     * Get all registered substandard IDs
     *
     * @return Set of registered substandard IDs
     */
    public java.util.Set<String> getRegisteredSubstandards() {
        return handlers.keySet();
    }
}
