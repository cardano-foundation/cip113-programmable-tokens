package org.cardanofoundation.cip113.model.blueprint;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record Validator(String title, String compiledCode) {
}
