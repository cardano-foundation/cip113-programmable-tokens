package org.cardanofoundation.cip113.model;

import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

@Slf4j
class DirectorySetNodeTest {

    private static final String DATUM_HEX = "d8799f40581effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd8799f40ffd8799f40ff40ff";

    @Test
    public void deserialise() {
        var fooOpt = DirectorySetNode.fromInlineDatum(DATUM_HEX);
        if (fooOpt.isEmpty()) {
            Assertions.fail("could not deserialise datum");
        }
        Assertions.assertEquals(new DirectorySetNode("", "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", "", "", ""), fooOpt.get());
    }

}