package org.cardanofoundation.cip113.model;

import java.util.List;

public record Substandard(
        String id,
        List<SubstandardValidator> validators
) {
}
