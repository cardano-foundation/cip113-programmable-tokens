package org.cardanofoundation.cip113.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public record SubstandardValidator(
        String title,
        @JsonProperty("script_bytes") String scriptBytes,
        @JsonProperty("script_hash") String scriptHash
) {
}
