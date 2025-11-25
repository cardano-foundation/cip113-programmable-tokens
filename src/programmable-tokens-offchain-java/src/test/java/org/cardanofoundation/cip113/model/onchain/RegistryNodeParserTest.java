package org.cardanofoundation.cip113.model.onchain;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

@Slf4j
class RegistryNodeParserTest {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private final RegistryNodeParser registryNodeParser = new RegistryNodeParser(OBJECT_MAPPER);

    @Test
    public void testParseRegistryNode() {
        // Example inline datum for a registry node
        // This is based on the DirectorySetNode structure from the exploration
        var inlineDatum = "d8799f581c0befd1269cf3b5b41cce136c92c64b45dde93e4bfe11875839b713d1581effffffffffffffffffffffffffffffffffffffffffffffffffffffffd8799f581caaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102ffd8799f581cdef513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126103ff581c1234567890abcdef1234567890abcdef1234567890abcdef12345678ff";

        var registryNodeOpt = registryNodeParser.parse(inlineDatum);

        if (registryNodeOpt.isEmpty()) {
            Assertions.fail("Failed to parse registry node");
        }

        var registryNode = registryNodeOpt.get();

        // Verify parsed values
        Assertions.assertEquals("0befd1269cf3b5b41cce136c92c64b45dde93e4bfe11875839b713d1", registryNode.key());
        Assertions.assertEquals("ffffffffffffffffffffffffffffffffffffffffffffffffffffff", registryNode.next());
        Assertions.assertEquals("aaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102", registryNode.transferLogicScript());
        Assertions.assertEquals("def513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126103", registryNode.thirdPartyTransferLogicScript());
        Assertions.assertEquals("1234567890abcdef1234567890abcdef1234567890abcdef12345678", registryNode.globalStatePolicyId());
    }

    @Test
    public void testParseSentinelNode() {
        // Sentinel node has empty key
        var inlineDatum = "d8799f40581effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd8799f581caaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102ffd8799f581cdef513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126103ff40ff";

        var registryNodeOpt = registryNodeParser.parse(inlineDatum);

        if (registryNodeOpt.isEmpty()) {
            Assertions.fail("Failed to parse sentinel node");
        }

        var registryNode = registryNodeOpt.get();

        // Verify sentinel has empty key
        Assertions.assertEquals("", registryNode.key());
        Assertions.assertEquals("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", registryNode.next());
    }

    @Test
    public void testParseInvalidDatum() {
        var invalidDatum = "invalid_hex_data";

        var registryNodeOpt = registryNodeParser.parse(invalidDatum);

        // Should return empty on parse failure
        Assertions.assertTrue(registryNodeOpt.isEmpty());
    }
}
