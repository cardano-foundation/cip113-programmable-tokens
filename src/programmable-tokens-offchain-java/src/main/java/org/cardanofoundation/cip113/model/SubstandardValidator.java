package org.cardanofoundation.cip113.model;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * A single validator within a substandard blueprint.
 *
 * <p>Represents a compiled Plutus script from an Aiken blueprint. Each validator
 * has a specific purpose (minting, spending, withdrawing) and contains the
 * compiled CBOR bytes ready for on-chain execution.
 *
 * <h2>Validator Title Format</h2>
 * <p>The title follows Aiken's naming convention:
 * {@code module.validator.purpose} (e.g., "transfer_logic.transfer_logic.withdraw")
 *
 * <h2>Script Hash</h2>
 * <p>The script hash is computed as Blake2b-224 of the script bytes and serves
 * as the script credential/policy ID on-chain.
 *
 * @param title Full validator title from the Aiken blueprint
 * @param scriptBytes Compiled CBOR hex of the Plutus script
 * @param scriptHash Blake2b-224 hash of the script (28 bytes = 56 hex chars)
 * @see Substandard
 */
public record SubstandardValidator(
        String title,
        @JsonProperty("script_bytes") String scriptBytes,
        @JsonProperty("script_hash") String scriptHash
) {
}
