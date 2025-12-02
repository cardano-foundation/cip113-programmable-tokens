package org.cardanofoundation.cip113.model;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Represents a validator within a CIP-113 substandard.
 *
 * <p>Each validator is a Plutus script that implements specific
 * programmable token logic (e.g., transfer validation, minting rules).
 * The script bytes are loaded from the Aiken blueprint (plutus.json).</p>
 *
 * @param title       human-readable title from the blueprint (e.g., "example_transfer_logic.spend")
 * @param scriptBytes hex-encoded compiled Plutus script bytes
 * @param scriptHash  blake2b-224 hash of the script (56 hex chars)
 */
public record SubstandardValidator(
        String title,
        @JsonProperty("script_bytes") String scriptBytes,
        @JsonProperty("script_hash") String scriptHash
) {
}
