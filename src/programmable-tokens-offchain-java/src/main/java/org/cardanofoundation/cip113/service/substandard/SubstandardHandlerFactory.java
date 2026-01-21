package org.cardanofoundation.cip113.service.substandard;

import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.service.substandard.capabilities.BasicOperations;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable;
import org.cardanofoundation.cip113.service.substandard.context.FreezeAndSeizeContext;
import org.cardanofoundation.cip113.service.substandard.context.SubstandardContext;
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Service;

import java.util.*;

/**
 * Factory service for creating and managing substandard handlers.
 *
 * <p>This factory supports two types of handlers:</p>
 * <ul>
 *   <li><b>Simple handlers</b> (like Dummy) - Singleton, no context needed</li>
 *   <li><b>Context-aware handlers</b> (like FreezeAndSeize) - Prototype scope, require context</li>
 * </ul>
 *
 * <h2>Usage Examples:</h2>
 * <pre>{@code
 * // Simple handler (Dummy)
 * SubstandardHandler handler = factory.getHandler("dummy");
 *
 * // Context-aware handler (FreezeAndSeize)
 * var context = FreezeAndSeizeContext.forExistingDeployment(...);
 * SubstandardHandler handler = factory.getHandler("freeze-and-seize", context);
 *
 * // Check capabilities
 * if (handler.supportsSeize()) {
 *     handler.asSeizeable().get().buildSeizeTransaction(...);
 * }
 * }</pre>
 */
@Service
@Slf4j
public class SubstandardHandlerFactory {

    private final Map<String, SubstandardHandler> simpleHandlers = new HashMap<>();
    private final Set<String> contextAwareSubstandards = new HashSet<>();
    private final ApplicationContext applicationContext;

    /**
     * Constructor that auto-registers all SubstandardHandler beans.
     *
     * @param handlerList        List of all SubstandardHandler beans from Spring context
     * @param applicationContext Spring application context for creating prototype beans
     */
    public SubstandardHandlerFactory(List<SubstandardHandler> handlerList,
                                     ApplicationContext applicationContext) {
        this.applicationContext = applicationContext;

        for (SubstandardHandler handler : handlerList) {
            String id = handler.getSubstandardId().toLowerCase();

            // FreezeAndSeizeHandler is prototype-scoped, needs context
            if (handler instanceof FreezeAndSeizeHandler) {
                contextAwareSubstandards.add(id);
                log.info("Registered context-aware substandard: {}", id);
            } else {
                simpleHandlers.put(id, handler);
                log.info("Registered simple substandard: {} (capabilities: {})",
                        id, describeCapabilities(handler));
            }
        }
    }

    /**
     * Get a handler for the specified substandard (for simple handlers).
     *
     * @param substandardId The substandard identifier (e.g., "dummy")
     * @return The handler for the substandard, or null if not found
     * @throws IllegalStateException if the substandard requires context
     */
    public SubstandardHandler getHandler(String substandardId) {
        String normalizedId = substandardId.toLowerCase();

        if (contextAwareSubstandards.contains(normalizedId)) {
            throw new IllegalStateException(
                    "Substandard '" + substandardId + "' requires context. " +
                    "Use getHandler(substandardId, context) instead.");
        }

        return simpleHandlers.get(normalizedId);
    }

    /**
     * Get a handler for the specified substandard with context.
     *
     * @param substandardId The substandard identifier (e.g., "freeze-and-seize")
     * @param context       The context for this handler instance
     * @return The configured handler for the substandard
     */
    public SubstandardHandler getHandler(String substandardId, SubstandardContext context) {
        String normalizedId = substandardId.toLowerCase();

        // Simple handlers don't need context
        if (simpleHandlers.containsKey(normalizedId)) {
            log.debug("Returning simple handler for '{}' (context ignored)", substandardId);
            return simpleHandlers.get(normalizedId);
        }

        // Context-aware handlers
        if (contextAwareSubstandards.contains(normalizedId)) {
            return createContextAwareHandler(normalizedId, context);
        }

        log.warn("No handler found for substandard: {}", substandardId);
        return null;
    }

    /**
     * Create a new instance of a context-aware handler with the given context.
     */
    private SubstandardHandler createContextAwareHandler(String substandardId, SubstandardContext context) {
        if ("freeze-and-seize".equals(substandardId)) {
            if (!(context instanceof FreezeAndSeizeContext fasContext)) {
                throw new IllegalArgumentException(
                        "freeze-and-seize handler requires FreezeAndSeizeContext, got: " +
                        (context != null ? context.getClass().getSimpleName() : "null"));
            }

            // Get a new prototype instance from Spring
            FreezeAndSeizeHandler handler = applicationContext.getBean(FreezeAndSeizeHandler.class);
            handler.setContext(fasContext);
            log.debug("Created FreezeAndSeizeHandler with context: {}", fasContext);
            return handler;
        }

        throw new IllegalStateException("Unknown context-aware substandard: " + substandardId);
    }

    /**
     * Check if a substandard handler is registered.
     *
     * @param substandardId The substandard identifier
     * @return true if handler exists, false otherwise
     */
    public boolean hasHandler(String substandardId) {
        String normalizedId = substandardId.toLowerCase();
        return simpleHandlers.containsKey(normalizedId) ||
               contextAwareSubstandards.contains(normalizedId);
    }

    /**
     * Check if a substandard requires context.
     *
     * @param substandardId The substandard identifier
     * @return true if context is required, false otherwise
     */
    public boolean requiresContext(String substandardId) {
        return contextAwareSubstandards.contains(substandardId.toLowerCase());
    }

    /**
     * Get all registered substandard IDs.
     *
     * @return Set of registered substandard IDs
     */
    public Set<String> getRegisteredSubstandards() {
        Set<String> all = new HashSet<>(simpleHandlers.keySet());
        all.addAll(contextAwareSubstandards);
        return all;
    }

    /**
     * Get capability description for a handler.
     */
    private String describeCapabilities(SubstandardHandler handler) {
        List<String> caps = new ArrayList<>();
        if (handler instanceof BasicOperations) caps.add("BasicOperations");
        if (handler instanceof BlacklistManageable) caps.add("BlacklistManageable");
        if (handler instanceof WhitelistManageable) caps.add("WhitelistManageable");
        if (handler instanceof Seizeable) caps.add("Seizeable");
        return String.join(", ", caps);
    }

    // ========== Convenience Methods for Capability Access ==========

    /**
     * Get a handler's BasicOperations capability if supported.
     */
    @SuppressWarnings("rawtypes")
    public Optional<BasicOperations> getBasicOperations(String substandardId) {
        var handler = getHandler(substandardId);
        return handler != null ? handler.asBasicOperations() : Optional.empty();
    }

    /**
     * Get a handler's BasicOperations capability with context if supported.
     */
    @SuppressWarnings("rawtypes")
    public Optional<BasicOperations> getBasicOperations(String substandardId, SubstandardContext context) {
        var handler = getHandler(substandardId, context);
        return handler != null ? handler.asBasicOperations() : Optional.empty();
    }

    /**
     * Get a handler's BlacklistManageable capability if supported.
     */
    public Optional<BlacklistManageable> getBlacklistManageable(String substandardId, SubstandardContext context) {
        var handler = getHandler(substandardId, context);
        return handler != null ? handler.asBlacklistManageable() : Optional.empty();
    }

    /**
     * Get a handler's Seizeable capability if supported.
     */
    public Optional<Seizeable> getSeizeable(String substandardId, SubstandardContext context) {
        var handler = getHandler(substandardId, context);
        return handler != null ? handler.asSeizeable() : Optional.empty();
    }
}
