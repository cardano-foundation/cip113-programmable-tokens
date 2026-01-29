package org.cardanofoundation.cip113.cip171;

import lombok.Getter;

import java.util.Optional;
import java.util.stream.Stream;

@Getter
public enum CompilerType {

    AIKEN(0), HELIOS(1), SCALUS(2), OPSHIN(3), PLUTARCH(4), PLINTH(5), PLUTUS(6),
    PLUTS(7);

    private final int compileId;

    CompilerType(int compileId) {
        this.compileId = compileId;
    }

    public static Optional<CompilerType> fromId(int id) {
        return Stream.of(values()).filter(compilerType -> compilerType.compileId == id).findFirst();
    }

}
