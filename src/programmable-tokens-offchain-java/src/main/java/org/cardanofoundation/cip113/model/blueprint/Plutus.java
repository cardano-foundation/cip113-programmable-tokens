package org.cardanofoundation.cip113.model.blueprint;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public record Plutus(List<Validator> validators) {
}
