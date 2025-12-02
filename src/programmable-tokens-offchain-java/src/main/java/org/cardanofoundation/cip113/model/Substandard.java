package org.cardanofoundation.cip113.model;

import java.util.List;

/**
 * Represents a CIP-113 substandard with its associated validators.
 *
 * <p>A substandard defines a category of programmable token behavior
 * (e.g., blacklist, whitelist, transfer-restricted). Each substandard
 * contains one or more validator scripts that implement the logic.</p>
 *
 * @param id         unique identifier for the substandard (e.g., "blacklist")
 * @param validators list of validators implementing this substandard
 */
public record Substandard(
        String id,
        List<SubstandardValidator> validators
) {
}
