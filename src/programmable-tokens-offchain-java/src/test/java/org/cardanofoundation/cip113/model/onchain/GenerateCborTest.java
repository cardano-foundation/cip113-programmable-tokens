package org.cardanofoundation.cip113.model.onchain;

import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.util.HexUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

/**
 * Utility test to generate valid CBOR test data for RegistryNodeParserTest.
 * Run with: ./gradlew test --tests "*.GenerateCborTest"
 */
public class GenerateCborTest {

    @Test
    void generateRegistryNodeCbor() throws Exception {
        ObjectMapper mapper = new ObjectMapper();

        // Credential is Constr 1 for Script (Constr 0 for PubKey)
        var transferLogicCred = ConstrPlutusData.of(1,
            BytesPlutusData.of(HexUtil.decodeHexString("aaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102")));
        var thirdPartyCred = ConstrPlutusData.of(1,
            BytesPlutusData.of(HexUtil.decodeHexString("def513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126103")));

        var registryNode = ConstrPlutusData.of(0,
            BytesPlutusData.of(HexUtil.decodeHexString("0befd1269cf3b5b41cce136c92c64b45dde93e4bfe11875839b713d1")),
            BytesPlutusData.of(HexUtil.decodeHexString("ffffffffffffffffffffffffffffffffffffffffffffffffffffff")),
            transferLogicCred,
            thirdPartyCred,
            BytesPlutusData.of(HexUtil.decodeHexString("1234567890abcdef1234567890abcdef1234567890abcdef12345678"))
        );

        String cborHex = registryNode.serializeToHex();
        System.out.println("\n=== REGISTRY NODE CBOR ===");
        System.out.println(cborHex);

        // Parse back and show JSON structure
        var parsed = PlutusData.deserialize(HexUtil.decodeHexString(cborHex));
        var json = mapper.writerWithDefaultPrettyPrinter().writeValueAsString(parsed);
        System.out.println("\n=== REGISTRY NODE JSON ===");
        System.out.println(json);

        // Sentinel node (empty key)
        var sentinelNode = ConstrPlutusData.of(0,
            BytesPlutusData.of(new byte[0]),  // empty key
            BytesPlutusData.of(HexUtil.decodeHexString("ffffffffffffffffffffffffffffffffffffffffffffffffffffff")),
            transferLogicCred,
            thirdPartyCred,
            BytesPlutusData.of(new byte[0])  // empty global state
        );

        cborHex = sentinelNode.serializeToHex();
        System.out.println("\n=== SENTINEL NODE CBOR ===");
        System.out.println(cborHex);

        // Parse back and show JSON structure
        parsed = PlutusData.deserialize(HexUtil.decodeHexString(cborHex));
        json = mapper.writerWithDefaultPrettyPrinter().writeValueAsString(parsed);
        System.out.println("\n=== SENTINEL NODE JSON ===");
        System.out.println(json);
        System.out.println();
    }
}
