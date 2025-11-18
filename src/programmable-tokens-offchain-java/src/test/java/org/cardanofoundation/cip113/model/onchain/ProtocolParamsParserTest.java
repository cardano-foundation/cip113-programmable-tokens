package org.cardanofoundation.cip113.model.onchain;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

@Slf4j
class ProtocolParamsParserTest {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private final ProtocolParamsParser protocolParamsParser = new ProtocolParamsParser(OBJECT_MAPPER);

    @Test
    public void testOk() {
        var inlineDatum = "d8799f581c2584c485b40f65f3659dc94d36ee4389c3f95349f41437cb9b422160d87a9f581caaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102ffff";

        var protocolParamsOpt = protocolParamsParser.parse(inlineDatum);
        if (protocolParamsOpt.isEmpty()) {
            Assertions.fail();
        }

        var expected = ProtocolParams.builder()
                .registryNodePolicyId("2584c485b40f65f3659dc94d36ee4389c3f95349f41437cb9b422160")
                .programmableLogicBaseScriptHash("aaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102")
                .build();

        Assertions.assertEquals(expected, protocolParamsOpt.get());

    }

}