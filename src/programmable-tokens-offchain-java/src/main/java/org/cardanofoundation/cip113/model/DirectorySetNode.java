package org.cardanofoundation.cip113.model;

import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.util.HexUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;

import java.util.Optional;

@Slf4j
public record DirectorySetNode(String key,
                               String next,
                               // Note: transferLogicScript is stored as hex string of credential script hash
                               String transferLogicScript,
                               // Note: issuerLogicScript is stored as hex string of credential script hash
                               String issuerLogicScript,
                               String globalStateCs) {

    public static Optional<DirectorySetNode> fromInlineDatum(String inlineDatum) {
        try {
            var plutusData = PlutusData.deserialize(HexUtil.decodeHexString(inlineDatum));
            var om = new ObjectMapper();
            var json = om.readTree(om.writeValueAsString(plutusData));
            log.debug("Parsing DirectorySetNode from datum: {}", json);
            var key = json.path("fields").get(0).path("bytes").asText();
            var next = json.path("fields").get(1).path("bytes").asText();
            var transferLogicScript = json.path("fields")
                    .get(2)
                    .path("fields")
                    .get(0)
                    .path("bytes")
                    .asText();
            var issuerLogicScript = json.path("fields")
                    .get(3)
                    .path("fields")
                    .get(0)
                    .path("bytes")
                    .asText();
            var globalStateCs = json.path("fields").get(4).path("bytes").asText();
            return Optional.of(new DirectorySetNode(key, next, transferLogicScript, issuerLogicScript, globalStateCs));
        } catch (Exception e) {
            return Optional.empty();
        }
    }

}
