package org.cardanofoundation.cip113.model;

import com.bloxbean.cardano.client.address.Credential;
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

        // The datum contains empty hex strings ("40" = empty bytes) for the script fields
        // Credential.fromScript("") creates a credential with empty script hash
        var expectedTransferLogic = Credential.fromScript("");
        var expectedIssuerLogic = Credential.fromScript("");

        var result = fooOpt.get();

        // Verify basic fields
        Assertions.assertEquals("", result.key());
        Assertions.assertEquals("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", result.next());
        Assertions.assertEquals("", result.globalStateCs());

        // Verify credentials - compare the underlying bytes
        Assertions.assertArrayEquals(expectedTransferLogic.getBytes(), result.transferLogicScript().getBytes());
        Assertions.assertArrayEquals(expectedIssuerLogic.getBytes(), result.issuerLogicScript().getBytes());
    }

}
