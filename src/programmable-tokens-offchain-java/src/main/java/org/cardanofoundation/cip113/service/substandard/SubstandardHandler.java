package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
import org.cardanofoundation.cip113.service.substandard.capabilities.BasicOperations;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable;

import java.util.Optional;
import java.util.Set;

/**
 * Base interface for handling different programmable token substandards.
 *
 * This interface defines the common contract for all substandard handlers.
 * Specific capabilities (basic operations, blacklist, seize, etc.) are defined
 * in separate interfaces that handlers can implement based on their features.
 *
 * <h2>Capability Interfaces:</h2>
 * <ul>
 *   <li>{@link BasicOperations} - Register, mint, burn, transfer (all handlers)</li>
 *   <li>{@link BlacklistManageable} - Blacklist init/add/remove (freeze functionality)</li>
 *   <li>{@link WhitelistManageable} - Whitelist init/add/remove (KYC/securities)</li>
 *   <li>{@link Seizeable} - Seize assets from blacklisted addresses</li>
 * </ul>
 *
 * <h2>Example Handler Implementations:</h2>
 * <ul>
 *   <li>DummySubstandardHandler implements SubstandardHandler, BasicOperations</li>
 *   <li>FreezeAndSeizeHandler implements SubstandardHandler, BasicOperations, BlacklistManageable, Seizeable</li>
 * </ul>
 */
public interface SubstandardHandler {

    /**
     * Returns the unique identifier for this substandard (e.g., "dummy", "freeze-and-seize")
     */
    String getSubstandardId();

    // ========== Capability Discovery Methods ==========

    /**
     * Check if this handler supports basic operations (register, mint, transfer).
     * All handlers should support this.
     */
    default boolean supportsBasicOperations() {
        return this instanceof BasicOperations;
    }

    /**
     * Check if this handler supports blacklist management (freeze/unfreeze).
     */
    default boolean supportsBlacklistManagement() {
        return this instanceof BlacklistManageable;
    }

    /**
     * Check if this handler supports whitelist management (KYC).
     */
    default boolean supportsWhitelistManagement() {
        return this instanceof WhitelistManageable;
    }

    /**
     * Check if this handler supports seize operations.
     */
    default boolean supportsSeize() {
        return this instanceof Seizeable;
    }

    /**
     * Get this handler as BasicOperations if supported.
     */
    default Optional<BasicOperations> asBasicOperations() {
        return this instanceof BasicOperations ops ? Optional.of(ops) : Optional.empty();
    }

    /**
     * Get this handler as BlacklistManageable if supported.
     */
    default Optional<BlacklistManageable> asBlacklistManageable() {
        return this instanceof BlacklistManageable mgr ? Optional.of(mgr) : Optional.empty();
    }

    /**
     * Get this handler as WhitelistManageable if supported.
     */
    default Optional<WhitelistManageable> asWhitelistManageable() {
        return this instanceof WhitelistManageable mgr ? Optional.of(mgr) : Optional.empty();
    }

    /**
     * Get this handler as Seizeable if supported.
     */
    default Optional<Seizeable> asSeizeable() {
        return this instanceof Seizeable s ? Optional.of(s) : Optional.empty();
    }
}
