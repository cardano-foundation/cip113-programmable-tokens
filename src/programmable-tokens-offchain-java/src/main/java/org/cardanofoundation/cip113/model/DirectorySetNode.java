package org.cardanofoundation.cip113.model;

import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.util.HexUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;

import java.util.Optional;

@Slf4j
public record DirectorySetNode(String key,
                               String next,
                               Credential transferLogicScript,
                               Credential issuerLogicScript,
                               String globalStateCs) {

    public static Optional<DirectorySetNode> fromInlineDatum(String inlineDatum) {
        try {
            var plutusData = PlutusData.deserialize(HexUtil.decodeHexString(inlineDatum));
            var om = new ObjectMapper();
            var json = om.readTree(om.writeValueAsString(plutusData));
            log.debug("Parsing DirectorySetNode datum: {}", json);
            var key = json.path("fields").get(0).path("bytes").asText();
            var next = json.path("fields").get(1).path("bytes").asText();
            var transferLogicScriptHex = json.path("fields")
                    .get(2)
                    .path("fields")
                    .get(0)
                    .path("bytes")
                    .asText();
            var issuerLogicScriptHex = json.path("fields")
                    .get(3)
                    .path("fields")
                    .get(0)
                    .path("bytes")
                    .asText();
            var globalStateCs = json.path("fields").get(4).path("bytes").asText();

            var transferLogicScript = Credential.fromScript(transferLogicScriptHex);
            var issuerLogicScript = Credential.fromScript(issuerLogicScriptHex);

            return Optional.of(new DirectorySetNode(key, next, transferLogicScript, issuerLogicScript, globalStateCs));
        } catch (Exception e) {
            log.warn("Failed to parse DirectorySetNode from inline datum: {}", e.getMessage());
            return Optional.empty();
        }
    }

}
